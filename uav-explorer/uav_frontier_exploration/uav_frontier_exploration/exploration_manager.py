# ExplorationManager: Main Node. Builds the map (MapView), finds and ranks frontiers,
# publishes the map, markers and best goal, and sends the goal to EGO on /frontier/go_best

import array
import math

import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data           # best-effort QoS for sensor topics
from rcl_interfaces.msg import ParameterDescriptor      # lets params accept 4 or 4.0
from geometry_msgs.msg import PoseStamped               # goal message for EGO
from nav_msgs.msg import OccupancyGrid, Odometry        # coverage map out, drone pose in
from sensor_msgs.msg import Image, PointCloud2          # depth (timing only), EGO's cloud
from std_msgs.msg import String                         # status text topic
from std_srvs.srv import Trigger                        # go_best service type

from .frontier_detector import FrontierDetector, MapView
from .frontier_filter import FrontierFilter
from .frontier_ranker import FrontierRanker
from .goal_selector import GoalSelector
from .metrics_tracker import MetricsTracker
from .frontier_visualizer import FrontierVisualizer
from .frontier import ScoredFrontier


def cloud_to_xyz(msg):
    """Turn EGO's PointCloud2 into an N x 3 numpy array of (x, y, z)."""
    # Where x, y, z, sit inside each point's bytes
    offsets = {f.name: f.offset for f in msg.fields}
    n = msg.width * msg.height
    # Empty cloud or missing fields: return an empty array
    if n == 0 or not all(k in offsets for k in ('x', 'y', 'z')):
        return np.zeros((0, 3), dtype=np.float32)
    # Describe one point's layout so numpy can read all points at once (no Python loop)
    dtype = np.dtype({'names': ['x', 'y', 'z'], 'formats': ['<f4', '<f4', '<f4'], 'offsets': [offsets['x'], offsets['y'], offsets['z']],'itemsize': msg.point_step})
    pts = np.frombuffer(msg.data, dtype=dtype, count=n)
    xyz = np.stack([pts['x'], pts['y'], pts['z']], axis=1)
    # Drop any NaN or infinite points
    return xyz[np.isfinite(xyz).all(axis=1)]

def yaw_from_quaternion(q):
    """Drone heading in radians (0 = facing +x), from the odem orientation."""
    return math.atan2(2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z))



class ExplorationManager(Node):
    """Callbacks only save the latest message; the timer (run_exploration_cycle) does the work. The best goal is only shown in RViz until /frontier/go_best sends it to EGO."""

    def __init__(self):
        super().__init__('exploration_manager')
        p = self.param

        # --- Topics (defaults = real drone; override with -p or the launch file) ---
        cloud_topic = p('cloud_topic', '/drone_0_grid/grid_map/occupancy_inflate')
        odom_topic = p('odom_topic', '/mavros/local_position/odom')
        goal_topic = p('goal_topic', '/goal_pose')
        # Depth is only used to know a fresh camera frame came in ('none' turns the check off)
        depth_topic = p('depth_topic', '/depth_camera_bestef')
        depth_topic = '' if depth_topic == 'none' else depth_topic

        # --- Behavior settings ---
        self.frame_id = p('frame_id', 'map')            # frame for map, markers and goals
        self.goal_z = p('goal_z', 1.0)                  # flight height for goals (m)
        self.max_yaw_rate = p('max_yaw_rate', 0.5)      # no sweeping while turning faster (rad/s)
        self.depth_max_age = p('depth_max_age', 0.3)    # depth older than this = stale (s)
        self.arrive_dist = p('arrive_dist', 0.6)        # within this of a goal = reached (m)
        rate = p('rate', 2.0)                           # cycles per second

        # --- Our map: must match EGO's map size (40 x 40 m) ---
        self.view = MapView(
            size_x=p('map_size_x', 40.0), size_y=p('map_size_y', 40.0),
            resolution=p('resolution', 0.1), band_low=p('band_low', 0.7),
            band_high=p('band_high', 1.3), fov_deg=p('fov_deg', 73.0),
            max_range=p('max_range', 4.0), min_sweep_z=p('min_sweep_z', 0.5)
        )

        # --- Pipeline pieces (detect -> filter -> rank -> select) ---
        self.detector = FrontierDetector(min_size=p('min_frontier_size', 8), split_size=p('split_size', 2.0))
        self.filter = FrontierFilter(min_dist=p('min_goal_dist', 1.0), clearance=p('clearance', 0.3), edge_margin=p('edge_margin', 1.0))
        self.ranker = FrontierRanker()
        self.selector = GoalSelector(frame_id=self.frame_id, goal_z=self.goal_z)
        self.metrics = MetricsTracker()
        self.visualizer = FrontierVisualizer(self, frame_id=self.frame_id, goal_z=self.goal_z)

        # --- State that changes while running ---
        self.cloud = None                       # latest EGO cloud (cleared after use)
        self.odom = None                        # latest drone odometry
        self.last_depth = None                  # time the last depth frame arrived
        self.depth_check = bool(depth_topic)
        self.valid = []                         # usable frontiers this cycle
        self.best = None                        # best Frontier this cycle (or None)
        self.failed = []                        # goals sent that the drone never reached
        self.last_goal = None                   # last goal sent to EGO (x, y)
        self.last_log = 0.0                     # last time the status was logged (s)

        # --- Subscribers (sensor QoS = best effort, matches MAVROS / EGO) ---
        self.create_subscription(PointCloud2, cloud_topic, self.on_map_callback, qos_profile_sensor_data)
        self.create_subscription(Odometry, odom_topic, self.on_pose_callback, qos_profile_sensor_data)

        if depth_topic:
            # raw=True: never decode the image, only its arrival time matters
            self.create_subscription(Image, depth_topic, self.on_depth_callback, qos_profile_sensor_data, raw=True)

        # --- Publishes ---
        self.map_pub = self.create_publisher(OccupancyGrid, '/frontier/map', 1)         # coverage map
        self.best_pub = self.create_publisher(PoseStamped, '/frontier/best_goal', 1)    # shown in RViz only
        self.status_pub = self.create_publisher(String, '/frontier/status', 1)          # text status
        self.goal_pub = self.create_publisher(PoseStamped, goal_topic, 10)              # EGO's goal input

        # --- Service: call it to send the best goal to EGO once ---
        self.create_service(Trigger, '/frontier/go_best', self.go_best_callback)

        # --- Main loop timer ---
        self.create_timer(1.0 / rate, self.run_exploration_cycle)
        self.get_logger().info(f'ExplorationManager up: cloud {cloud_topic}, odom {odom_topic}')

    def param(self, name, default):
        """Declare a ROS parameter (accepts 4 or 4.0) and return it as default's type."""
        value = self.declare_parameter(name, default, ParameterDescriptor(dynamic_typing=True)).value
        return type(default)(value)

    # --- Callbacks: only save the newest data, the timer does the work ---

    def on_map_callback(self, msg: PointCloud2):
        # Newest occupied-point cloud from EGO
        self.cloud = msg

    def on_pose_callback(self, msg: Odometry):
        # Newest drone pose + velocity from MAVROS (whole msg: we need twist for turn rate)
        self.odom = msg

    def on_depth_callback(self, raw_msg):
        # Only record WHEN a depth frame arrived (image is never decoded)
        self.last_depth = self.get_clock().now().nanoseconds * 1e-9

    def depth_fresh(self) -> bool:
        """True if a depth frame came in within depth_max_age (or the check is off)."""
        if not self.depth_check:
            return True
        if self.last_depth is None:
            return False
        now = self.get_clock().now().nanoseconds * 1e-9
        return now - self.last_depth < self.depth_max_age

    def run_exploration_cycle(self):
        """Runs at 2 Hz: update map -> detect -> filter -> rank -> pick best -> publish. Never sends a goal to EGO by itself (that's go_best_callback)."""

        # 1. Pose: give MapView where the drone is and which way it faces
        turning = False
        if self.odom is not None:
            pos = self.odom.pose.pose.position
            yaw = yaw_from_quaternion(self.odom.pose.pose.orientation)
            self.view.update_pose(pos.x, pos.y, pos.z, yaw)
            # Spinning faster than max_yaw_rate? Then don't trust the sweep this cycle
            turning = abs(self.odom.twist.twist.angular.z) > self.max_yaw_rate

        # 2. Map: add EGO's newest obstacles, then mark what the camera sees as free
        if self.cloud is not None:
            self.view.update_cloud(cloud_to_xyz(self.cloud))
            self.cloud = None      # use each cloud once
            if not turning and self.depth_fresh():
                self.view.sweep()

        # 3. Frontiers: find them all, then keep only the safe ones
        frontiers = self.detector.detect(self.view)
        self.valid = []
        self.best = None
        if self.view.pose is not None:
            x, y, _, yaw = self.view.pose
            self.valid = self.filter.filter(frontiers, self.view, (x, y), self.failed)

            # 4. Rank (lowest cost first) and pick the best
            scored = self.ranker.rank(self.valid, (x, y, yaw), self.view.res)
            if scored:
                self.best = scored[0].frontier

        # 5. Track explored area
        self.metrics.update(self.view.known_area())

        # 6. Publish map, markers, best goal and status (RViz only, not EGO)
        self.publish_outputs()

    def go_best_callback(self, request, response):
        """/frontier/go_best: send the current best frontier to EGO, once."""

        # EGO never reports failure. If we're still far from the LAST goal when asked
        # for a new one, count that goal as failed so the filter skips it from now on.
        if self.last_goal is not None and self.view.pose is not None:
            gx, gy = self.last_goal
            x, y, _, yaw = self.view.pose
            if math.hypot(x - gx, y - gy) > self.arrive_dist:
                self.failed.append(self.last_goal)
                self.get_logger().info(f'goal ({gx:.2f}, {gy:.2f}) not reached, skipping it')
                # Re-picked the best now that this spot is excluded
                self.valid = self.filter.filter(self.valid, self.view, (x, y), self.failed)
                scored = self.ranker.rank(self.valid,(x, y, yaw), self.view.res)
                self.best = scored[0].frontier if scored else None
            self.last_goal = None

        # Nothing usable: tell the caller instead of sending a bad goal
        if self.best is None:
            response.success = False
            response.message = 'no usable frontier'
            return response

        # Build the goal (map frame, goal_z) and send it to EGO
        goal = self.selector.select([ScoredFrontier(frontier=self.best, score=0.0)])
        goal.header.stamp = self.get_clock().now().to_msg()
        self.goal_pub.publish(goal)
        self.last_goal = (goal.pose.position.x, goal.pose.position.y)

        response.success = True
        response.message = f'goal {self.last_goal[0]:.2f} {self.last_goal[1]:.2f}'
        self.get_logger().info(f'sent frontier goal ({self.last_goal[0]:.2f}, {self.last_goal[1]:.2f})')
        return response

    def publish_outputs(self):
        """Publish everything RViz needs each cycle. Never sends a goal to EGO."""
        now = self.get_clock().now()

        # Coverage map: MapView's grid as an OccupancyGrid (-1 unknown, 0 free, 100 wall)
        grid = OccupancyGrid()
        grid.header.frame_id = self.frame_id
        grid.header.stamp = now.to_msg()
        grid.info.resolution = float(self.view.res)
        grid.info.width = self.view.width
        grid.info.height = self.view.height
        grid.info.origin.position.x = self.view.origin_x
        grid.info.origin.position.y = self.view.origin_y
        grid.info.origin.orientation.w = 1.0
        grid.data = array.array('b', self.view.grid.tobytes())
        self.map_pub.publish(grid)

        # Best goal for RViz only (EGO doesn't listen to this topic)
        if self.best is not None:
            best_msg = self.selector.select([ScoredFrontier(frontier=self.best, score=0.0)])
            best_msg.header.stamp = now.to_msg()
            self.best_pub.publish(best_msg)

        # Markers: frontier cells, goals, chosen goal, status text
        self.visualizer.publish_markers(self.valid, self.best, self.view)

        # Status line on /frontier/status, also logged every 5 s
        best = (f'{self.best.position[0]:.2f},{self.best.position[1]:.2f}' if self.best is not None else 'none')
        status = (f'known_m2={self.view.known_area():.1f} frontiers={len(self.valid)} best={best} failed={len(self.failed)}')
        self.status_pub.publish(String(data=status))
        t = now.nanoseconds * 1e-9
        if t - self.last_log > 5.0:
            self.last_log = t
            self.get_logger().info(status)


def main(args=None):
    rclpy.init(args=args)
    node = ExplorationManager()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():          # avoid double-shutdown error on Ctrl+C
            rclpy.shutdown()


if __name__ == '__main__':
    main()