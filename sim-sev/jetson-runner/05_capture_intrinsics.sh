#!/usr/bin/env bash
# Save ZED depth intrinsics for hardware.launch.py (sim-sev/jetson-runner copy).
TOPIC=${1:-/zed/zed_node/depth/camera_info}
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
source "$HERE/03_env.sh"
OUT="${2:-$WS_ROOT/.ego_hw/zed_intrinsics.yaml}"

python3 - "$TOPIC" "$OUT" <<'PY'
import os, sys, time
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
    sys.exit(f'[intrinsics] nothing on {topic} in 15 s — is hardware.launch / ZED running?')
info = got[0]
k = list(info.k)
fx, fy, cx, cy = k[0], k[4], k[2], k[5]
if fx <= 0 or fy <= 0:
    sys.exit(f'[intrinsics] bad calibration fx={fx} fy={fy}')
if info.width * info.height > 640 * 480:
    sys.exit(f'[intrinsics] {info.width}x{info.height} too big for EGO; use VGA (sim-sev/config/zed_override.yaml)')
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
with open(out, 'w') as f:
    f.write(f'# From {topic} on {time.strftime("%Y-%m-%d %H:%M")}\n')
    f.write(f'width: {info.width}\nheight: {info.height}\n')
    f.write(f'fx: {fx}\nfy: {fy}\ncx: {cx}\ncy: {cy}\n')
print(f'[intrinsics] {info.width}x{info.height} fx={fx:.2f} fy={fy:.2f} cx={cx:.2f} cy={cy:.2f}')
print(f'[intrinsics] saved {out}')
PY
