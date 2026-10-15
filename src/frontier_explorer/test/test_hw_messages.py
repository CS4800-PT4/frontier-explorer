import math

import numpy as np
import pytest

# Needs ROS sourced (source /opt/ros/humble/setup.bash), skipped otherwise
pytest.importorskip('rclpy')

from nav_msgs.msg import Odometry  # noqa: E402

from frontier_explorer.extrinsic_node import extrinsic_msg  # noqa: E402
from frontier_explorer.mount import cam2body, quaternion_to_rotation  # noqa: E402
from frontier_explorer.vision_relay import pose_from_odom  # noqa: E402


def test_extrinsic_message_is_what_ego_reads():
    msg = extrinsic_msg(0.12, -0.02, 0.05, math.radians(20))
    o, p = msg.pose.pose.orientation, msg.pose.pose.position
    # EGO: Eigen::Quaterniond(w, x, y, z).toRotationMatrix() and position as the offset
    t = np.eye(4)
    t[:3, :3] = quaternion_to_rotation(o.w, o.x, o.y, o.z)
    t[:3, 3] = (p.x, p.y, p.z)
    assert np.allclose(t, cam2body(0.12, -0.02, 0.05, math.radians(20)))


def odom(x=1.0, y=2.0, z=0.5, w=1.0, qz=0.0):
    msg = Odometry()
    msg.header.stamp.sec = 42
    msg.header.frame_id = 'zed_odom'
    msg.pose.pose.position.x, msg.pose.pose.position.y, msg.pose.pose.position.z = x, y, z
    msg.pose.pose.orientation.w, msg.pose.pose.orientation.z = w, qz
    return msg


def test_relay_keeps_pose_and_stamp():
    out = pose_from_odom(odom(), 'odom')
    assert out.header.stamp.sec == 42
    assert out.header.frame_id == 'odom'
    assert (out.pose.position.x, out.pose.position.y, out.pose.position.z) == (1.0, 2.0, 0.5)
    s = math.sqrt(0.5)
    out = pose_from_odom(odom(w=s, qz=s), 'odom')
    assert math.isclose(out.pose.orientation.z, s)


def test_relay_drops_bad_poses():
    assert pose_from_odom(odom(x=float('nan')), 'odom') is None
    assert pose_from_odom(odom(w=0.0), 'odom') is None        # not a rotation
    assert pose_from_odom(odom(w=float('inf')), 'odom') is None
