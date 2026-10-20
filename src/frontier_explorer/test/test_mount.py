import math

import numpy as np
import pytest

from frontier_explorer.mount import (OPTICAL_TO_BODY, cam2body, quaternion_to_rotation,
                                     rotation_to_quaternion)


def to_body(t, point):
    return (t @ np.append(point, 1.0))[:3]


def test_default_matches_ego():
    # grid_map.cpp: cam2body_ << 0,0,1,0, -1,0,0,0, 0,-1,0,0, 0,0,0,1
    expected = np.array([[0, 0, 1, 0], [-1, 0, 0, 0], [0, -1, 0, 0], [0, 0, 0, 1]], dtype=float)
    assert np.allclose(cam2body(), expected)


def test_optical_axes_land_on_body_axes():
    t = cam2body()
    assert np.allclose(to_body(t, [0, 0, 1]), [1, 0, 0])    # forward stays forward
    assert np.allclose(to_body(t, [1, 0, 0]), [0, -1, 0])   # image right is the drone's right
    assert np.allclose(to_body(t, [0, 1, 0]), [0, 0, -1])   # image down is down


def test_offset_moves_points():
    # 2 m straight ahead of a camera 0.1 m forward and 0.05 m up
    t = cam2body(0.1, 0.0, 0.05)
    assert np.allclose(to_body(t, [0, 0, 2.0]), [2.1, 0.0, 0.05])


def test_pitch_down_looks_down():
    t = cam2body(pitch=math.radians(30))
    ahead = to_body(t, [0, 0, 1])
    assert np.allclose(ahead, [math.cos(math.radians(30)), 0, -math.sin(math.radians(30))])
    assert np.allclose(to_body(t, [1, 0, 0]), [0, -1, 0])   # pitch doesn't change right


@pytest.mark.parametrize('pitch_deg', [0, 15, 30, 45, 89, 90, -20])
def test_quaternion_round_trip(pitch_deg):
    r = cam2body(pitch=math.radians(pitch_deg))[:3, :3]
    w, x, y, z = rotation_to_quaternion(r)
    assert w >= 0
    assert math.isclose(w * w + x * x + y * y + z * z, 1.0, abs_tol=1e-9)
    assert np.allclose(quaternion_to_rotation(w, x, y, z), r)


def test_rotation_is_proper():
    assert np.isclose(np.linalg.det(OPTICAL_TO_BODY), 1.0)
