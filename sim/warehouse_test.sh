#!/usr/bin/env bash
# Headless obstacle course in the warehouse: between the shelf rows, down the aisle beside
# the crates, to the far end, and back to the start. Pass = every goal reached and the planner
# still running. Needs: bash sim/warehouse_setup.sh (done by 2_user_setup.sh).
# Usage: bash sim/warehouse_test.sh      (EGO_* env vars override the warehouse settings)
source /opt/ros/humble/setup.bash
source ~/mavros_ws/install/setup.bash
source ~/ros2_ws/install/setup.bash
source ~/ego_ws/install/setup.bash
source ~/px4_ego_ws/install/setup.bash
export GZ_WORLD=default_warehouse GZ_HEADLESS=1
export EGO_INFLATION=${EGO_INFLATION:-0.4} EGO_GROUND=${EGO_GROUND:-0.3} EGO_CEIL=${EGO_CEIL:-1.6}
L=~/.ego_sim/warehouse_logs; rm -rf $L; mkdir -p $L
DLL_FILE=~/.ego_sim/nav_dll_act_orig
xy() { timeout 5 ros2 topic echo /mavros/local_position/odom --once --field pose.pose.position 2>/dev/null | awk '/^x:/{x=$2}/^y:/{y=$2}/^z:/{z=$2}END{if(x!="")printf "%.2f %.2f %.2f",x,y,z}'; }
key() { timeout 4 ros2 topic pub -r 2 -t 3 /mode_key std_msgs/msg/String "{data: $1}" >/dev/null 2>&1; }

restore_dll() {
  local v; [ -s $DLL_FILE ] || return 0; v=$(cat $DLL_FILE)
  for i in 1 2 3; do
    timeout 15 ros2 param set --no-daemon /mavros/param NAV_DLL_ACT "$v" >/dev/null 2>&1
    timeout 15 ros2 param get --no-daemon /mavros/param NAV_DLL_ACT 2>/dev/null | grep -qE "value is: $v$" && { rm -f $DLL_FILE; return 0; }
    sleep 2
  done
  echo "WARNING: could not restore NAV_DLL_ACT=$v (saved in $DLL_FILE; the next demo/test run will retry)"
}
cleanup() {
  restore_dll
  pkill -f "[p]x4_sitl_ros2.launch"; pkill -f "[s]ingle_uav_gazebo.launch"; pkill -f "[o]ffboard_control_test"
  pkill -9 -f "[g]z sim"; pkill -f "[m]avros_node"; pkill -f "[M]icroXRCEAgent"; pkill -f "[b]in/px4 "
  pkill -f "[e]go_planner_node"; pkill -f "[t]raj_server"; pkill -f "[d]epth_gz_bridge"; pkill -f "[p]arameter_bridge"
  pkill -f "[s]tatic_transform_publisher"
}
trap cleanup EXIT

echo "[warehouse] settings: inflation=$EGO_INFLATION ground=$EGO_GROUND ceil=$EGO_CEIL depth_timeout=${EGO_DEPTH_TIMEOUT:-1.0}"
ros2 launch ~/PX4-Autopilot/launch/px4_sitl_ros2.launch.py > $L/C_px4.log 2>&1 &
sleep 45
grep -aq "Gazebo world is ready" $L/C_px4.log || { echo "FAIL: PX4 never found the Gazebo world (see $L/C_px4.log)"; exit 1; }
# No QGC in a headless test -> PX4 refuses to arm. Turn off the GCS-loss action (cleanup restores it).
# MAVROS's param service can take a while to come up, so retry until it reads back 0.
for i in $(seq 1 10); do
  [ -s $DLL_FILE ] || ros2 param get --no-daemon /mavros/param NAV_DLL_ACT 2>/dev/null | grep -oE "[0-9]+$" > $DLL_FILE
  ros2 param set --no-daemon /mavros/param NAV_DLL_ACT 0 >/dev/null 2>&1
  ros2 param get --no-daemon /mavros/param NAV_DLL_ACT 2>/dev/null | grep -qE "value is: 0$" && break
  sleep 3
done
ros2 param get --no-daemon /mavros/param NAV_DLL_ACT 2>/dev/null | grep -qE "value is: 0$" || { echo "FAIL: could not set NAV_DLL_ACT=0 (MAVROS params not ready)"; exit 1; }
ros2 launch ego_planner single_uav_gazebo.launch.py > $L/B_ego.log 2>&1 &
PYTHONUNBUFFERED=1 ros2 run px4_ego_py offboard_control_test > $L/D_bridge.log 2>&1 &
sleep 10

echo "[warehouse] takeoff"
for try in 1 2 3; do
  key t; for i in $(seq 1 15); do sleep 2; z=$(xy | cut -d' ' -f3); awk -v z="$z" 'BEGIN{exit !(z>0.6)}' && break 2; done
done
awk -v z="$z" 'BEGIN{exit !(z>0.6)}' || { echo "FAIL: no takeoff (z=${z:-?}); check $L/C_px4.log for 'Arming denied'"; exit 1; }
echo "[warehouse] offboard"
for try in 1 2 3 4 5; do key o; sleep 3; grep -aqE "No command in offboard|offboard velocity" $L/D_bridge.log && break; done
grep -aqE "No command in offboard|offboard velocity" $L/D_bridge.log || { echo "FAIL: bridge never entered offboard"; exit 1; }

# Goals in planner coordinates (= Gazebo + 6 m in x)
PASS=0; N=0
goal() {  # x y wait label
  N=$((N+1))
  # A fresh `ros2 topic pub` can send before discovery finishes; re-send until the planner triggers
  local before; before=$(grep -ac "Triggered!" $L/B_ego.log)
  for try in 1 2 3; do
    timeout 4 ros2 topic pub -r 2 -t 3 /goal_pose geometry_msgs/msg/PoseStamped "{header: {frame_id: world}, pose: {position: {x: $1, y: $2, z: 0.0}, orientation: {w: 1.0}}}" >/dev/null 2>&1
    [ "$(grep -ac "Triggered!" $L/B_ego.log)" -gt "$before" ] && break
  done
  sleep $3
  local p; p=$(xy)
  if [ -n "$p" ] && awk -v p="$p" -v gx=$1 -v gy=$2 'BEGIN{split(p,a," "); exit !((a[1]-gx)^2+(a[2]-gy)^2 < 0.25 && a[3] > 0.25)}'; then
    PASS=$((PASS+1)); echo "  PASS  $4: at ($p)"
  else
    echo "  FAIL  $4: goal ($1, $2), drone at (${p:-no odometry})"
  fi
}
goal 10.0  2.5 35 "aisle between shelf rows"
goal 14.0 -0.8 35 "narrow aisle beside the crates"
goal 18.5  5.5 35 "far end of the warehouse"
goal  0.0  0.0 45 "back to start"

ALIVE=$(pgrep -f "[e]go_planner_node" >/dev/null && echo yes || echo no)
echo "[warehouse] planner still running: $ALIVE"
if [ $PASS -eq $N ] && [ $ALIVE = yes ]; then echo "[warehouse] PASS ($PASS/$N goals)"; exit 0
else echo "[warehouse] FAIL ($PASS/$N goals; logs in $L)"; exit 1; fi
