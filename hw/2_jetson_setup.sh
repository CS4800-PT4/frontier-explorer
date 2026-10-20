#!/usr/bin/env bash
# Part 2 on the Jetson (no sudo): clone, patch and build everything the drone runs.
# Run after: sudo bash hw/1_jetson_sudo.sh, and the ZED SDK installer. Safe to re-run.
# Builds: px4_msgs (release/1.15), Micro XRCE-DDS agent, EGO planner, the px4_ego bridge,
# this repo and the ZED wrapper. MAVROS comes from apt (hw/1). No Gazebo or PX4 SITL.
#   PX4_MSGS_BRANCH   px4_msgs branch matching the flight controller (default release/1.15)
#   ZED_WRAPPER_REF   zed-ros2-wrapper tag/branch to build (default master; pin it to the
#                     release that matches your ZED SDK version, see the wrapper's releases)
set -eo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
PATCHES=$REPO/sim/patches
PX4_MSGS_BRANCH=${PX4_MSGS_BRANCH:-release/1.15}
ZED_WRAPPER_REF=${ZED_WRAPPER_REF:-master}
# The Orin Nano has 8 GB shared with the GPU. MAKEFLAGS limits compilers per package and
# --parallel-workers limits packages at once, so at most 4 compilers run together.
export MAKEFLAGS=${MAKEFLAGS:--j4}
BUILD="colcon build --parallel-workers ${COLCON_WORKERS:-1}"
# Upstream commits our patches were made on, so a new upstream commit can't break them
EGO_BASE=fd808477dc1a7447d3bfc91a86a31665be089161
PX4_EGO_BASE=77e9a5fc8df48d1d4156c72247d3de55d15f9ac5
source /opt/ros/humble/setup.bash

clone() { local dir=${!#}; [ -d "$dir/.git" ] || git clone "$@"; }   # last arg = target dir

# Same as sim/2_user_setup.sh: put a repo on branch 'sim-fixes' (from the pinned upstream
# commit) and apply our patches
apply_patches() {  # repo_dir patch_subdir base_commit
  local p subject
  cd "$1"
  # a patch that failed on an earlier run leaves git am half done
  [ -d .git/rebase-apply ] && git am --abort
  if git rev-parse --verify -q sim-fixes >/dev/null; then git checkout -q sim-fixes
  else git checkout -q -b sim-fixes "$3"
  fi
  for p in "$PATCHES/$2"/*.patch; do
    subject=$(sed -n 's/^Subject: \[PATCH[^]]*\] //p' "$p")
    git log --format=%s | grep -xF -- "$subject" >/dev/null && continue
    git -c user.name="${GIT_NAME:-hw-setup}" -c user.email="${GIT_EMAIL:-hw-setup@localhost}" am -q "$p" || {
      git am --abort
      echo "!!! $(basename "$p") did not apply in $1. Is sim-fixes based on $3?"
      exit 1
    }
  done
  cd - >/dev/null
}

# --- px4_msgs must match the firmware exactly, or topics show up with no usable data ---
mkdir -p ~/ros2_ws/src
clone --branch "$PX4_MSGS_BRANCH" https://github.com/PX4/px4_msgs.git ~/ros2_ws/src/px4_msgs
( cd ~/ros2_ws/src/px4_msgs && git fetch -q origin "$PX4_MSGS_BRANCH" && git checkout -q "$PX4_MSGS_BRANCH" )
( cd ~/ros2_ws && $BUILD --cmake-args -DCMAKE_BUILD_TYPE=Release )

# --- Micro XRCE-DDS agent (v2.4.2 is the version the PX4 1.15 ROS 2 guide uses) ---
if ! command -v MicroXRCEAgent >/dev/null; then
  clone --branch v2.4.2 https://github.com/eProsima/Micro-XRCE-DDS-Agent.git ~/Micro-XRCE-DDS-Agent
  ( cd ~/Micro-XRCE-DDS-Agent && mkdir -p build && cd build && cmake .. && make && sudo make install && sudo ldconfig /usr/local/lib/ )
fi

# --- EGO planner with our patches; only the planner, not its simulator packages ---
source ~/ros2_ws/install/setup.bash
mkdir -p ~/ego_ws/src
clone https://github.com/DongnanHu6556/ego-swarm-ros2.git ~/ego_ws/src/ego-swarm-ros2
apply_patches ~/ego_ws/src/ego-swarm-ros2 ego-swarm-ros2 $EGO_BASE
( cd ~/ego_ws && $BUILD --symlink-install --packages-up-to ego_planner quadrotor_msgs \
    --cmake-args -DCMAKE_BUILD_TYPE=Release )

# --- Offboard bridge with our patches (vehicle_status_v4, PX4 1.15 local position) ---
mkdir -p ~/px4_ego_ws/src
clone https://github.com/DongnanHu6556/px4_ego.git ~/px4_ego_ws/src/px4_ego
apply_patches ~/px4_ego_ws/src/px4_ego px4_ego $PX4_EGO_BASE
source ~/ego_ws/install/setup.bash
( cd ~/px4_ego_ws && $BUILD --symlink-install )

# --- This repo (before the ZED wrapper, so a wrapper problem doesn't block it) ---
( cd "$REPO" && $BUILD --symlink-install --packages-select frontier_explorer )

# --- ZED wrapper (needs the ZED SDK, which needs the Jetson's CUDA) ---
if [ -d /usr/local/zed ] && [ ! -x /usr/local/cuda/bin/nvcc ]; then
  echo "!!! No CUDA toolkit (/usr/local/cuda/bin/nvcc): run sudo bash hw/1_jetson_sudo.sh again"
  ZED_OK=no
elif [ -d /usr/local/zed ]; then
  mkdir -p ~/zed_ws/src
  clone --recursive https://github.com/stereolabs/zed-ros2-wrapper.git ~/zed_ws/src/zed-ros2-wrapper
  ( cd ~/zed_ws/src/zed-ros2-wrapper && git fetch -q --tags origin && git checkout -q "$ZED_WRAPPER_REF" \
      && git submodule update --init --recursive )
  ( cd ~/zed_ws && rosdep update && rosdep install --from-paths src --ignore-src -r -y \
      && $BUILD --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release )
  ZED_OK=yes
else
  echo "!!! ZED SDK not found in /usr/local/zed: install it, then run this script again"
  ZED_OK=no
fi

cat <<EOF
=== Part 2 done (ZED wrapper built: $ZED_OK) ===
Add to ~/.bashrc:
  source /opt/ros/humble/setup.bash
  source ~/ros2_ws/install/setup.bash
  source ~/ego_ws/install/setup.bash
  source ~/px4_ego_ws/install/setup.bash
  source ~/zed_ws/install/setup.bash
  source $REPO/install/setup.bash
Next: hw/README.md, "Bring-up".
EOF
