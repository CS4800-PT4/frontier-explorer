#!/usr/bin/env bash
# Bench check for the hardware stack (props off). Run it in a second terminal while
# hardware.launch.py is up. It checks every link the flight needs and prints the PX4
# settings that matter, then says PASS or FAIL. The sim test runs it too.
# Usage: bash hw/bench_check.sh
#   DEPTH_TOPIC=...   depth topic to time (default the ZED one)
#   VISION=0          skip the vision checks (when PX4 gets position some other way)
#   MIN_DEPTH_HZ=10   lowest depth rate that passes (the sim test uses 5; its camera is slower)
DEPTH_TOPIC=${DEPTH_TOPIC:-/zed/zed_node/depth/depth_registered}
MIN_DEPTH_HZ=${MIN_DEPTH_HZ:-10}
VISION=${VISION:-1}
for f in /opt/ros/humble/setup.bash ~/mavros_ws/install/setup.bash ~/ros2_ws/install/setup.bash \
         ~/ego_ws/install/setup.bash ~/px4_ego_ws/install/setup.bash ~/zed_ws/install/setup.bash; do
  [ -f $f ] && source $f
done
REPO=$(cd "$(dirname "$0")/.." && pwd)
[ -f $REPO/install/setup.bash ] && source $REPO/install/setup.bash

FAILS=0
pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; FAILS=$((FAILS+1)); }
info() { echo "  INFO  $1"; }
# --field with --once hangs on Humble, so these read whole messages. 15 s because the CLI
# is slow to start when the full stack is loading the machine.
echo_once() { timeout ${2:-15} ros2 topic echo "$1" --once 2>/dev/null; }   # topic [timeout]
has_data() { echo_once "$@" | grep -q "^---$"; }   # a full message ends in ---; warnings don't
# Finds base or base_vN (PX4 adds the version to some names) that has a publisher. Only
# published topics count: the bridge subscribes to several versions, and those names show up
# too. The daemon can come back empty under load, so it retries without the daemon.
find_topic() {
  local t
  for opt in "" "--no-daemon --spin-time 5" "--no-daemon --spin-time 10"; do
    # shellcheck disable=SC2086
    t=$(ros2 topic list -v $opt 2>/dev/null | awk '/^Published topics:/{p=1; next} /^Subscribed topics:/{p=0} p{print $2}' \
        | grep -E "^$1(_v[0-9]+)?$" | head -1)
    [ -n "$t" ] && { echo $t; return; }
  done
}
rate() { timeout 8 ros2 topic hz "$1" 2>/dev/null | awk '/average rate/{r=$3}END{print r+0}'; }

echo "[bench] depth"
R=$(rate $DEPTH_TOPIC)
awk -v r="$R" -v m="$MIN_DEPTH_HZ" 'BEGIN{exit !(r>=m)}' && pass "$DEPTH_TOPIC at $R Hz" \
  || fail "$DEPTH_TOPIC at ${R:-0} Hz (need $MIN_DEPTH_HZ+; is the ZED running and set to 15 Hz?)"

echo "[bench] flight controller"
echo_once /mavros/state | grep -q "^connected: true" \
  && pass "MAVROS connected" || fail "MAVROS not connected (check fcu_url and the cable)"
ST=$(find_topic /fmu/out/vehicle_status)
if [ -n "$ST" ] && has_data $ST; then pass "XRCE agent: $ST has data"
else fail "XRCE agent: no data on ${ST:-/fmu/out/vehicle_status} (agent port/baud, UXRCE_DDS_CFG, px4_msgs version)"; fi
LP=$(find_topic /fmu/out/vehicle_local_position)
if [ -n "$LP" ] && has_data $LP; then pass "XRCE agent: $LP has data (the bridge needs it)"
else fail "no data on ${LP:-/fmu/out/vehicle_local_position} (the bridge can't hold position)"; fi
has_data /mavros/local_position/odom && pass "PX4 local position on /mavros/local_position/odom" \
  || fail "no /mavros/local_position/odom (PX4 has no position estimate yet)"

if [ "$VISION" = 1 ]; then
  echo "[bench] vision"
  has_data /mavros/vision_pose/pose && pass "ZED pose forwarded to /mavros/vision_pose/pose" \
    || fail "nothing on /mavros/vision_pose/pose (is vision_relay up and the ZED tracking?)"
fi

echo "[bench] planner and explorer"
has_data /vins_estimator/extrinsic && pass "camera mount published to EGO" \
  || fail "no /vins_estimator/extrinsic (extrinsic_node)"
has_data /drone_0_grid/grid_map/occupancy_inflate 10 && pass "EGO map publishing" \
  || fail "EGO map not publishing (is ego_planner_node up?)"
K=$(echo_once /frontier/status | grep -oE "known_m2=[0-9.]+" | cut -d= -f2)
awk -v k="$K" 'BEGIN{exit !(k>0)}' && pass "explorer is mapping ($K m2 seen)" \
  || fail "explorer has seen nothing (status: ${K:-none}); depth or odom not reaching it"

echo "[bench] PX4 settings (check these against hw/README.md)"
for p in EKF2_EV_CTRL EKF2_HGT_REF EKF2_GPS_CTRL EKF2_EV_DELAY EKF2_EV_POS_X EKF2_EV_POS_Y EKF2_EV_POS_Z \
         COM_OF_LOSS_T COM_OBL_RC_ACT UXRCE_DDS_CFG; do
  for _ in 1 2; do   # one retry; the param service is slow under load
    v=$(timeout 10 ros2 param get --no-daemon /mavros/param $p 2>/dev/null | sed -nE "s/^(Double|Integer) value is: //p")
    [ -n "$v" ] && break
  done
  info "$p = ${v:-?}"
done
command -v tegrastats >/dev/null && info "$(timeout 3 tegrastats --interval 1000 | head -1)"

if [ $FAILS = 0 ]; then echo "[bench] PASS"; exit 0; fi
echo "[bench] FAIL ($FAILS checks)"; exit 1
