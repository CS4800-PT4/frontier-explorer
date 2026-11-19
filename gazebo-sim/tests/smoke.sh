#!/usr/bin/env bash
# Smoke test: launch PX4+Gazebo+MAVROS for ~100 s, check key topics, shut down.
source /opt/ros/humble/setup.bash
source ~/mavros_ws/install/setup.bash
source ~/ros2_ws/install/setup.bash
source ~/ego_ws/install/setup.bash
source ~/px4_ego_ws/install/setup.bash
mkdir -p ~/.ego_sim
Q="--qos-reliability best_effort"

timeout 110 ros2 launch ~/PX4-Autopilot/launch/px4_sitl_ros2.launch.py > ~/.ego_sim/smoke.log 2>&1 &
sleep 60

echo "--- mavros odom:";  timeout 8 ros2 topic hz /mavros/local_position/odom 2>&1 | grep -m1 "average rate" || echo NO_ODOM
echo "--- px4 status_v4:"; timeout 8 ros2 topic echo $Q /fmu/out/vehicle_status_v4 --once 2>&1 | grep -m2 -E "arming_state|nav_state" || echo NO_STATUS
echo "--- px4 local_pos_v1:"; timeout 8 ros2 topic echo $Q /fmu/out/vehicle_local_position_v1 --once 2>&1 | grep -m1 -E "^z:" || echo NO_LOCALPOS
echo "--- gz depth topics:"; gz topic -l 2>/dev/null | grep -i depth
echo "--- ros depth topics:"; ros2 topic list | grep -i depth
echo "--- /depth_camera:";  timeout 8 ros2 topic hz /depth_camera 2>&1 | grep -m1 "average rate" || echo NO_RAW_DEPTH
echo "--- /depth_camera_bestef:"; timeout 8 ros2 topic hz $Q /depth_camera_bestef 2>&1 | grep -m1 "average rate" || echo NO_DEPTH
echo "--- gz model:"; gz model --list 2>/dev/null | tail -3
echo "--- errors:"; grep -E "Traceback|process has died|\[ERROR\]" ~/.ego_sim/smoke.log | grep -v "FCU: EVENT" | head -5

wait
pgrep -af "gz sim|bin/px4 |MicroXRCEAgent|mavros_node" | grep -v pgrep || echo ALL_STOPPED
