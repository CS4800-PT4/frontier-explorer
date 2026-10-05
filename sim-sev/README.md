# sim-sev

Ubuntu 22.04 VirtualBox stack for the EGO-Planner / PX4 click-to-fly demo.
The other stack stays in ../sim. Do not copy files between these folders.

This folder is the patch and the pin. It is not a runnable workspace.
Do not commit PX4-Autopilot, ego_ws, px4_ego/build, install, or log.

## Pins

- Ubuntu 22.04, ROS 2 Humble, Gazebo Harmonic (ros-humble-ros-gzharmonic)
- PX4 v1.15.4. Do not use main. v1.18 versions messages. v1.14.3 has no gz_bridge.
- px4_msgs: PX4/px4_msgs branch release/1.15, replacing ego-swarm-ros2/utils/px4_msgs
- QGroundControl, Micro XRCE-DDS Agent, MAVROS 2

## What is in this folder

- offboard_control_test.py: patched takeoff node
- px4_sitl_ros2.launch.py: copy into ~/PX4-Autopilot/launch/
- ego.sdf: copy into ~/.simulation-gazebo/worlds/

## Patch

In offboard_control_test.py:

1. Local position subscription is /fmu/out/vehicle_local_position, not _v1.
   The versioned topic never fired the callback, so takeoff published a zero setpoint
   and PX4 auto-disarmed.

2. In position_msg_pub(), both takeoff heights are current z minus 0.9, not absolute -0.9.
   NED z is down. The estimator origin was not the ground, so absolute -0.9 was a descent.

## Setup

git clone --branch v1.15.4 --recursive https://github.com/PX4/PX4-Autopilot.git
cd PX4-Autopilot && make px4_sitl
cp px4_sitl_ros2.launch.py ~/PX4-Autopilot/launch/

mkdir -p ~/ego_ws/src && cd ~/ego_ws/src
git clone https://github.com/DongnanHu6556/ego-swarm-ros2.git
cd ego-swarm-ros2/utils
rm -rf px4_msgs
git clone --branch release/1.15 https://github.com/PX4/px4_msgs.git
cd ~/ego_ws
source /opt/ros/humble/setup.bash
colcon build

git clone https://github.com/DongnanHu6556/px4_ego.git ~/px4_ego
cp offboard_control_test.py ~/px4_ego/src/px4_ego_py/px4_ego_py/offboard_control_test.py
cd ~/px4_ego
source ~/ego_ws/install/setup.bash
colcon build

pip3 install --user 'numpy<2'

Gazebo scripts come from https://github.com/DongnanHu6556/ego-planner-ros2-sim
mkdir -p ~/ros_proj/gazebo_start
cp simulation-gazebo depth_gz_bridge.py ~/ros_proj/gazebo_start
Set the world default in simulation-gazebo to "ego".
cp ego.sdf ~/.simulation-gazebo/worlds/

## Run

C: ros2 launch ~/PX4-Autopilot/launch/px4_sitl_ros2.launch.py
B: ros2 launch ego_planner single_uav_gazebo.launch.py
A: ros2 launch ego_planner rviz.launch.py
D: ros2 run px4_ego_py offboard_control_test
E: python3 ~/px4_ego/mode_key.py

Source Humble, ~/ego_ws/install/setup.bash, and ~/px4_ego/install/setup.bash
before B, A, and D.

t, wait for hover, o, then one 2D Goal Pose in open space.
Pass: /fmu/in/trajectory_setpoint z is about 0.9 more negative than local z,
and QGC altitude climbs. A zero setpoint means the old node is still running.
