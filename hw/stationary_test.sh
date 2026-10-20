#!/usr/bin/env bash
# Stationary test of the frontier explorer on the real ZED, with no flight controller. Only
# the ZED, EGO and the explorer run (MAVROS, XRCE, the bridge and the vision relay stay off,
# so nothing can arm). The ZED's own odometry stands in for PX4's, and the explorer and EGO
# are set up for a camera on the ground (see "Settings" below).
# Run hw/stationary_setup.sh once first. Then:
#   bash hw/stationary_test.sh <camera_model>      (zed, zedm, zed2 or zed2i)
# It saves the camera intrinsics the first time, starts everything, checks each link, then
# prints the explorer's status every 10 s. Walk the camera around slowly and watch RViz.
# Stop with Ctrl-C. Logs go to $FE_WS/logs/<time>/.
#   RVIZ=0               don't open RViz (no screen)
#   DEPTH_TOPIC=, ZED_ODOM=, DEPTH_INFO=   if the ZED wrapper uses other topic names
#   NEW_INTRINSICS=1     save the intrinsics again (other camera or resolution)
#   ZED=0                don't start the ZED (the sim test publishes fake ZED topics)
#   FE_WS=~/fe_ws        where hw/stationary_setup.sh put things
CAMERA=${1:-${CAMERA:-}}
FE_WS=${FE_WS:-$HOME/fe_ws}
RVIZ=${RVIZ:-1}
ZED=${ZED:-1}
DEPTH_TOPIC=${DEPTH_TOPIC:-/zed/zed_node/depth/depth_registered}
DEPTH_INFO=${DEPTH_INFO:-/zed/zed_node/depth/camera_info}
ZED_ODOM=${ZED_ODOM:-/zed/zed_node/odom}
INTRINSICS=$FE_WS/zed_intrinsics.yaml
HERE=$(cd "$(dirname "$0")" && pwd)

if [ "$ZED" = 1 ] && [ -z "$CAMERA" ]; then
  echo "usage: bash hw/stationary_test.sh <camera_model>   (zed, zedm, zed2 or zed2i)"; exit 1
fi
[ -f "$FE_WS/env.sh" ] || { echo "[stationary] run bash hw/stationary_setup.sh first"; exit 1; }
# shellcheck disable=SC1091
source "$FE_WS/env.sh"
LOG=$FE_WS/logs/$(date +%m%d_%H%M%S)
mkdir -p "$LOG"
exec > >(tee -a "$LOG/run.log") 2>&1   # a copy for hw/collect_info.sh

say() { echo "[stationary] $*"; }
PIDS=()
CORE=()   # everything but RViz: if one of these stops, the test stops
start() {  # name command...   Each runs in its own process group, so stopping it stops its nodes
  local name=$1
  shift
  setsid "$@" > "$LOG/$name.log" 2>&1 &
  PIDS+=($!)
  [ "$name" = rviz ] || CORE+=($!)
  say "started $name (log: $LOG/$name.log)"
}
# Ctrl-C first, as if typed in each terminal. Background jobs of a script start with Ctrl-C
# ignored, though, so anything still up after 5 s gets TERM, then KILL.
stop_all() {
  local p sig alive
  for sig in INT TERM; do
    for p in "${PIDS[@]}"; do kill -"$sig" -- -"$p" 2>/dev/null; done
    for _ in 1 2 3 4 5; do
      alive=0
      for p in "${PIDS[@]}"; do kill -0 -- -"$p" 2>/dev/null && alive=1; done
      [ $alive = 0 ] && break 2
      sleep 1
    done
  done
  for p in "${PIDS[@]}"; do kill -KILL -- -"$p" 2>/dev/null; done
  PIDS=()
  CORE=()
}
trap 'echo; say "stopping"; stop_all; say "logs: $LOG"; exit 0' INT TERM

# --- Launch arguments. Settings for a camera sitting on the ground: ---
# - ground:=-1.0  EGO treats everything below 'ground' as solid. The ZED's odometry starts at
#   z = 0, so with the default 0.3 m EGO would think the camera starts inside an obstacle.
# - The explorer only marks space as seen above min_sweep_z (0.5 m, meant for flight), and only
#   counts obstacles in a height band (0.7-1.3 m above the start). Here the sweep runs at any
#   height and the band is 0.2-1.0 m above the camera, which skips the floor.
LAUNCH=(ros2 launch frontier_explorer hardware.launch.py mavros:=false xrce:=false bridge:=false
        vision:=false "depth_topic:=$DEPTH_TOPIC" "zed_odom:=$ZED_ODOM" "intrinsics_file:=$INTRINSICS")
if [ "$ZED" = 1 ]; then LAUNCH+=("camera_model:=$CAMERA"); else LAUNCH+=(zed:=false); fi

echo_once() { timeout "${2:-15}" ros2 topic echo "$1" --once --no-arr 2>/dev/null; }
has_data() { echo_once "$@" | grep -q "^---$"; }
rate() { timeout 8 ros2 topic hz "$1" 2>/dev/null | awk '/average rate/{r=$3}END{print r+0}'; }
running() { local p; for p in "${CORE[@]}"; do kill -0 -- -"$p" 2>/dev/null || return 1; done; }

# --- 1. Camera intrinsics (once) ---
if [ ! -f "$INTRINSICS" ] || [ "${NEW_INTRINSICS:-0}" = 1 ]; then
  say "saving the camera intrinsics"
  [ "$ZED" = 1 ] && start zed_only "${LAUNCH[@]}" ego:=false explorer:=false
  ok=0
  for _ in 1 2 3 4; do   # the ZED wrapper can take 30 s or more to start
    bash "$HERE/zed_intrinsics.sh" "$DEPTH_INFO" "$INTRINSICS" && { ok=1; break; }
    running || break
  done
  stop_all
  if [ $ok = 0 ]; then
    say "!!! no intrinsics. End of the ZED log:"
    tail -20 "$LOG/zed_only.log" 2>/dev/null
    say "if the topic names differ, check: ros2 topic list | grep zed"
    exit 1
  fi
fi
FOV=$(python3 -c "import math, yaml; d = yaml.safe_load(open('$INTRINSICS'))
print(round(math.degrees(2 * math.atan(d['width'] / 2 / d['fx'])), 1) if d.get('width') else 73.0)")
say "intrinsics: $INTRINSICS (horizontal FOV $FOV deg)"

# --- 2. ZED + EGO, then the explorer ---
start stack "${LAUNCH[@]}" explorer:=false "odom_topic:=$ZED_ODOM" ground:=-1.0
say "waiting for depth on $DEPTH_TOPIC"
for _ in $(seq 12); do
  has_data "$DEPTH_TOPIC" 5 && break
  running || break
done
if ! running; then
  say "!!! the launch stopped. End of its log:"; tail -25 "$LOG/stack.log"; stop_all; exit 1
fi
start explorer ros2 run frontier_explorer explorer_node --ros-args \
  -p "odom_topic:=$ZED_ODOM" -p "depth_topic:=$DEPTH_TOPIC" -p "fov_deg:=$FOV" \
  -p min_sweep_z:=-1.0 -p band_low:=0.2 -p band_high:=1.0

if [ "$RVIZ" = 1 ] && { [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; } && command -v rviz2 >/dev/null; then
  # The sim's RViz view, with the drone shown from the ZED odometry instead of MAVROS
  sed "s#/mavros/local_position/odom#$ZED_ODOM#" \
    "$FE_REPO/src/frontier_explorer/rviz/frontier.rviz" > "$LOG/stationary.rviz"
  start rviz rviz2 -d "$LOG/stationary.rviz"
else
  say "no RViz (RVIZ=0, no screen, or rviz2 not installed)"
fi

# --- 3. Check each link ---
sleep 8
say "checks (point the camera at a wall or a box 1 to 4 m away):"
FAILS=0
check() { if [ "$1" = ok ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; FAILS=$((FAILS+1)); fi; }
R=$(rate "$DEPTH_TOPIC")
check "$(awk -v r="$R" 'BEGIN{print (r>=5) ? "ok" : "no"}')" "depth at $R Hz on $DEPTH_TOPIC (the ZED is set to 15; under 5 fails)"
has_data "$ZED_ODOM" && check ok "ZED odometry on $ZED_ODOM" \
  || check no "no ZED odometry on $ZED_ODOM (is positional tracking on?)"
MAP=$(echo_once /drone_0_grid/grid_map/occupancy_inflate | awk '/^width:/{print $2; exit}')
if [ -z "$MAP" ]; then check no "EGO map not publishing (see $LOG/stack.log)"
elif [ "$MAP" -gt 0 ]; then check ok "EGO is mapping from depth ($MAP occupied points)"
else check no "EGO map is empty: nothing within 4 m, or depth/odometry isn't reaching EGO"; fi
K=$(echo_once /frontier/status | grep -oE "known_m2=[0-9.]+" | cut -d= -f2)
check "$(awk -v k="$K" 'BEGIN{print (k>0) ? "ok" : "no"}')" "explorer has seen ${K:-0} m2 (see $LOG/explorer.log)"
[ $FAILS = 0 ] && say "all checks passed" || say "$FAILS check(s) failed; it keeps running so you can look"

cat <<EOF
[stationary] Now walk the camera around slowly (turn slowly too). In RViz: light blue is seen
             space, orange markers are frontiers, the green ball is the goal it would pick.
             To have EGO plan a path to that goal (nothing flies, the bridge is off), run once:
               source $FE_WS/env.sh && ros2 service call /frontier/go_best std_srvs/srv/Trigger
             Each extra call while the camera hasn't reached the goal marks it failed.
             Ctrl-C here stops everything.
EOF
while running; do
  sleep 10
  S=$(echo_once /frontier/status 5 | grep -oE "known_m2=.*" | tr -d "'\"")
  [ -n "$S" ] && say "$S"
done
say "!!! something stopped. Ends of the logs:"
for f in "$LOG"/stack.log "$LOG"/explorer.log; do echo "--- $f"; tail -15 "$f"; done
stop_all
exit 1
