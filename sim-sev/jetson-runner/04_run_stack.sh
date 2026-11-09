#!/usr/bin/env bash
# Launch the live hardware stack from sim-sev (Jetson).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
source "$HERE/03_env.sh"

# ---------------------------------------------------------------------------
# VIEW THE EXPLORED MAP IN RVIZ  (run in its OWN terminal, not this script)
# ---------------------------------------------------------------------------
# 1) Source the environment (ROS + all workspaces + frontier_explorer):
#      source sim-sev/jetson-runner/03_env.sh
#
# 2) Start RViz with the frontier_explorer config:
#      rviz2 -d "$(ros2 pkg prefix frontier_explorer)/share/frontier_explorer/rviz/frontier.rviz"
#
# 3) Where to run it. This is a SEPARATE terminal from the flight stack
#    (04_run_stack.sh) and this demo script:
#      - Bench:   on the Jetson itself, with a monitor attached.
#      - Flights: on the Ubuntu laptop over Wi-Fi, same ROS_DOMAIN_ID as the
#                 Jetson (check with: echo $ROS_DOMAIN_ID), so the Jetson's
#                 GPU stays free for the ZED and EGO.
#
# 4) The "explored map" display (topic /frontier/map_cloud) fills in live
#    as the explorer runs: every cell the drone has seen, free or occupied.
#
# 5) Do NOT use the rviz:=true launch argument. A separate rviz2 command is
#    preferred: you can close/reopen RViz without restarting the flight
#    stack, and if RViz crashes the crash stays isolated from it.
# ---------------------------------------------------------------------------

LAUNCH="$SIM_SEV/hardware.launch.py"
[ -f "$LAUNCH" ] || { echo "Missing $LAUNCH"; exit 1; }

if [ ! -f "$WS_ROOT/.ego_hw/zed_intrinsics.yaml" ]; then
  echo "NOTE: no $WS_ROOT/.ego_hw/zed_intrinsics.yaml yet."
  echo "      After the ZED node is up, run: bash $HERE/05_capture_intrinsics.sh"
  echo "      Then restart this launch if EGO complained about intrinsics."
fi

echo "Launching: ros2 launch $LAUNCH $*"
echo "Other terminal: bash $SIM_SEV/jetson-runner/06_run_demo.sh"
exec ros2 launch "$LAUNCH" intrinsics_file:="$WS_ROOT/.ego_hw/zed_intrinsics.yaml" map_size_x:=10.0 map_size_y:=10.0 "$@"
