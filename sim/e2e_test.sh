#!/usr/bin/env bash
# End-to-end headless test: sim + planner + bridge, takeoff, offboard, send a goal, check drone moved.
# Usage: bash sim/e2e_test.sh [goal_x] [goal_y]
GX=${1:-3.0}; GY=${2:-0.0}
source /opt/ros/humble/setup.bash
source ~/mavros_ws/install/setup.bash
source ~/ros2_ws/install/setup.bash
source ~/ego_ws/install/setup.bash
source ~/px4_ego_ws/install/setup.bash
export GZ_HEADLESS=1   # no Gazebo GUI: test runs anywhere, even without a display
L=~/.ego_sim/e2e_logs; mkdir -p $L
Q="--qos-reliability best_effort"
pos() { timeout 5 ros2 topic echo /mavros/local_position/odom --once --field pose.pose.position 2>/dev/null | tr '\n' ' '; echo; }
# Send a mode key a few times: a single --once publish can be lost before discovery completes
key() { timeout 4 ros2 topic pub -r 2 -t 3 /mode_key std_msgs/msg/String "{data: $1}" >/dev/null 2>&1; }
alt() { timeout 5 ros2 topic echo /mavros/local_position/odom --once --field pose.pose.position.z 2>/dev/null | head -1; }
# Take off and wait until actually hovering (z > 0.6 m); retry the key if not
takeoff() {
  for try in 1 2 3; do
    key t
    for i in $(seq 1 15); do sleep 2; z=$(alt); awk -v z="$z" 'BEGIN{exit !(z>0.6)}' && return 0; done
    echo "    takeoff attempt $try: z=${z:-?}, retrying"
  done
  echo "    TAKEOFF FAILED - check $L/C_px4.log for 'Arming denied'"; return 1
}

# Restore PX4's GCS-loss action (NAV_DLL_ACT) from the saved original; retries, skips the ROS CLI daemon
restore_dll() {
  local f=~/.ego_sim/nav_dll_act_orig v
  [ -s $f ] || return 0
  v=$(cat $f)
  for i in 1 2 3; do
    timeout 15 ros2 param set --no-daemon /mavros/param NAV_DLL_ACT "$v" >/dev/null 2>&1
    if timeout 15 ros2 param get --no-daemon /mavros/param NAV_DLL_ACT 2>/dev/null | grep -qE "value is: $v$"; then
      echo "restored NAV_DLL_ACT=$v"; rm -f $f; return 0
    fi
    sleep 2
  done
  echo "WARNING: could not restore NAV_DLL_ACT=$v (saved in $f; the next demo/test run will retry)"
}

cleanup() {
  # Restore the GCS-loss action changed below (PX4 SITL saves params across runs)
  restore_dll
  pkill -9 -f "[g]z sim"
  pkill -f "[p]x4_sitl_ros2.launch"; pkill -f "[s]ingle_uav_gazebo.launch"; pkill -f "[o]ffboard_control_test"
  pkill -f "[g]z sim"; pkill -f "[m]avros_node"; pkill -f "[M]icroXRCEAgent"; pkill -f "[b]in/px4 "
  pkill -f "[e]go_planner_node"; pkill -f "[t]raj_server"; pkill -f "[d]epth_gz_bridge"; pkill -f "[s]tatic_transform_publisher"
}
trap cleanup EXIT

ros2 launch ~/PX4-Autopilot/launch/px4_sitl_ros2.launch.py > $L/C_px4.log 2>&1 &
sleep 45
# No QGC in a headless test -> PX4 refuses to arm ("No connection to the GCS").
# Temporarily disable the GCS-loss action for this run; cleanup() restores it.
# The original is kept in a file so an interrupted run can't lose it.
DLL_FILE=~/.ego_sim/nav_dll_act_orig
[ -s $DLL_FILE ] || ros2 param get --no-daemon /mavros/param NAV_DLL_ACT 2>/dev/null | grep -oE "[0-9]+$" > $DLL_FILE
DLL_ORIG=$(cat $DLL_FILE)
ros2 param set --no-daemon /mavros/param NAV_DLL_ACT 0 >/dev/null 2>&1
echo "--- NAV_DLL_ACT was ${DLL_ORIG:-?}, now $(ros2 param get --no-daemon /mavros/param NAV_DLL_ACT 2>&1 | grep -oE "[0-9]+$")"
ros2 launch ego_planner single_uav_gazebo.launch.py > $L/B_ego.log 2>&1 &
ros2 run px4_ego_py offboard_control_test > $L/D_bridge.log 2>&1 &
sleep 10

echo "--- depth_bestef encoding:"; timeout 8 ros2 topic echo $Q /depth_camera_bestef --once --field encoding 2>&1 | head -1
echo "--- start pos:"; pos
echo "--- takeoff (t)"; takeoff; sleep 3
echo "--- pos after takeoff:"; pos
echo "--- offboard (o)"; key o; sleep 3
echo "--- goal ($GX, $GY)"
timeout 4 ros2 topic pub -r 2 -t 3 /goal_pose geometry_msgs/msg/PoseStamped "{header: {frame_id: world}, pose: {position: {x: $GX, y: $GY, z: 0.0}, orientation: {w: 1.0}}}" >/dev/null 2>&1
sleep 4
echo "--- pos_cmd:"; timeout 5 ros2 topic echo /drone_0_planning/pos_cmd --once --field position 2>&1 | tr '\n' ' '; echo
sleep 16
echo "--- pos after goal:"; pos
if [ -n "$3" ]; then
  # Second goal sent right after the first, while the planner is busy (used to crash it)
  GX2=$3; GY2=${4:-0.0}
  echo "--- 2nd goal ($GX2, $GY2) sent mid-flight"
  timeout 4 ros2 topic pub -r 2 -t 3 /goal_pose geometry_msgs/msg/PoseStamped "{header: {frame_id: world}, pose: {position: {x: $GX, y: $GY, z: 0.0}, orientation: {w: 1.0}}}" >/dev/null 2>&1
  timeout 4 ros2 topic pub -r 2 -t 3 /goal_pose geometry_msgs/msg/PoseStamped "{header: {frame_id: world}, pose: {position: {x: $GX2, y: $GY2, z: 0.0}, orientation: {w: 1.0}}}" >/dev/null 2>&1
  sleep 20
  echo "--- pos after 2nd goal:"; pos
  echo "--- planner alive: $(pgrep -f "[e]go_planner_node" >/dev/null && echo yes || echo NO - crashed)"
fi
echo "--- planner log:"; grep -aE "Triggered|no odom|wait for goal|GEN_NEW_TRAJ|EXEC_TRAJ|REACH|ERROR" $L/B_ego.log | sort | uniq -c | sort -rn | head -8
echo "--- bridge log:"; grep -aoE "offboard velocity|No command in offboard.*|takeoff|Switching to offboard mode|Arm command sent" $L/D_bridge.log | sort | uniq -c | head -8
