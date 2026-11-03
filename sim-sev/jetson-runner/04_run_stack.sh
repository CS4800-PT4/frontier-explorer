#!/usr/bin/env bash
# Launch the live hardware stack from sim-sev (Jetson).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
source "$HERE/03_env.sh"

LAUNCH="$SIM_SEV/hardware.launch.py"
[ -f "$LAUNCH" ] || { echo "Missing $LAUNCH"; exit 1; }

if [ ! -f "${HOME}/.ego_hw/zed_intrinsics.yaml" ]; then
  echo "NOTE: no ~/.ego_hw/zed_intrinsics.yaml yet."
  echo "      After the ZED node is up, run: bash $HERE/05_capture_intrinsics.sh"
  echo "      Then restart this launch if EGO complained about intrinsics."
fi

echo "Launching: ros2 launch $LAUNCH $*"
echo "Other terminal: bash $SIM_SEV/jetson-runner/06_run_demo.sh"
exec ros2 launch "$LAUNCH" "$@"
