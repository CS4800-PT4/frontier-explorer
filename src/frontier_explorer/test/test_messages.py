import numpy as np
import pytest

# Needs ROS sourced (source /opt/ros/humble/setup.bash), skipped otherwise
pytest.importorskip('rclpy')

from builtin_interfaces.msg import Time  # noqa: E402
from geometry_msgs.msg import Quaternion  # noqa: E402

from frontier_explorer.explorer_node import cloud_to_xyz, grid_to_cloud, yaw_from_quaternion  # noqa: E402
from frontier_explorer.map_view import MapView  # noqa: E402


def test_map_cloud_round_trip():
    view = MapView(size_x=10.0, size_y=10.0)
    view.update_cloud(np.array([[2.0, 0.0, 1.0]]))
    view.update_pose(0.0, 0.0, 1.0, 0.0)
    view.sweep()
    msg = grid_to_cloud(view, 'map', Time())
    xyz = cloud_to_xyz(msg)
    assert msg.width == len(xyz) == np.count_nonzero(view.grid != -1)
    intensity = np.frombuffer(bytes(msg.data), dtype='<f4').reshape(-1, 4)[:, 3]
    assert intensity.sum() == np.count_nonzero(view.grid == 100)


def test_cloud_with_padding_and_no_points():
    view = MapView(size_x=4.0, size_y=4.0)
    msg = grid_to_cloud(view, 'map', Time())
    assert cloud_to_xyz(msg).shape == (0, 3)


def test_yaw():
    assert abs(yaw_from_quaternion(Quaternion(w=1.0))) < 1e-9
    q = Quaternion(z=np.sin(np.pi / 4), w=np.cos(np.pi / 4))
    assert abs(yaw_from_quaternion(q) - np.pi / 2) < 1e-9
