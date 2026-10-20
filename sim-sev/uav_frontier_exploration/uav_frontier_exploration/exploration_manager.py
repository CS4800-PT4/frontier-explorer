# Our Main Node

import rclpy
from rclpy.node import Node
from nav_msgs.msg import OccupancyGrid, Odometry
from sensor_msgs.msg import PointCloud2
from geometry_msgs.msg import PoseStamped
import numpy as np

from .frontier_detector import FrontierDetector
from .frontier_filter import FrontierFilter
from .frontier_ranker import FrontierRanker
from .goal_selector import GoalSelector
from .metrics_tracker import MetricsTracker
from .frontier_visualizer import FrontierVisualizer
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy


class ExplorationManager(Node):
    def __init__(self):
        super().__init__('exploration_manager')
        self.detector = FrontierDetector()
        self.filter = FrontierFilter()
        self.ranker = FrontierRanker()
        self.selector = GoalSelector()
        self.metrics = MetricsTracker()
        self.visualizer = FrontierVisualizer(self)
        self.current_goal = None
        self.latest_grid = None
        self.latest_pose = None

        odom_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10
        )
        # These are the Subscribers must adjust topic names to match the stack
        self.create_subscription(PointCloud2, '/drone_0_grid/grid_map/occupancy_inflate', self.on_map_callback, 10)
        self.create_subscription(Odometry, '/mavros/local_position/odom', self.on_pose_callback, odom_qos)
        # Publisher that ego planner already listens to
        self.goal_pub = self.create_publisher(PoseStamped, '/goal_pose', 10)
        self.create_timer(2.0, self.run_exploration_cycle)
        self.get_logger().info('ExplorationManager started')

    def on_map_callback(self, msg: PointCloud2):
        self.latest_grid = msg

    def on_pose_callback(self, msg: Odometry):
        self.latest_pose = msg.pose.pose

    def run_exploration_cycle(self):
        if self.latest_grid is None or self.latest_pose is None:
            return

        points = self._pointcloud2_to_xyz(self.latest_grid)
        if points is None or len(points) == 0:
            self.get_logger().info('No points')
            return

        pose = np.array([
            self.latest_pose.position.x,
            self.latest_pose.position.y,
            self.latest_pose.position.z,
        ])

        # Detect
        frontiers = self.detector.detect_from_cloud(points, pose)
        self.get_logger().info(f'points={len(points)}  frontiers={len(frontiers)}')

        # Filter
        # Dummy grid / origin / resolution for now (PointCloud2 path)
        valid = self.filter.filter(
            frontiers,
            np.zeros((1, 1), dtype=np.int8),
            np.array([0.0, 0.0]),
            0.1,
            pose
        ) if frontiers else []
        self.get_logger().info(f'valid={len(valid)}')

        # Rank
        scored = self.ranker.rank(valid, pose) if valid else []
        self.get_logger().info(f'scored={len(scored)}')

        # Select Goal (selector already returns a PoseStamped)
        goal = self.selector.select(scored) if scored else None

        if goal is not None:
            goal.header.stamp = self.get_clock().now().to_msg()
            goal.pose.position.z = float(pose[2]) + 0.3

            # Reject goal if any occupancy point is within 0.6 m
            gx = goal.pose.position.x
            gy = goal.pose.position.y
            gz = goal.pose.position.z
            dists = np.sqrt((points[:, 0] - gx)**2 + (points[:, 1] - gy)**2 + (points[:, 2] - gz)**2)
            if np.any(dists < 0.6):
                self.get_logger().info(f'Goal too close to obstacle, skipped: {gx:.2f}, {gy:.2f}')
                return

            publish = True
            now = self.get_clock().now()

            if self.current_goal is not None:
                dx = goal.pose.position.x - self.current_goal.pose.position.x
                dy = goal.pose.position.y - self.current_goal.pose.position.y
                dist_sq = dx * dx + dy * dy

                # Require a larger move (1.5 m) before publishing a new goal
                if dist_sq < 2.25:
                    publish = False

            # Also wait at least 8 seconds since the last published goal
            if hasattr(self, 'last_goal_time'):
                elapsed = (now - self.last_goal_time).nanoseconds / 1e9
                if elapsed < 8.0:
                    publish = False

            if publish:
                self.goal_pub.publish(goal)
                self.current_goal = goal
                self.last_goal_time = now
                self.visualizer.publish_markers(valid, scored[0].frontier)
                self.metrics.update(scored[0].frontier, pose)
                self.get_logger().info(
                    f'Published goal: {goal.pose.position.x:.2f}, {goal.pose.position.y:.2f}'
                )

        # Check Completion
        # if self.check_completion(valid):
        #     self.get_logger().info('Exploration complete')

    def _pointcloud2_to_xyz(self, cloud_msg):
        try:
            from sensor_msgs_py import point_cloud2
            pts = point_cloud2.read_points(
                cloud_msg,
                field_names=('x', 'y', 'z'),
                skip_nans=True
            )
            return np.array([[p[0], p[1], p[2]] for p in pts], dtype=np.float32)
        except Exception as e:
            self.get_logger().warn(f'PointCloud2 conversion failed: {e}')
            return None

    def check_completion(self, frontiers) -> bool:
        return len(frontiers) == 0


def main(args=None):
    rclpy.init(args=args)
    node = ExplorationManager()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()