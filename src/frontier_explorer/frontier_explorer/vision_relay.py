import math
import time

import rclpy
from geometry_msgs.msg import PoseWithCovarianceStamped
from nav_msgs.msg import Odometry
from rcl_interfaces.msg import ParameterDescriptor
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data

try:  # built with the ZED wrapper; not there in the sim
    from zed_msgs.msg import PosTrackStatus
except ImportError:
    PosTrackStatus = None

# zed_msgs/PosTrackStatus: odometry_status OK is 0. Older wrappers only have the
# deprecated status field, where OK is 1.
ODOM_OK = 0
OLD_STATUS_OK = 1


def tracking_ok(status):
    """True if a ZED pose/status message says position tracking is working."""
    if hasattr(status, 'odometry_status'):
        return status.odometry_status == ODOM_OK
    return status.status == OLD_STATUS_OK


def pose_from_odom(msg, frame_id):
    """ZED odometry -> the pose MAVROS forwards to PX4, or None if it is unusable.

    MAVROS does the ENU -> NED conversion. The camera's offset from the flight
    controller is set in PX4 (EKF2_EV_POS_X/Y/Z), so the pose is passed as is. The ZED's
    covariance goes along, so PX4 can see when tracking gets worse.
    """
    p, q = msg.pose.pose.position, msg.pose.pose.orientation
    values = (p.x, p.y, p.z, q.w, q.x, q.y, q.z) + tuple(msg.pose.covariance)
    if not all(math.isfinite(v) for v in values):
        return None
    if abs(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z - 1.0) > 0.01:
        return None
    out = PoseWithCovarianceStamped()
    out.header.stamp = msg.header.stamp
    out.header.frame_id = frame_id
    out.pose = msg.pose
    return out


class VisionRelay(Node):
    """Forwards the ZED's position tracking to PX4 through MAVROS (indoor position).

    Assumes the camera is mounted level, facing forward. When the ZED loses tracking it
    keeps publishing its last pose, so the relay also reads the ZED's tracking status and
    stops forwarding until tracking is back. PX4 then sees vision loss and fails safe
    instead of holding a frozen position while the drone drifts.
    """

    def __init__(self):
        super().__init__('vision_relay')
        p = self.param
        in_topic = p('odom_in', '/zed/zed_node/odom')
        status_topic = p('status_in', '/zed/zed_node/pose/status')
        out_topic = p('pose_out', '/mavros/vision_pose/pose_cov')
        self.frame_id = p('frame_id', 'odom')
        self.max_gap = p('max_gap', 0.5)
        self.last_in = None
        self.sent = 0
        self.dropped = 0
        self.held = 0
        self.lost = False
        self.tracking = None   # last ZED tracking status, None until one arrives
        self.last_status = None
        self.use_status = bool(status_topic)
        self.pub = self.create_publisher(PoseWithCovarianceStamped, out_topic, 10)
        self.create_subscription(Odometry, in_topic, self.odom_cb, qos_profile_sensor_data)
        log = self.get_logger()
        if self.use_status and PosTrackStatus is None:
            log.warn('zed_msgs is not installed, so tracking loss can not be seen: forwarding '
                     'every pose (fine in the sim, not on the drone)')
            self.use_status = False
        if self.use_status:
            self.create_subscription(PosTrackStatus, status_topic, self.status_cb,
                                     qos_profile_sensor_data)
        self.create_timer(0.25, self.check)
        log.info(f'vision relay: {in_topic} -> {out_topic}'
                 + (f', gated on {status_topic}' if self.use_status else ''))

    def param(self, name, default):
        value = self.declare_parameter(
            name, default, ParameterDescriptor(dynamic_typing=True)).value
        return type(default)(value)

    def status_cb(self, msg):
        ok = tracking_ok(msg)
        self.last_status = time.monotonic()
        if ok != self.tracking:
            if ok:
                self.get_logger().info('ZED tracking OK: forwarding poses to PX4')
            else:
                self.get_logger().warn('ZED lost tracking: holding poses back so PX4 sees '
                                       'vision loss')
        self.tracking = ok

    def tracking_now(self):
        if not self.use_status:
            return True
        fresh = self.last_status is not None and time.monotonic() - self.last_status < 2 * self.max_gap
        return fresh and self.tracking

    def odom_cb(self, msg):
        out = pose_from_odom(msg, self.frame_id)
        if out is None:
            self.dropped += 1
            return
        if not self.tracking_now():
            self.held += 1
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
            why = 'no ZED tracking status' if self.use_status and self.last_status is None \
                else 'no tracked ZED pose'
            self.get_logger().warn(f'{why} for {self.max_gap} s: PX4 will lose vision '
                                   f'(sent {self.sent}, dropped {self.dropped}, '
                                   f'held while not tracking {self.held})')


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
