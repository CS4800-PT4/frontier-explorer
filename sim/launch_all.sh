#!/usr/bin/env bash
# Opens each piece of the stack in its own Windows Terminal tab.
# Usage (from WSL): bash sim/launch_all.sh
ENV='source /opt/ros/humble/setup.bash; source ~/mavros_ws/install/setup.bash; source ~/ros2_ws/install/setup.bash; source ~/ego_ws/install/setup.bash; source ~/px4_ego_ws/install/setup.bash'

tab() { wt.exe -w 0 new-tab --title "$1" wsl.exe -e bash -ic "$ENV; $2; exec bash" & sleep "${3:-2}"; }

tab "C: PX4+Gazebo" "ros2 launch ~/PX4-Autopilot/launch/px4_sitl_ros2.launch.py" 15
tab "B: EGO"        "ros2 launch ego_planner single_uav_gazebo.launch.py"
tab "A: RViz"       "ros2 launch ego_planner rviz.launch.py"
tab "D: Offboard"   "ros2 run px4_ego_py offboard_control_test"
tab "E: Keys"       "cd ~/px4_ego_ws/src/px4_ego && python3 mode_key.py"
tab "Check"         "echo 'Checks: ros2 topic hz /mavros/local_position/odom | ros2 topic hz /drone_0_planning/pos_cmd'"
