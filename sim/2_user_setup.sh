#!/usr/bin/env bash
# Part 2 (no sudo): clone, apply our patches, copy sim files, build. Safe to re-run.
# Run after: sudo bash sim/1_sudo_install.sh
# Expects PX4-Autopilot, ~/ros2_ws (px4_msgs matching PX4) and MicroXRCEAgent to already exist.
set -eo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PATCHES=$HERE/patches
source /opt/ros/humble/setup.bash

clone() { [ -d "${@: -1}/.git" ] || git clone "$@"; }   # last arg = target dir

# Put a repo on branch 'sim-fixes' with our patches applied (skips if already done)
apply_patches() {  # repo_dir patch_subdir
  cd "$1"
  if git rev-parse --verify -q sim-fixes >/dev/null; then git checkout -q sim-fixes
  else
    git checkout -q -b sim-fixes
    git -c user.name="${GIT_NAME:-sim-setup}" -c user.email="${GIT_EMAIL:-sim-setup@localhost}" am -q "$PATCHES/$2"/*.patch
  fi
  cd - >/dev/null
}

# --- NumPy: PX4's setup pip-installs NumPy 2.x into ~/.local, which breaks
#     ROS Humble's cv_bridge/OpenCV (depth_gz_bridge.py crashes with _ARRAY_API not found)
pip3 install --user -q "numpy<2"

# --- MAVROS from source (ros-humble-mavros binary is missing from the ROS apt repo) ---
mkdir -p ~/mavros_ws/src
clone --depth 1 --branch 2.15.1 https://github.com/mavlink/mavros.git ~/mavros_ws/src/mavros
# mavros_msgs comes from apt (2.15.1); skip tests/examples
touch ~/mavros_ws/src/mavros/{mavros_msgs,test_mavros,mavros_examples}/COLCON_IGNORE
( cd ~/mavros_ws && MAKEFLAGS=-j6 colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF )

# --- Sim repo (patched: ego world default, optional headless Gazebo) ---
clone https://github.com/DongnanHu6556/ego-planner-ros2-sim.git ~/ego-planner-ros2-sim
apply_patches ~/ego-planner-ros2-sim ego-planner-ros2-sim
mkdir -p ~/PX4-Autopilot/launch ~/ros_proj/gazebo_start
cp ~/ego-planner-ros2-sim/px4_sitl_ros2.launch.py ~/PX4-Autopilot/launch/
cp ~/ego-planner-ros2-sim/simulation-gazebo ~/ego-planner-ros2-sim/depth_gz_bridge.py ~/ros_proj/gazebo_start/
chmod +x ~/ros_proj/gazebo_start/simulation-gazebo ~/ros_proj/gazebo_start/depth_gz_bridge.py

# Download gazebo models/worlds without launching the GUI, then add ego world
( cd ~/ros_proj/gazebo_start && python3 simulation-gazebo --world default --dryrun )
mkdir -p ~/.simulation-gazebo/worlds
cp ~/ego-planner-ros2-sim/ego.sdf ~/.simulation-gazebo/worlds/

# --- PX4 SITL binary (needed by the launch file) ---
if [ ! -x ~/PX4-Autopilot/build/px4_sitl_default/bin/px4 ]; then
  ( cd ~/PX4-Autopilot && make px4_sitl_default )
fi

# --- EGO planner (patched: 40 m map, ROS 2 goal-callback crash fix, ignore stale px4_msgs) ---
source ~/ros2_ws/install/setup.bash
mkdir -p ~/ego_ws/src
clone https://github.com/DongnanHu6556/ego-swarm-ros2.git ~/ego_ws/src/ego-swarm-ros2
apply_patches ~/ego_ws/src/ego-swarm-ros2 ego-swarm-ros2
( cd ~/ego_ws && colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release )

# --- Offboard bridge (patched: vehicle_status_v4) ---
mkdir -p ~/px4_ego_ws/src
clone https://github.com/DongnanHu6556/px4_ego.git ~/px4_ego_ws/src/px4_ego
apply_patches ~/px4_ego_ws/src/px4_ego px4_ego
source ~/ego_ws/install/setup.bash
( cd ~/px4_ego_ws && colcon build --symlink-install )

echo "=== Part 2 done. Verify with: bash $HERE/e2e_test.sh 4.0 2.0 ==="
