#!/usr/bin/env bash
# Reads the ZED depth camera_info once and saves fx, fy, cx, cy for hardware.launch.py.
# Run it with the ZED wrapper already running, once per camera / resolution:
#   ros2 launch zed_wrapper zed_camera.launch.py camera_model:=<model> \
#     ros_params_override_path:=$(ros2 pkg prefix frontier_explorer)/share/frontier_explorer/config/zed_override.yaml
#   bash hw/zed_intrinsics.sh
# Usage: bash hw/zed_intrinsics.sh [camera_info topic] [output file]
TOPIC=${1:-/zed/zed_node/depth/camera_info}
OUT=${2:-$HOME/.ego_hw/zed_intrinsics.yaml}
source /opt/ros/humble/setup.bash
[ -f ~/zed_ws/install/setup.bash ] && source ~/zed_ws/install/setup.bash

python3 - "$TOPIC" "$OUT" <<'EOF'
import os
import sys
import time

import rclpy
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo

topic, out = sys.argv[1], sys.argv[2]
rclpy.init()
node = rclpy.create_node('zed_intrinsics')
got = []
node.create_subscription(CameraInfo, topic, got.append, qos_profile_sensor_data)
end = time.monotonic() + 15
while not got and time.monotonic() < end:
    rclpy.spin_once(node, timeout_sec=0.5)
rclpy.shutdown()
if not got:
    sys.exit(f'[intrinsics] nothing on {topic} in 15 s. Is the ZED wrapper running? '
             f'(ros2 topic list | grep camera_info)')
info = got[0]
k = list(info.k)
fx, fy, cx, cy = k[0], k[4], k[2], k[5]
if fx <= 0 or fy <= 0:
    sys.exit(f'[intrinsics] {topic} has no calibration (fx={fx}, fy={fy})')
# EGO's depth buffer holds 640 x 480 pixels (grid_map.cpp) and overflows on bigger images
if info.width * info.height > 640 * 480:
    sys.exit(f'[intrinsics] depth is {info.width}x{info.height}; EGO only handles up to '
             f'640x480. Set the ZED to VGA (config/zed_override.yaml) and run this again.')
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'w') as f:
    f.write(f'# From {topic} on {time.strftime("%Y-%m-%d %H:%M")}\n')
    f.write(f'width: {info.width}\nheight: {info.height}\n')
    f.write(f'fx: {fx}\nfy: {fy}\ncx: {cx}\ncy: {cy}\n')
print(f'[intrinsics] {info.width}x{info.height} fx={fx:.2f} fy={fy:.2f} cx={cx:.2f} cy={cy:.2f}')
print(f'[intrinsics] saved to {out}; hardware.launch.py reads it from there')
EOF
