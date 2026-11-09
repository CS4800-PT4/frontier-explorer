#!/usr/bin/env bash
# Manual live demo helper — one step at a time. Nothing runs until you press Enter.
# Prerequisites: 04_run_stack.sh already running (explorer off by default).
# Ctrl+C at any prompt to stop this helper (use kill switch / l / d as needed).
#
# Keys (bridge listens on /mode_key):
#   t = takeoff+arm   o = offboard (MUST before Explorer)   then explorer
# KNOWN ISSUE: Explorer before o crashes — see ../KNOWN_ISSUES.md
#   p = hover HERE (freeze current x/y/z)   l = land HERE   d = disarm
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/03_env.sh"

EXPLORER_LOG="$SCRIPT_DIR/explorer.log"
EXPLORER_PID=""
FLYING=0
MAX_RADIUS=8.0   # geofence: refuse goals farther than this (m) from the odom origin
MAP_SIZE=10.0    # explorer + EGO map (m); must match map_size_x/y passed in 04
ARRIVE_DIST=0.6  # same as explorer_node arrive_dist: within this (m) = goal reached
GOAL_TIMEOUT=25  # s; if a goal isn't reached by then, ask for the next (explorer skips it)
GOAL_X=""; GOAL_Y=""; GOAL_T=0

cleanup_explorer() {
  if [[ -n "${EXPLORER_PID}" ]] && kill -0 "$EXPLORER_PID" 2>/dev/null; then
    echo "[demo] stopping explorer (pid $EXPLORER_PID)"
    kill "$EXPLORER_PID" 2>/dev/null || true
    wait "$EXPLORER_PID" 2>/dev/null || true
    EXPLORER_PID=""
  fi
}

on_interrupt() {
  trap '' INT TERM HUP   # ignore more Ctrl+C so the stop sequence finishes
  echo
  if [[ "$FLYING" == 1 ]]; then
    echo "[demo] INTERRUPTED WHILE FLYING."
    safe_stop
    echo "[demo] When it's on the ground, disarm from any terminal:"
    echo "       ros2 topic pub -r 5 -t 6 /mode_key std_msgs/msg/String \"{data: 'd'}\""
  else
    cleanup_explorer
    echo "[demo] Interrupted before takeoff. No flight command sent."
  fi
  exit 130
}

on_exit() {
  local rc=$?
  if [[ $rc -ne 0 && $rc -ne 130 ]]; then
    trap '' INT TERM HUP
    echo "[demo] SCRIPT ERROR (exit $rc)."
    if [[ "$FLYING" == 1 ]]; then safe_stop; else cleanup_explorer; fi
  fi
}
trap on_interrupt INT TERM HUP
trap on_exit EXIT

pub_key() {
  local k="$1"
  local n="${2:-6}"
  echo "[demo] sending mode_key → $k"
  ros2 topic pub -r 5 -t "$n" /mode_key std_msgs/msg/String "{data: '$k'}" >/dev/null
}

hover_now() {          # position mode: hold exactly here
  cleanup_explorer
  pub_key p 6 || true
  echo "[demo] POSITION HOVER sent (p): holding current x/y/z."
}

takeoff_hover_now() {  # takeoff mode: hold x/y, ~0.9 m above current height
  cleanup_explorer
  pub_key t 6 || true
  echo "[demo] TAKEOFF-MODE HOVER sent (t): holding x/y, climbing ~0.9 m."
}

land_now() {
  cleanup_explorer
  pub_key l 8 || true
  echo "[demo] LAND sent (l): descending in place."
}

safe_stop() {          # Ctrl+C / error: hover, settle, then land
  echo "[demo] SAFE STOP: position hover, then land in 3 s."
  hover_now
  sleep 3
  land_now
}

finish_landing() {
  echo "[demo] Type d + Enter once it is ON THE GROUND to disarm."
  local ans=""
  until [[ "$ans" == d ]]; do read -r ans; done
  pub_key d 6 || true
  FLYING=0
  echo "[demo] DISARMED. Keep kill switch until props are stopped."
  exit 0
}

send_next_goal() {     # geofence check, then one goal; returns 1 if fenced (already hovering)
  local xy gx gy
  xy=$(timeout 5 ros2 topic echo --once /frontier/best_goal 2>/dev/null \
       | awk '/position:/{f=1;next} f&&$1=="x:"{x=$2} f&&$1=="y:"{print x, $2; exit}') || true
  if [[ -z "$xy" ]]; then echo "    No best goal yet. Retrying shortly."; GOAL_X=""; GOAL_T=$SECONDS; return 0; fi
  read -r gx gy <<<"$xy"
  if awk -v x="$gx" -v y="$gy" -v r="$MAX_RADIUS" 'BEGIN{exit !(sqrt(x*x+y*y) <= r)}'; then
    echo "[demo] goal ($gx, $gy) is inside ${MAX_RADIUS} m. Sending."
    ros2 service call /frontier/go_best std_srvs/srv/Trigger "{}" || echo "    go_best call failed."
    GOAL_X="$gx"; GOAL_Y="$gy"; GOAL_T=$SECONDS
    return 0
  fi
  echo "[demo] GEOFENCE: goal ($gx, $gy) is outside ${MAX_RADIUS} m. NOT sent. Position hover."
  hover_now
  return 1
}

goal_done() {          # 0 = time for the next goal (reached, timed out, or none yet)
  if [[ -z "$GOAL_X" ]]; then (( SECONDS - GOAL_T >= 3 )); return; fi
  if (( SECONDS - GOAL_T >= GOAL_TIMEOUT )); then
    echo "[demo] goal ($GOAL_X, $GOAL_Y) not reached in ${GOAL_TIMEOUT} s. Asking for the next one."
    return 0
  fi
  local xy
  xy=$(timeout 5 ros2 topic echo --once /mavros/local_position/odom 2>/dev/null \
       | awk '/position:/{f=1;next} f&&$1=="x:"{x=$2} f&&$1=="y:"{print x, $2; exit}') || true
  [[ -n "$xy" ]] || return 1
  awk -v p="$xy" -v gx="$GOAL_X" -v gy="$GOAL_Y" -v r="$ARRIVE_DIST" \
    'BEGIN{split(p,a," "); exit !(sqrt((a[1]-gx)^2+(a[2]-gy)^2) <= r)}'
}

confirm() {
  local msg="$1" ans
  echo
  echo ">>> $msg"
  echo "    Enter = do it   p = position hover   t = takeoff-mode hover   l = LAND   Ctrl+C = hover then land"
  while true; do
    read -r ans
    case "$ans" in
      ("") return 0 ;;
      (p|t|l)
        if [[ "$FLYING" != 1 ]]; then echo "    Not flying."; continue; fi
        case "$ans" in
          (p) hover_now ;;
          (t) takeoff_hover_now ;;
          (l) land_now; finish_landing ;;
        esac ;;
      (*) echo "    Press Enter, or type p, t, or l." ;;
    esac
  done
}


echo "[demo] MANUAL mode — you confirm every step."
echo "[demo] checking odom..."
if ! timeout 20 ros2 topic echo /mavros/local_position/odom --once >/dev/null 2>&1; then
  echo "[demo] FAIL: no /mavros/local_position/odom. Start: bash $SCRIPT_DIR/04_run_stack.sh"
  exit 1
fi
echo "[demo] odom OK"

confirm "STEP 1 TAKEOFF (send t): ARMS, props spin, climbs and hovers. Area clear? Kill switch in hand?"
pub_key t 8
FLYING=1
confirm "Is it HOVERING STABLY after takeoff?"

# KNOWN ISSUE: starting Explorer before offboard (o) crashes the program.
# Always send o first, then start explorer_node. See sim-sev/KNOWN_ISSUES.md.
confirm "STEP 2 OFFBOARD (send o): drone will follow EGO goals. Must come BEFORE explorer."
pub_key o 8
echo "[demo] offboard selected."

confirm "STEP 3 START EXPLORER: maps frontiers and picks/sends goals BY ITSELF (no Enter per goal)."
: > "$EXPLORER_LOG"
# Same params hardware.launch.py passes when explorer:=true (node defaults are sim topics)
FOV=$(python3 -c "import math,sys,yaml;d=yaml.safe_load(open(sys.argv[1]));print(math.degrees(2*math.atan(d['width']/2.0/d['fx'])))" "$WS_ROOT/.ego_hw/zed_intrinsics.yaml" 2>/dev/null || echo 73.0)
ros2 run frontier_explorer explorer_node --ros-args \
  -p depth_topic:=/zed/zed_node/depth/depth_registered \
  -p odom_topic:=/mavros/local_position/odom \
  -p map_size_x:="$MAP_SIZE" -p map_size_y:="$MAP_SIZE" -p fov_deg:="$FOV" \
  >"$EXPLORER_LOG" 2>&1 &
EXPLORER_PID=$!
sleep 1
echo "[demo] explorer pid $EXPLORER_PID"
echo "[demo] watch explorer:  tail -f $EXPLORER_LOG"
echo "[demo] or goals:        ros2 topic echo /goal_pose"

echo
echo ">>> EXPLORER RUNNING AUTONOMOUSLY: next goal goes out when the last is reached (<= ${ARRIVE_DIST} m)"
echo "    or after ${GOAL_TIMEOUT} s. Goals beyond ${MAX_RADIUS} m trigger the geofence hover."
echo "    Type a key + Enter any time:  p = FALLBACK position hover   t = FALLBACK takeoff hover (+0.9 m)"
echo "                                   l = LAND now                Ctrl+C = hover then land"
send_next_goal || GEOFENCED=1
while [[ "${GEOFENCED:-0}" != 1 ]]; do
  if read -r -t 1 ans; then
    case "$ans" in
      (p)  hover_now; break ;;
      (t)  takeoff_hover_now; break ;;
      (l)  land_now; finish_landing ;;
      (*)  echo "    Explorer is automatic. Type p, t, or l (then Enter) to take over." ;;
    esac
  elif goal_done; then
    send_next_goal || break
  fi
done

# Reached after a fallback (p/t) or a geofence stop
echo "[demo] In fallback hover. Watch it, then land."
confirm "LAND NOW (send l): PX4 lands at current XY, descends in place"
land_now
finish_landing