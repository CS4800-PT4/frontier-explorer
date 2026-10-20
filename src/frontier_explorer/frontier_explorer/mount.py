"""Camera mount math for EGO's depth projection.

EGO turns each depth pixel into a point in the camera's optical frame (z forward,
x right, y down), then moves it into the drone's body frame (x forward, y left, z up)
with a fixed cam2body transform (grid_map.cpp). Its default is a level camera at the
body origin. The only way to change it without editing EGO is to publish the transform
on /vins_estimator/extrinsic, which is what extrinsic_node does with these numbers.
"""
import math

import numpy as np

# EGO's default cam2body rotation: optical frame -> body frame (grid_map.cpp)
OPTICAL_TO_BODY = np.array([[0.0, 0.0, 1.0],
                            [-1.0, 0.0, 0.0],
                            [0.0, -1.0, 0.0]])


def cam2body(x=0.0, y=0.0, z=0.0, pitch=0.0):
    """4 x 4 transform from the optical frame to the body frame.

    x, y, z: camera position in the body frame (m, forward / left / up).
    pitch: how far the camera is tilted down (rad, positive = looking down).
    """
    c, s = math.cos(pitch), math.sin(pitch)
    tilt = np.array([[c, 0.0, s],
                     [0.0, 1.0, 0.0],
                     [-s, 0.0, c]])     # rotation about the body y axis
    t = np.eye(4)
    t[:3, :3] = tilt @ OPTICAL_TO_BODY
    t[:3, 3] = (x, y, z)
    return t


def rotation_to_quaternion(r):
    """3 x 3 rotation matrix -> (w, x, y, z)."""
    trace = r[0, 0] + r[1, 1] + r[2, 2]
    if trace > 0.0:
        s = 2.0 * math.sqrt(trace + 1.0)
        w, x = 0.25 * s, (r[2, 1] - r[1, 2]) / s
        y, z = (r[0, 2] - r[2, 0]) / s, (r[1, 0] - r[0, 1]) / s
    elif r[0, 0] > r[1, 1] and r[0, 0] > r[2, 2]:
        s = 2.0 * math.sqrt(1.0 + r[0, 0] - r[1, 1] - r[2, 2])
        w, x = (r[2, 1] - r[1, 2]) / s, 0.25 * s
        y, z = (r[0, 1] + r[1, 0]) / s, (r[0, 2] + r[2, 0]) / s
    elif r[1, 1] > r[2, 2]:
        s = 2.0 * math.sqrt(1.0 + r[1, 1] - r[0, 0] - r[2, 2])
        w, x = (r[0, 2] - r[2, 0]) / s, (r[0, 1] + r[1, 0]) / s
        y, z = 0.25 * s, (r[1, 2] + r[2, 1]) / s
    else:
        s = 2.0 * math.sqrt(1.0 + r[2, 2] - r[0, 0] - r[1, 1])
        w, x = (r[1, 0] - r[0, 1]) / s, (r[0, 2] + r[2, 0]) / s
        y, z = (r[1, 2] + r[2, 1]) / s, 0.25 * s
    if w < 0.0:
        w, x, y, z = -w, -x, -y, -z
    return w, x, y, z


def quaternion_to_rotation(w, x, y, z):
    """(w, x, y, z) -> 3 x 3 rotation matrix, the same way Eigen does it in EGO."""
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
        [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
        [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)]])
