#!/usr/bin/env bash
# Restarts only the EGO planner (e.g. after editing its launch params) while the sim keeps running.
pkill -f "[s]ingle_uav_gazebo.launch"; sleep 2
pkill -f "[e]go_planner_node"; pkill -f "[t]raj_server"; pkill -f "[s]tatic_transform_publisher"; sleep 1
source /opt/ros/humble/setup.bash
source ~/mavros_ws/install/setup.bash
source ~/ros2_ws/install/setup.bash
source ~/ego_ws/install/setup.bash
mkdir -p ~/.ego_sim/demo_logs
setsid nohup ros2 launch ego_planner single_uav_gazebo.launch.py > ~/.ego_sim/demo_logs/B_ego.log 2>&1 < /dev/null &
sleep 8
echo "planner map_size_x: $(ros2 param get /drone_0_ego_planner_node grid_map/map_size_x 2>&1)"
