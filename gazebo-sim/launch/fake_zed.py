#!/usr/bin/env python3
"""Stand-in for the ZED wrapper in the sim, so the hardware launch can be tested in WSL.

Republishes the Gazebo depth camera and the drone's odometry under the ZED topic names:
  /depth_camera_bestef        -> /zed/zed_node/depth/depth_registered (+ depth/camera_info)
  /mavros/local_position/odom -> /zed/zed_node/odom
The camera_info uses the intrinsics EGO is given in the sim (advanced_param.launch.py).
"""
import rclpy
from nav_msgs.msg import Odometry
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo, Image

# EGO's defaults in advanced_param.launch.py, which the sim runs with
FX = FY = 387.229248046875
CX, CY = 321.04638671875, 243.44969177246094
NS = '/zed/zed_node'


class FakeZed(Node):
    def __init__(self):
        super().__init__('fake_zed')
        self.depth_pub = self.create_publisher(Image, NS + '/depth/depth_registered', 10)
        self.info_pub = self.create_publisher(CameraInfo, NS + '/depth/camera_info', 10)
        self.odom_pub = self.create_publisher(Odometry, NS + '/odom', 10)
        self.create_subscription(Image, '/depth_camera_bestef', self.depth_cb, qos_profile_sensor_data)
        self.create_subscription(Odometry, '/mavros/local_position/odom', self.odom_cb,
                                 qos_profile_sensor_data)

    def depth_cb(self, msg):
        msg.header.frame_id = 'zed_left_camera_optical_frame'
        self.depth_pub.publish(msg)
        info = CameraInfo()
        info.header = msg.header
        info.width, info.height = msg.width, msg.height
        info.k = [FX, 0.0, CX, 0.0, FY, CY, 0.0, 0.0, 1.0]
        self.info_pub.publish(info)

    def odom_cb(self, msg):
        msg.header.frame_id = 'odom'
        self.odom_pub.publish(msg)


def main():
    rclpy.init()
    node = FakeZed()
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
