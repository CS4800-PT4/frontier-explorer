#!/usr/bin/env bash
# Stops the demo and restores PX4's GCS-loss setting.
source /opt/ros/humble/setup.bash
source ~/mavros_ws/install/setup.bash
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
restore_dll
pkill -f "[d]emo.sh"
pkill -9 -f "[g]z sim"; pkill -f "[r]viz2"
pkill -f "[p]x4_sitl_ros2.launch"; pkill -f "[s]ingle_uav_gazebo.launch"; pkill -f "[r]viz.launch"
pkill -f "[o]ffboard_control_test"; pkill -f "[m]avros_node"; pkill -f "[M]icroXRCEAgent"; pkill -f "[b]in/px4 "
pkill -f "[e]go_planner_node"; pkill -f "[t]raj_server"; pkill -f "[d]epth_gz_bridge"; pkill -f "[s]tatic_transform_publisher"
pkill -f "[r]os2 topic echo /goal_pose"
sleep 3
pgrep -af "[g]z sim|[m]avros_node|[b]in/px4 |[r]viz2|[e]go_planner_node" || echo "all stopped"
