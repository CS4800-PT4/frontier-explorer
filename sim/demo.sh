#!/usr/bin/env bash
# Live GUI demo: Gazebo + RViz on screen, auto takeoff/offboard, one demo goal,
# then stays up so you can click 2D Goal Pose in RViz. Stop with: bash sim/demo_stop.sh
if pgrep -f "[g]z sim|[b]in/px4 |[m]avros_node" >/dev/null; then
  echo "[demo] A simulation is already running. Stop it first: bash sim/demo_stop.sh"; exit 1
fi
source /opt/ros/humble/setup.bash
source ~/mavros_ws/install/setup.bash
source ~/ros2_ws/install/setup.bash
source ~/ego_ws/install/setup.bash
source ~/px4_ego_ws/install/setup.bash
L=~/.ego_sim/demo_logs; mkdir -p $L
DLL_FILE=~/.ego_sim/nav_dll_act_orig
pos() { timeout 5 ros2 topic echo /mavros/local_position/odom --once --field pose.pose.position 2>/dev/null | awk '{printf "%s %.2f  ", $1, $2}'; echo; }
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

echo "[demo] starting PX4 + Gazebo + MAVROS"
ros2 launch ~/PX4-Autopilot/launch/px4_sitl_ros2.launch.py > $L/C_px4.log 2>&1 &
sleep 45
[ -s $DLL_FILE ] || ros2 param get --no-daemon /mavros/param NAV_DLL_ACT 2>/dev/null | grep -oE "[0-9]+$" > $DLL_FILE
ros2 param set --no-daemon /mavros/param NAV_DLL_ACT 0 >/dev/null 2>&1   # no QGC needed; demo_stop.sh restores it

echo "[demo] starting EGO planner, RViz, offboard bridge"
ros2 launch ego_planner single_uav_gazebo.launch.py > $L/B_ego.log 2>&1 &
ros2 launch ego_planner rviz.launch.py > $L/A_rviz.log 2>&1 &
ros2 run px4_ego_py offboard_control_test > $L/D_bridge.log 2>&1 &
sleep 10

echo "[demo] takeoff";  takeoff || exit 1; sleep 3; echo -n "[demo] hover pos: "; pos
echo "[demo] offboard"; key o; sleep 3
echo "[demo] demo goal (4, 2)"
timeout 4 ros2 topic pub -r 2 -t 3 /goal_pose geometry_msgs/msg/PoseStamped "{header: {frame_id: world}, pose: {position: {x: 4.0, y: 2.0, z: 0.0}, orientation: {w: 1.0}}}" >/dev/null 2>&1
sleep 20; echo -n "[demo] pos after demo goal: "; pos
echo "[demo] READY - click 2D Goal Pose in RViz"

# Log every goal clicked in RViz and where the drone ends up
ros2 topic echo /goal_pose geometry_msgs/msg/PoseStamped --field pose.position > $L/goals.log 2>&1 &
while true; do echo "$(date +%T) $(pos)" >> $L/positions.log; sleep 2; done
