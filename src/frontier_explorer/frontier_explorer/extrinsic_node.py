import math

import rclpy
from nav_msgs.msg import Odometry
from rcl_interfaces.msg import ParameterDescriptor
from rclpy.node import Node

from frontier_explorer.mount import cam2body, rotation_to_quaternion


def extrinsic_msg(x, y, z, pitch):
    """The Odometry message EGO reads as cam2body: orientation = rotation, position = offset."""
    t = cam2body(x, y, z, pitch)
    w, qx, qy, qz = rotation_to_quaternion(t[:3, :3])
    msg = Odometry()
    msg.header.frame_id = 'body'
    msg.child_frame_id = 'camera_optical'
    msg.pose.pose.position.x, msg.pose.pose.position.y, msg.pose.pose.position.z = x, y, z
    o = msg.pose.pose.orientation
    o.w, o.x, o.y, o.z = w, qx, qy, qz
    return msg


class ExtrinsicNode(Node):
    """Tells EGO where the depth camera sits on the drone.

    EGO only reads the mount from /vins_estimator/extrinsic and keeps the last one, so
    this publishes it once a second (EGO may start after this node).
    """

    def __init__(self):
        super().__init__('extrinsic_node')
        p = self.param
        x, y, z = p('cam_x', 0.0), p('cam_y', 0.0), p('cam_z', 0.0)
        pitch = math.radians(p('cam_pitch_deg', 0.0))
        self.msg = extrinsic_msg(x, y, z, pitch)
        self.pub = self.create_publisher(Odometry, '/vins_estimator/extrinsic', 10)
        self.create_timer(1.0, self.tick)
        self.get_logger().info(
            f'camera mount: x={x:.3f} y={y:.3f} z={z:.3f} m, pitch {math.degrees(pitch):.1f} deg down')

    def param(self, name, default):
        value = self.declare_parameter(
            name, default, ParameterDescriptor(dynamic_typing=True)).value
        return type(default)(value)

    def tick(self):
        self.msg.header.stamp = self.get_clock().now().to_msg()
        self.pub.publish(self.msg)


def main(args=None):
    rclpy.init(args=args)
    node = ExtrinsicNode()
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
