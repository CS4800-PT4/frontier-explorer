#!/usr/bin/env bash
# Bench check for the hardware stack (props off). Run it in a second terminal while
# hardware.launch.py is up and something is in front of the camera (a wall or a box within
# 4 m). It checks every link the flight needs and the PX4 settings that matter, then says
# PASS or FAIL. The sim test runs it too.
# Usage: bash hw/bench_check.sh
#   DEPTH_TOPIC=...   depth topic to time (default the ZED one)
#   VISION=0          skip the vision checks (when PX4 gets position some other way)
#   MIN_DEPTH_HZ=10   lowest depth rate that passes (the sim test uses 5; its camera is slower)
#   SIM=1             PX4 SITL flies on simulated GPS: don't require vision fusion or the
#                     drone's PX4 settings (set by the sim test)
DEPTH_TOPIC=${DEPTH_TOPIC:-/zed/zed_node/depth/depth_registered}
MIN_DEPTH_HZ=${MIN_DEPTH_HZ:-10}
VISION=${VISION:-1}
SIM=${SIM:-0}
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
LPMSG=$([ -n "$LP" ] && echo_once $LP)
if echo "$LPMSG" | grep -q "^---$"; then pass "XRCE agent: $LP has data (the bridge needs it)"
else fail "no data on ${LP:-/fmu/out/vehicle_local_position} (the bridge can't hold position)"; fi
# PX4 keeps publishing local position when it has no estimate, so check the valid flags
if echo "$LPMSG" | grep -q "^xy_valid: true" && echo "$LPMSG" | grep -q "^z_valid: true"; then
  pass "PX4 has a valid position estimate (xy_valid, z_valid)"
else
  fail "PX4 position not valid (xy_valid/z_valid false): check the EKF2_EV_* settings and that the ZED is tracking"
fi
has_data /mavros/local_position/odom && pass "PX4 local position on /mavros/local_position/odom" \
  || fail "no /mavros/local_position/odom (PX4 has no position estimate yet)"

if [ "$VISION" = 1 ]; then
  echo "[bench] vision"
  has_data /mavros/vision_pose/pose_cov && pass "ZED pose forwarded to /mavros/vision_pose/pose_cov" \
    || fail "nothing on /mavros/vision_pose/pose_cov (is vision_relay up and the ZED tracking? see its log)"
  if [ "$SIM" != 1 ]; then
    EF=$(find_topic /fmu/out/estimator_status_flags)
    if [ -z "$EF" ]; then info "no /fmu/out/estimator_status_flags, can't check EKF2 is using the ZED"
    else
      EFMSG=$(echo_once $EF)
      echo "$EFMSG" | grep -q "^cs_ev_pos: true" && pass "EKF2 is fusing the ZED position" \
        || fail "EKF2 is not fusing the ZED position (cs_ev_pos false: EKF2_EV_CTRL, EKF2_EV_DELAY, EV_POS)"
      echo "$EFMSG" | grep -q "^cs_ev_hgt: true" && info "EKF2 takes height from the ZED" \
        || info "EKF2 is not taking height from the ZED (fine if EKF2_HGT_REF is baro on purpose)"
    fi
  fi
fi

echo "[bench] planner and explorer"
has_data /vins_estimator/extrinsic && pass "camera mount published to EGO" \
  || fail "no /vins_estimator/extrinsic (extrinsic_node)"
# A map message alone only shows EGO is up. Occupied points show it is fusing depth, which
# also arms its depth-loss stop.
MAP=$(timeout 15 ros2 topic echo /drone_0_grid/grid_map/occupancy_inflate --once --no-arr 2>/dev/null \
      | awk '/^width:/{print $2; exit}')
if [ -z "$MAP" ]; then fail "EGO map not publishing (is ego_planner_node up?)"
elif [ "$MAP" -gt 0 ]; then pass "EGO is mapping from depth ($MAP occupied points)"
else fail "EGO map is empty: it is not fusing depth (depth_topic, odom, stamps) or nothing is within 4 m"; fi
K=$(echo_once /frontier/status | grep -oE "known_m2=[0-9.]+" | cut -d= -f2)
awk -v k="$K" 'BEGIN{exit !(k>0)}' && pass "explorer is mapping ($K m2 seen)" \
  || fail "explorer has seen nothing (status: ${K:-none}); depth or odom not reaching it"

echo "[bench] PX4 settings (hw/README.md has the full table)"
param() {
  local v
  for _ in 1 2; do   # one retry; the param service is slow under load
    v=$(timeout 10 ros2 param get --no-daemon /mavros/param $1 2>/dev/null | sed -nE "s/^(Double|Integer) value is: //p")
    [ -n "$v" ] && break
  done
  echo "$v"
}
for p in EKF2_HGT_REF EKF2_EV_DELAY EKF2_EV_POS_X EKF2_EV_POS_Y EKF2_EV_POS_Z COM_OF_LOSS_T COM_OBL_RC_ACT UXRCE_DDS_CFG; do
  v=$(param $p); info "$p = ${v:-?}"
done
if [ "$SIM" != 1 ]; then
  v=$(param EKF2_EV_CTRL)
  # bit 0 = horizontal position, bit 3 = yaw; 11 adds height, 9 leaves height to the baro
  if [ -n "$v" ] && [ $((v & 9)) = 9 ]; then pass "EKF2_EV_CTRL = $v (uses the ZED position and yaw)"
  else fail "EKF2_EV_CTRL = ${v:-?}, want 11 (or 9 for a ZED without an IMU, see hw/README.md)"; fi
  v=$(param EKF2_GPS_CTRL)
  [ "$v" = 0 ] && pass "EKF2_GPS_CTRL = 0" || fail "EKF2_GPS_CTRL = ${v:-?}, want 0 indoors"
fi
command -v tegrastats >/dev/null && info "$(timeout 3 tegrastats --interval 1000 | head -1)"

if [ $FAILS = 0 ]; then echo "[bench] PASS"; exit 0; fi
echo "[bench] FAIL ($FAILS checks)"; exit 1
