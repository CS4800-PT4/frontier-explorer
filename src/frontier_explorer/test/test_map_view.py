import math

import numpy as np

from frontier_explorer.map_view import FREE, OCCUPIED, UNKNOWN, MapView


def wall(x, y0, y1, z=1.0, step=0.05):
    ys = np.arange(y0, y1, step)
    return np.column_stack([np.full(len(ys), x), ys, np.full(len(ys), z)])


def test_new_map_is_unknown():
    assert MapView().grid.shape == (400, 400)  # EGO's 40 x 40 m map
    view = MapView(size_x=10.0, size_y=6.0, resolution=0.1)
    assert view.grid.shape == (60, 100)
    assert np.all(view.grid == UNKNOWN)
    assert view.known_area() == 0.0


def test_cell_round_trip_and_bounds():
    view = MapView(size_x=10.0, size_y=6.0, resolution=0.1)
    row, col = view.to_cell(1.23, -2.47)
    x, y = view.cell_center(row, col)
    assert abs(x - 1.25) < 1e-9 and abs(y - -2.45) < 1e-9
    assert view.in_bounds(4.9, 2.9)
    assert not view.in_bounds(5.0, 0.0)
    assert not view.in_bounds(4.5, 0.0, margin=1.0)
    assert view.state(20.0, 0.0) == OCCUPIED  # outside EGO's map counts as an obstacle


def test_cloud_uses_height_band_only():
    view = MapView(size_x=10.0, size_y=10.0)
    view.update_cloud(np.array([[1.0, 1.0, 0.2], [2.0, 2.0, 1.0], [3.0, 3.0, 1.55]]))
    assert view.state(1.0, 1.0) == UNKNOWN   # floor clutter, below the band
    assert view.state(2.0, 2.0) == OCCUPIED
    assert view.state(3.0, 3.0) == UNKNOWN   # EGO's virtual ceiling, above the band


def test_sweep_needs_pose_cloud_and_altitude():
    view = MapView(size_x=10.0, size_y=10.0)
    assert view.sweep() == 0
    view.update_pose(0.0, 0.0, 1.0, 0.0)
    assert view.sweep() == 0                 # no cloud yet
    view.update_cloud(np.zeros((0, 3)))
    view.update_pose(0.0, 0.0, 0.1, 0.0)
    assert view.sweep() == 0                 # still on the ground
    view.update_pose(0.0, 0.0, 1.0, 0.0)
    assert view.sweep() > 0


def test_sweep_marks_field_of_view_free():
    view = MapView(size_x=20.0, size_y=20.0, fov_deg=73.0, max_range=4.0)
    view.update_cloud(np.zeros((0, 3)))
    view.update_pose(0.0, 0.0, 1.0, 0.0)     # facing +x
    view.sweep()
    assert view.state(2.0, 0.0) == FREE
    assert view.state(3.5, 1.0) == FREE      # inside the 73 deg cone
    assert view.state(5.0, 0.0) == UNKNOWN   # past max range
    assert view.state(-2.0, 0.0) == UNKNOWN  # behind the drone
    assert view.state(1.0, 2.0) == UNKNOWN   # outside the cone
    assert view.state(0.0, 0.0) == FREE      # the drone's own spot


def test_sweep_follows_yaw():
    view = MapView(size_x=20.0, size_y=20.0)
    view.update_cloud(np.zeros((0, 3)))
    view.update_pose(0.0, 0.0, 1.0, math.pi / 2)  # facing +y
    view.sweep()
    assert view.state(0.0, 2.0) == FREE
    assert view.state(2.0, 0.0) == UNKNOWN


def test_rays_stop_at_obstacles():
    view = MapView(size_x=20.0, size_y=20.0)
    view.update_cloud(wall(2.0, -3.0, 3.0))
    view.update_pose(0.0, 0.0, 1.0, 0.0)
    view.sweep()
    assert view.state(1.5, 0.0) == FREE
    assert view.state(2.0, 0.0) == OCCUPIED
    assert view.state(3.0, 0.0) == UNKNOWN   # hidden behind the wall


def test_old_obstacle_is_cleared_when_seen_free():
    view = MapView(size_x=20.0, size_y=20.0)
    view.update_cloud(np.array([[2.0, 0.0, 1.0]]))
    assert view.state(2.0, 0.0) == OCCUPIED
    view.update_cloud(np.zeros((0, 3)))      # gone from the latest cloud
    view.update_pose(0.0, 0.0, 1.0, 0.0)
    view.sweep()
    assert view.state(2.0, 0.0) == FREE


def test_obstacles_outside_view_are_remembered():
    view = MapView(size_x=20.0, size_y=20.0)
    view.update_cloud(np.array([[-3.0, 0.0, 1.0]]))
    view.update_cloud(np.zeros((0, 3)))      # EGO forgot it, the drone is facing away
    view.update_pose(0.0, 0.0, 1.0, 0.0)
    view.sweep()
    assert view.state(-3.0, 0.0) == OCCUPIED


def test_clearance():
    view = MapView(size_x=10.0, size_y=10.0)
    view.update_cloud(np.array([[1.0, 0.0, 1.0]]))
    assert not view.clearance(0.8, 0.0, 0.3)
    assert view.clearance(0.0, 0.0, 0.3)
    assert not view.clearance(30.0, 0.0, 0.3)  # outside the map
