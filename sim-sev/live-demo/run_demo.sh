#!/usr/bin/env bash
# Manual live demo helper — one step at a time. Nothing runs until you press Enter.
# Prerequisites: sim-sev/hardware.launch.py already running (explorer off by default).
# Ctrl+C at any prompt to stop this helper (use kill switch / l / d as needed).
#
# Keys (bridge listens on /mode_key):
#   t = takeoff+arm   o = follow explorer goals
#   p = hover HERE (freeze current x/y/z)   l = land HERE   d = disarm
set -euo pipefail

source /opt/ros/humble/setup.bash
[ -f ~/ego_ws/install/setup.bash ] && source ~/ego_ws/install/setup.bash
[ -f ~/px4_ego/install/setup.bash ] && source ~/px4_ego/install/setup.bash
[ -f ~/frontier-explorer/install/setup.bash ] && source ~/frontier-explorer/install/setup.bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
EXPLORER_LOG="$SCRIPT_DIR/explorer.log"
EXPLORER_PID=""

cleanup_explorer() {
  if [[ -n "${EXPLORER_PID}" ]] && kill -0 "$EXPLORER_PID" 2>/dev/null; then
    echo "[demo] stopping explorer (pid $EXPLORER_PID)"
    kill "$EXPLORER_PID" 2>/dev/null || true
    wait "$EXPLORER_PID" 2>/dev/null || true
    EXPLORER_PID=""
  fi
}

on_interrupt() {
  echo
  echo "[demo] interrupted — explorer cleaned up if we started it."
  echo "[demo] If the drone is still up: kill switch, or send p (hover) / l (land) / d (disarm)."
  cleanup_explorer
  exit 130
}
trap on_interrupt INT

pub_key() {
  local k="$1"
  local n="${2:-6}"
  echo "[demo] sending mode_key → $k"
  ros2 topic pub -r 5 -t "$n" /mode_key std_msgs/msg/String "{data: '$k'}" >/dev/null
}

confirm() {
  local msg="$1"
  echo
  echo ">>> $msg"
  echo "    Press Enter to do it, or Ctrl+C to abort this helper."
  read -r _
}

echo "[demo] MANUAL mode — you confirm every step."
echo "[demo] checking odom..."
if ! timeout 20 ros2 topic echo /mavros/local_position/odom --once >/dev/null 2>&1; then
  echo "[demo] FAIL: no /mavros/local_position/odom. Start: ros2 launch ~/frontier-explorer/sim-sev/hardware.launch.py"
  exit 1
fi
echo "[demo] odom OK"

confirm "START / TAKEOFF (send t) — props spin, climbs ~2 m and holds"
pub_key t 8
echo "[demo] waiting for hover. Press Enter when it is hovering stably."
read -r _

confirm "START EXPLORER (frontier_explorer explorer_node)"
: > "$EXPLORER_LOG"
ros2 run frontier_explorer explorer_node >"$EXPLORER_LOG" 2>&1 &
EXPLORER_PID=$!
sleep 1
echo "[demo] explorer pid $EXPLORER_PID"
echo "[demo] watch explorer:  tail -f $EXPLORER_LOG"
echo "[demo] or goals:        ros2 topic echo /goal_pose"

confirm "OFFBOARD (send o) — vehicle starts following explorer goals"
pub_key o 8

# Immediate next prompt so you can freeze ASAP if anything looks wrong
confirm "HOVER HERE NOW? (kill explorer + send p) — freezes at current x/y/z"
cleanup_explorer
pub_key p 6
echo "[demo] holding in place (p). Watch it. When ready to come down:"

confirm "LAND HERE (send l) — PX4 land at current XY (descends in place)"
pub_key l 8
echo "[demo] landing. Press Enter when it is on the ground (then we disarm)."
read -r _

confirm "DISARM (send d)"
pub_key d 6
echo "[demo] DONE. Keep kill switch until props are stopped."
