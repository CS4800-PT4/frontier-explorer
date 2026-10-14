import array
import math

import numpy as np
import rclpy
from geometry_msgs.msg import Point, PoseStamped
from nav_msgs.msg import OccupancyGrid, Odometry
from rcl_interfaces.msg import ParameterDescriptor
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import Image, PointCloud2, PointField
from std_msgs.msg import ColorRGBA, String
from std_srvs.srv import Trigger
from visualization_msgs.msg import Marker, MarkerArray

from frontier_explorer.frontier_detector import FrontierDetector
from frontier_explorer.frontier_ranker import FrontierRanker
from frontier_explorer.map_view import OCCUPIED, UNKNOWN, MapView


def cloud_to_xyz(msg):
    """PointCloud2 with float32 x, y, z fields -> N x 3 numpy array."""
    offsets = {f.name: f.offset for f in msg.fields}
    n = msg.width * msg.height
    if n == 0 or not all(k in offsets for k in ('x', 'y', 'z')):
        return np.zeros((0, 3), dtype=np.float32)
    dtype = np.dtype({'names': ['x', 'y', 'z'], 'formats': ['<f4', '<f4', '<f4'],
                      'offsets': [offsets['x'], offsets['y'], offsets['z']],
                      'itemsize': msg.point_step})
    pts = np.frombuffer(msg.data, dtype=dtype, count=n)
    xyz = np.stack([pts['x'], pts['y'], pts['z']], axis=1)
    return xyz[np.isfinite(xyz).all(axis=1)]


def grid_to_cloud(view, frame_id, stamp):
    """Seen cells as a flat PointCloud2: intensity 0 = free, 1 = occupied.

    RViz's Map display uses a shader that fails on some WSL graphics drivers, while
    PointCloud2 always draws, so the demo view uses this.
    """
    rows, cols = np.nonzero(view.grid != UNKNOWN)
    pts = np.zeros(len(rows), dtype=[('x', '<f4'), ('y', '<f4'), ('z', '<f4'), ('i', '<f4')])
    pts['x'] = view.origin_x + (cols + 0.5) * view.res
    pts['y'] = view.origin_y + (rows + 0.5) * view.res
    pts['i'] = view.grid[rows, cols] == OCCUPIED
    msg = PointCloud2()
    msg.header.frame_id = frame_id
    msg.header.stamp = stamp
    msg.height = 1
    msg.width = len(pts)
    msg.fields = [PointField(name=n, offset=4 * k, datatype=PointField.FLOAT32, count=1)
                  for k, n in enumerate(('x', 'y', 'z', 'intensity'))]
    msg.point_step = 16
    msg.row_step = 16 * len(pts)
    msg.is_dense = True
    msg.data = array.array('B', pts.tobytes())
    return msg


def yaw_from_quaternion(q):
    return math.atan2(2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z))


def color(r, g, b, a=1.0):
    return ColorRGBA(r=r, g=g, b=b, a=a)


class ExplorerNode(Node):
    """Builds the explored map, finds frontiers and picks the next goal.

    Callbacks only store the latest message; the timer does all the work.
    R1 only shows the goal in RViz. Calling /frontier/go_best sends it to EGO once.
    """

    def __init__(self):
        super().__init__('explorer_node')
        p = self.param
        cloud_topic = p('cloud_topic', '/drone_0_grid/grid_map/occupancy_inflate')
        odom_topic = p('odom_topic', '/mavros/local_position/odom')
        goal_topic = p('goal_topic', '/goal_pose')
        self.frame_id = p('frame_id', 'map')
        self.goal_z = p('goal_z', 1.0)  # EGO flies every goal at 1.0 m anyway
        self.max_yaw_rate = p('max_yaw_rate', 0.5)  # rad/s, no sweeping while turning faster
        # EGO republishes its cloud every 0.11 s even when no depth frame came in, so the
        # sweep waits for real depth frames on the topic EGO uses (none turns this check off)
        depth_topic = p('depth_topic', '/depth_camera_bestef')
        depth_topic = '' if depth_topic == 'none' else depth_topic
        self.depth_max_age = p('depth_max_age', 0.3)
        self.arrive_dist = p('arrive_dist', 0.6)
        rate = p('rate', 2.0)

        # Map size must match EGO's (single_uav_gazebo.launch.py: 40 x 40 m)
        self.view = MapView(
            size_x=p('map_size_x', 40.0), size_y=p('map_size_y', 40.0),
            resolution=p('resolution', 0.1), band_low=p('band_low', 0.7),
            band_high=p('band_high', 1.3), fov_deg=p('fov_deg', 73.0),
            max_range=p('max_range', 4.0), min_sweep_z=p('min_sweep_z', 0.5))
        self.detector = FrontierDetector(min_size=p('min_frontier_size', 8),
                                         split_size=p('split_size', 2.0))
        self.ranker = FrontierRanker(
            min_dist=p('min_goal_dist', 1.0), clearance=p('clearance', 0.3),
            edge_margin=p('edge_margin', 1.0))

        self.cloud = None
        self.odom = None
        self.frontiers = []
        self.best = None
        self.failed = []       # goals sent that the drone never reached
        self.last_goal = None
        self.last_log = 0.0
        self.depth_check = bool(depth_topic)
        self.last_depth = None

        self.create_subscription(PointCloud2, cloud_topic, self.cloud_cb, qos_profile_sensor_data)
        self.create_subscription(Odometry, odom_topic, self.odom_cb, qos_profile_sensor_data)
        if depth_topic:
            # raw=True: only the arrival time is used, so the image is never decoded
            self.create_subscription(Image, depth_topic, self.depth_cb, qos_profile_sensor_data,
                                     raw=True)
        self.map_pub = self.create_publisher(OccupancyGrid, '/frontier/map', 1)
        self.map_cloud_pub = self.create_publisher(PointCloud2, '/frontier/map_cloud', 1)
        self.marker_pub = self.create_publisher(MarkerArray, '/frontier/markers', 1)
        self.best_pub = self.create_publisher(PoseStamped, '/frontier/best_goal', 1)
        self.status_pub = self.create_publisher(String, '/frontier/status', 1)
        self.goal_pub = self.create_publisher(PoseStamped, goal_topic, 10)
        self.create_service(Trigger, '/frontier/go_best', self.go_best_cb)
        self.create_timer(1.0 / rate, self.tick)
        self.get_logger().info(f'explorer_node up: cloud {cloud_topic}, odom {odom_topic}')

    def param(self, name, default):
        """Declare a parameter that also accepts 4 for 4.0 (and the other way), then cast."""
        value = self.declare_parameter(
            name, default, ParameterDescriptor(dynamic_typing=True)).value
        return type(default)(value)

    def cloud_cb(self, msg):
        self.cloud = msg

    def odom_cb(self, msg):
        self.odom = msg

    def depth_cb(self, raw_msg):
        self.last_depth = self.get_clock().now().nanoseconds * 1e-9

    def depth_fresh(self):
        if not self.depth_check:
            return True
        if self.last_depth is None:
            return False
        return self.get_clock().now().nanoseconds * 1e-9 - self.last_depth < self.depth_max_age

    def tick(self):
        turning = False
        if self.odom is not None:
            pos = self.odom.pose.pose.position
            self.view.update_pose(pos.x, pos.y, pos.z,
                                  yaw_from_quaternion(self.odom.pose.pose.orientation))
            turning = abs(self.odom.twist.twist.angular.z) > self.max_yaw_rate
        if self.cloud is not None:
            self.view.update_cloud(cloud_to_xyz(self.cloud))
            self.cloud = None
            # Only sweep with a fresh cloud built from fresh depth, and not mid-turn
            # (see MapView.sweep)
            if not turning and self.depth_fresh():
                self.view.sweep()
        self.frontiers = self.detector.detect(self.view)
        self.best = None
        if self.view.pose is not None:
            x, y, _, yaw = self.view.pose
            self.best = self.ranker.best(self.frontiers, self.view, (x, y, yaw), self.failed)
        self.publish()

    def go_best_cb(self, request, response):
        # EGO never says a goal failed. If the drone is still away from the last goal when
        # the next one is asked for, count it as failed so the ranker skips it from now on.
        if self.last_goal is not None and self.view.pose is not None:
            gx, gy = self.last_goal
            if math.hypot(self.view.pose[0] - gx, self.view.pose[1] - gy) > self.arrive_dist:
                self.failed.append(self.last_goal)
                self.get_logger().info(f'goal ({gx:.2f}, {gy:.2f}) not reached, skipping it')
                x, y, _, yaw = self.view.pose
                self.best = self.ranker.best(self.frontiers, self.view, (x, y, yaw), self.failed)
            self.last_goal = None
        if self.best is None:
            response.success = False
            response.message = 'no usable frontier'
            return response
        self.goal_pub.publish(self.pose_msg(self.best.x, self.best.y))
        self.last_goal = (self.best.x, self.best.y)
        response.success = True
        response.message = f'goal {self.best.x:.2f} {self.best.y:.2f}'
        self.get_logger().info(f'sent frontier goal ({self.best.x:.2f}, {self.best.y:.2f})')
        return response

    def pose_msg(self, x, y):
        msg = PoseStamped()
        msg.header.frame_id = self.frame_id
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.pose.position.x = float(x)
        msg.pose.position.y = float(y)
        msg.pose.position.z = float(self.goal_z)
        msg.pose.orientation.w = 1.0
        return msg

    def publish(self):
        now = self.get_clock().now()
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
        if self.map_cloud_pub.get_subscription_count() > 0:
            self.map_cloud_pub.publish(grid_to_cloud(self.view, self.frame_id, grid.header.stamp))

        if self.best is not None:
            self.best_pub.publish(self.pose_msg(self.best.x, self.best.y))
        self.marker_pub.publish(self.markers(now))

        best = f'{self.best.x:.2f},{self.best.y:.2f}' if self.best else 'none'
        status = (f'known_m2={self.view.known_area():.1f} frontiers={len(self.frontiers)} '
                  f'best={best} failed={len(self.failed)}')
        self.status_pub.publish(String(data=status))
        t = now.nanoseconds * 1e-9
        if t - self.last_log > 5.0:
            self.last_log = t
            self.get_logger().info(status)

    def markers(self, now):
        stamp = now.to_msg()
        out = MarkerArray()
        clear = Marker()
        clear.action = Marker.DELETEALL
        out.markers.append(clear)

        def marker(ns, mtype, scale, col):
            m = Marker()
            m.header.frame_id = self.frame_id
            m.header.stamp = stamp
            m.ns = ns
            m.id = len(out.markers)
            m.type = mtype
            m.pose.orientation.w = 1.0
            m.scale.x = m.scale.y = m.scale.z = scale
            m.color = col
            out.markers.append(m)
            return m

        z = self.goal_z
        if self.frontiers:
            cells = marker('frontier_cells', Marker.CUBE_LIST, self.view.res, color(1.0, 0.55, 0.0))
            goals = marker('frontier_goals', Marker.SPHERE_LIST, 0.25, color(0.2, 0.4, 1.0))
            for f in self.frontiers:
                for r, c in f.cells:
                    x, y = self.view.cell_center(r, c)
                    cells.points.append(Point(x=x, y=y, z=0.05))
                goals.points.append(Point(x=f.x, y=f.y, z=z))
        if self.best is not None and self.view.pose is not None:
            m = marker('best_goal', Marker.SPHERE, 0.5, color(0.1, 0.8, 0.2))
            m.pose.position = Point(x=self.best.x, y=self.best.y, z=z)
            line = marker('best_goal', Marker.LINE_STRIP, 0.05, color(0.1, 0.8, 0.2))
            line.points = [Point(x=self.view.pose[0], y=self.view.pose[1], z=self.view.pose[2]),
                           Point(x=self.best.x, y=self.best.y, z=z)]
        if self.view.pose is not None:
            text = marker('status', Marker.TEXT_VIEW_FACING, 0.35, color(0.1, 0.1, 0.1))
            text.pose.position = Point(x=self.view.pose[0], y=self.view.pose[1],
                                       z=self.view.pose[2] + 0.8)
            text.text = f'{self.view.known_area():.0f} m2 seen, {len(self.frontiers)} frontiers'
        return out


def main(args=None):
    rclpy.init(args=args)
    node = ExplorerNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
