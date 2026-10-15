#!/usr/bin/env bash
# Headless test of the frontier explorer (R1) in the warehouse: takes off, then flies to the
# explorer's best frontier several times in a row. Pass = the map is published, the seen area
# grows, the drone reaches all but at most one frontier goal, and every node is still running.
# Needs: bash sim/warehouse_setup.sh (done by 2_user_setup.sh).
# Usage: bash sim/frontier_test.sh [steps]     (default 5; EGO_* env vars work as in demo.sh)
REPO=$(cd "$(dirname "$0")/.." && pwd)
STEPS=${1:-5}
source /opt/ros/humble/setup.bash
source ~/mavros_ws/install/setup.bash
source ~/ros2_ws/install/setup.bash
source ~/ego_ws/install/setup.bash
source ~/px4_ego_ws/install/setup.bash
export GZ_WORLD=default_warehouse GZ_HEADLESS=1
export EGO_INFLATION=${EGO_INFLATION:-0.4} EGO_GROUND=${EGO_GROUND:-0.3} EGO_CEIL=${EGO_CEIL:-1.6}
export EGO_DEPTH_TIMEOUT=${EGO_DEPTH_TIMEOUT:-3.0}   # rides out the ~2 s WSL stalls
if pgrep -f "[g]z sim|[b]in/px4 |[m]avros_node" >/dev/null; then
  echo "FAIL: a simulation is already running. Stop it first: bash sim/demo_stop.sh"; exit 1
fi
L=~/.ego_sim/frontier_logs; rm -rf $L; mkdir -p $L
DLL_FILE=~/.ego_sim/nav_dll_act_orig
OFL_FILE=~/.ego_sim/com_of_loss_t_orig
( cd $REPO && colcon build --symlink-install --packages-select frontier_explorer ) > $L/build.log 2>&1 \
  || { echo "FAIL: frontier_explorer build failed (see $L/build.log)"; exit 1; }
source $REPO/install/setup.bash
xy() { timeout 5 ros2 topic echo /mavros/local_position/odom --once --field pose.pose.position 2>/dev/null | awk '/^x:/{x=$2}/^y:/{y=$2}/^z:/{z=$2}END{if(x!="")printf "%.2f %.2f %.2f",x,y,z}'; }
key() { timeout 4 ros2 topic pub -r 2 -t 3 /mode_key std_msgs/msg/String "{data: $1}" >/dev/null 2>&1; }
status() { timeout 5 ros2 topic echo /frontier/status --once --field data 2>/dev/null | head -1; }
known() { local k; for i in 1 2 3; do k=$(status | grep -oE "known_m2=[0-9.]+" | cut -d= -f2); [ -n "$k" ] && break; done; echo "$k"; }

restore_param() {  # name file
  local v; [ -s $2 ] || return 0; v=$(cat $2)
  echo "$v" | grep -qE "^-?[0-9]+(\.[0-9]+)?$" || { echo "WARNING: bad saved value for $1, dropping $2"; rm -f $2; return 0; }
  for i in 1 2 3 4 5; do
    timeout 15 ros2 param set --no-daemon /mavros/param $1 "$v" >/dev/null 2>&1
    timeout 15 ros2 param get --no-daemon /mavros/param $1 2>/dev/null | grep -qE "value is: $v$" && { rm -f $2; return 0; }
    sleep 2
  done
  echo "WARNING: could not restore $1=$v (saved in $2; the next demo/test run will retry)"
}
cleanup() {
  restore_param NAV_DLL_ACT $DLL_FILE
  restore_param COM_OF_LOSS_T $OFL_FILE
  pkill -f "[l]ib/frontier_explorer/explorer_node"; pkill -f "[r]un frontier_explorer explorer_node"
  pkill -f "[p]x4_sitl_ros2.launch"; pkill -f "[s]ingle_uav_gazebo.launch"; pkill -f "[o]ffboard_control_test"
  pkill -9 -f "[g]z sim"; pkill -f "[m]avros_node"; pkill -f "[M]icroXRCEAgent"; pkill -f "[b]in/px4 "
  pkill -f "[e]go_planner_node"; pkill -f "[t]raj_server"; pkill -f "[d]epth_gz_bridge"; pkill -f "[p]arameter_bridge"
  pkill -f "[s]tatic_transform_publisher"
}
trap cleanup EXIT

echo "[frontier] settings: inflation=$EGO_INFLATION ground=$EGO_GROUND ceil=$EGO_CEIL depth_timeout=$EGO_DEPTH_TIMEOUT steps=$STEPS"
ros2 launch ~/PX4-Autopilot/launch/px4_sitl_ros2.launch.py > $L/C_px4.log 2>&1 &
sleep 45
grep -aq "Gazebo world is ready" $L/C_px4.log || { echo "FAIL: PX4 never found the Gazebo world (see $L/C_px4.log)"; exit 1; }
# No QGC in a headless test -> PX4 refuses to arm. Turn off the GCS-loss action (cleanup restores it).
for i in $(seq 1 10); do
  [ -s $DLL_FILE ] || ros2 param get --no-daemon /mavros/param NAV_DLL_ACT 2>/dev/null | grep -oE "[0-9]+$" > $DLL_FILE
  ros2 param set --no-daemon /mavros/param NAV_DLL_ACT 0 >/dev/null 2>&1
  ros2 param get --no-daemon /mavros/param NAV_DLL_ACT 2>/dev/null | grep -qE "value is: 0$" && break
  sleep 3
done
ros2 param get --no-daemon /mavros/param NAV_DLL_ACT 2>/dev/null | grep -qE "value is: 0$" || { echo "FAIL: could not set NAV_DLL_ACT=0 (MAVROS params not ready)"; exit 1; }
# WSL can stall ROS traffic for ~2 s (EGO logs "odom or depth lost"). PX4's sim default drops
# offboard after 1 s without a setpoint and flies home, so allow 5 s. Cleanup restores it.
if [ ! -s $OFL_FILE ]; then
  for i in 1 2 3 4 5; do
    v=$(timeout 15 ros2 param get --no-daemon /mavros/param COM_OF_LOSS_T 2>/dev/null | sed -nE "s/^(Double|Integer) value is: (-?[0-9]+(\.[0-9]+)?)$/\2/p")
    [ -n "$v" ] && break; sleep 2
  done
  [ -n "$v" ] || { echo "FAIL: could not read COM_OF_LOSS_T"; exit 1; }
  echo "$v" > $OFL_FILE
fi
ros2 param set --no-daemon /mavros/param COM_OF_LOSS_T 5.0 >/dev/null 2>&1
ros2 param get --no-daemon /mavros/param COM_OF_LOSS_T 2>/dev/null | grep -qE "value is: 5(\.0)?$" || { echo "FAIL: could not set COM_OF_LOSS_T=5.0"; exit 1; }
ros2 launch ego_planner single_uav_gazebo.launch.py > $L/B_ego.log 2>&1 &
PYTHONUNBUFFERED=1 ros2 run px4_ego_py offboard_control_test > $L/D_bridge.log 2>&1 &
PYTHONUNBUFFERED=1 ros2 run frontier_explorer explorer_node > $L/E_explorer.log 2>&1 &
sleep 10

W=$(timeout 10 ros2 topic echo /frontier/map --once --field info.width 2>/dev/null | head -1)
[ -n "$W" ] && [ "$W" -gt 0 ] || { echo "FAIL: /frontier/map not published (see $L/E_explorer.log)"; exit 1; }
echo "[frontier] map published ($W cells wide)"

echo "[frontier] takeoff"
for try in 1 2 3; do
  key t; for i in $(seq 1 15); do sleep 2; z=$(xy | cut -d' ' -f3); awk -v z="$z" 'BEGIN{exit !(z>0.6)}' && break 2; done
done
awk -v z="$z" 'BEGIN{exit !(z>0.6)}' || { echo "FAIL: no takeoff (z=${z:-?}); check $L/C_px4.log for 'Arming denied'"; exit 1; }
sleep 3
K0=$(known)
[ -n "$K0" ] || { echo "FAIL: could not read /frontier/status after takeoff (see $L/E_explorer.log)"; exit 1; }
echo "[frontier] seen after takeoff: $K0 m2"
# The bridge only holds offboard for ~10 s without a planner command (PX4 then reports
# "No offboard signal" and returns home), so the first frontier goal goes out right away
echo "[frontier] offboard"
for try in 1 2 3 4 5; do key o; sleep 1; grep -aqE "No command in offboard|offboard velocity" $L/D_bridge.log && break; done
grep -aqE "No command in offboard|offboard velocity" $L/D_bridge.log || { echo "FAIL: bridge never entered offboard"; exit 1; }

REACHED=0
for s in $(seq 1 $STEPS); do
  bash $REPO/sim/frontier_go.sh 1 2>&1 | sed "s/step 1\/1/step $s\/$STEPS/" | tee -a $L/go.log
  [ "${PIPESTATUS[0]}" = 0 ] && REACHED=$((REACHED+1))
done
K1=$(known)

ALIVE=yes
pgrep -f "[e]go_planner_node" >/dev/null || ALIVE="no (planner died)"
pgrep -f "[o]ffboard_control_test" >/dev/null || ALIVE="no (offboard bridge died)"
pgrep -f "[l]ib/frontier_explorer/explorer_node" >/dev/null || ALIVE="no (explorer_node died)"
GREW=$(awk -v a="$K0" -v b="${K1:-0}" 'BEGIN{print (b - a >= 20) ? "yes" : "no"}')
MIN=$(( STEPS > 1 ? STEPS - 1 : 1 ))
echo "[frontier] seen area: ${K0:-?} -> ${K1:-?} m2 (grew 20+ m2: $GREW)"
echo "[frontier] frontier goals reached: $REACHED/$STEPS"
echo "[frontier] all nodes still running: $ALIVE"
FS=$(grep -ac "Failsafe activated" $L/C_px4.log)
echo "[frontier] PX4 failsafes: $FS"
if [ $GREW = yes ] && [ $REACHED -ge $MIN ] && [ "$ALIVE" = yes ] && [ "$FS" = 0 ]; then
  echo "[frontier] PASS"; exit 0
else
  echo "[frontier] FAIL (logs in $L)"; exit 1
fi
