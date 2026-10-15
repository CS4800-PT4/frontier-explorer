import math
import time

import rclpy
from geometry_msgs.msg import PoseStamped
from nav_msgs.msg import Odometry
from rcl_interfaces.msg import ParameterDescriptor
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data


def pose_from_odom(msg, frame_id):
    """ZED odometry -> the PoseStamped MAVROS forwards to PX4, or None if it has a NaN.

    MAVROS does the ENU -> NED conversion. The camera's offset from the flight
    controller is set in PX4 (EKF2_EV_POS_X/Y/Z), so the pose is passed as is.
    """
    p, q = msg.pose.pose.position, msg.pose.pose.orientation
    values = (p.x, p.y, p.z, q.w, q.x, q.y, q.z)
    if not all(math.isfinite(v) for v in values):
        return None
    if abs(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z - 1.0) > 0.01:
        return None
    out = PoseStamped()
    out.header.stamp = msg.header.stamp
    out.header.frame_id = frame_id
    out.pose = msg.pose.pose
    return out


class VisionRelay(Node):
    """Forwards the ZED's position tracking to PX4 through MAVROS (indoor position).

    Assumes the camera is mounted level, facing forward. Logs when the ZED stops
    sending poses, which is what PX4 sees as vision loss.
    """

    def __init__(self):
        super().__init__('vision_relay')
        p = self.param
        in_topic = p('odom_in', '/zed/zed_node/odom')
        out_topic = p('pose_out', '/mavros/vision_pose/pose')
        self.frame_id = p('frame_id', 'odom')
        self.max_gap = p('max_gap', 0.5)
        self.last_in = None
        self.sent = 0
        self.dropped = 0
        self.lost = False
        self.pub = self.create_publisher(PoseStamped, out_topic, 10)
        self.create_subscription(Odometry, in_topic, self.odom_cb, qos_profile_sensor_data)
        self.create_timer(0.25, self.check)
        self.get_logger().info(f'vision relay: {in_topic} -> {out_topic}')

    def param(self, name, default):
        value = self.declare_parameter(
            name, default, ParameterDescriptor(dynamic_typing=True)).value
        return type(default)(value)

    def odom_cb(self, msg):
        out = pose_from_odom(msg, self.frame_id)
        if out is None:
            self.dropped += 1
            return
        self.pub.publish(out)
        self.sent += 1
        self.last_in = time.monotonic()
        if self.lost:
            self.lost = False
            self.get_logger().info('ZED poses are back')

    def check(self):
        gap = None if self.last_in is None else time.monotonic() - self.last_in
        if (gap is None or gap > self.max_gap) and not self.lost:
            self.lost = True
            self.get_logger().warn(f'no ZED pose for {self.max_gap} s: PX4 will lose vision '
                                   f'(sent {self.sent}, dropped {self.dropped})')


def main(args=None):
    rclpy.init(args=args)
    node = VisionRelay()
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
