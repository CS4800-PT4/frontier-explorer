#!/usr/bin/env bash
# Stops the demo and restores the PX4 settings it changed.
source /opt/ros/humble/setup.bash
source ~/mavros_ws/install/setup.bash
# Restore a PX4 param the demo changed from its saved original; retries, skips the ROS CLI daemon
restore_param() {  # name file
  local f=$2 v
  [ -s $f ] || return 0
  v=$(cat $f)
  echo "$v" | grep -qE "^-?[0-9]+(\.[0-9]+)?$" || { echo "WARNING: bad saved value for $1, dropping $f"; rm -f $f; return 0; }
  for i in 1 2 3 4 5; do
    timeout 15 ros2 param set --no-daemon /mavros/param $1 "$v" >/dev/null 2>&1
    if timeout 15 ros2 param get --no-daemon /mavros/param $1 2>/dev/null | grep -qE "value is: $v$"; then
      echo "restored $1=$v"; rm -f $f; return 0
    fi
    sleep 2
  done
  echo "WARNING: could not restore $1=$v (saved in $f; the next demo/test run will retry)"
}
restore_param NAV_DLL_ACT ~/.ego_sim/nav_dll_act_orig        # GCS-loss action
restore_param COM_OF_LOSS_T ~/.ego_sim/com_of_loss_t_orig    # offboard-loss timeout
pkill -f "[d]emo.sh"
pkill -9 -f "[g]z sim"; pkill -f "[r]viz2"
pkill -f "[p]x4_sitl_ros2.launch"; pkill -f "[s]ingle_uav_gazebo.launch"; pkill -f "[r]viz.launch"
pkill -f "[o]ffboard_control_test"; pkill -f "[m]avros_node"; pkill -f "[M]icroXRCEAgent"; pkill -f "[b]in/px4 "
pkill -f "[e]go_planner_node"; pkill -f "[t]raj_server"; pkill -f "[d]epth_gz_bridge"; pkill -f "[p]arameter_bridge"; pkill -f "[s]tatic_transform_publisher"
pkill -f "[r]os2 topic echo /goal_pose"; pkill -f "[b]ash .*sim/frontier_go.sh"; pkill -f "[l]ib/frontier_explorer/explorer_node"; pkill -f "[r]un frontier_explorer explorer_node"
pkill -f "[h]ardware.launch.py"; pkill -f "[f]ake_zed.py"; pkill -f "[l]ib/frontier_explorer/vision_relay"; pkill -f "[l]ib/frontier_explorer/extrinsic_node"
sleep 3
pgrep -af "[g]z sim|[m]avros_node|[b]in/px4 |[r]viz2|[e]go_planner_node" || echo "all stopped"
