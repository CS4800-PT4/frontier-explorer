#!/usr/bin/env bash
# Part 2 on the Jetson (no sudo): clone, patch and build everything the drone runs.
# Run after: sudo bash hw/1_jetson_sudo.sh. Safe to re-run.
# Builds: px4_msgs (release/1.15), Micro XRCE-DDS agent, EGO planner, the px4_ego bridge and
# this repo. Then hw/zed_setup.sh installs the ZED SDK if it's missing (Jetson only) and builds
# the wrapper release that matches it. MAVROS comes from apt (hw/1). No Gazebo or PX4 SITL.
#   PX4_MSGS_BRANCH   px4_msgs branch matching the flight controller (default release/1.15)
#   ZED_*             ZED SDK and wrapper settings, see hw/zed_setup.sh
set -eo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
PATCHES=$REPO/sim/patches
PX4_MSGS_BRANCH=${PX4_MSGS_BRANCH:-release/1.15}
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
  # v2.4.2 builds Fast-DDS from the 2.12.x branch, which eProsima has since deleted. Use its last tag.
  sed -i 's/set(_fastdds_tag 2\.12\.x)/set(_fastdds_tag v2.12.2)/' ~/Micro-XRCE-DDS-Agent/CMakeLists.txt
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

# --- ZED SDK + wrapper, matched by version (last, so a ZED problem doesn't block the rest) ---
zed_rc=0
bash "$HERE/zed_setup.sh" || zed_rc=$?
case $zed_rc in
  0) ZED_OK=yes ;;
  3) ZED_OK="no, no ZED SDK" ;;
  *) ZED_OK="no, it failed (see above)" ;;
esac

cat <<EOF
=== Part 2 done (ZED wrapper built: $ZED_OK) ===
Add to ~/.bashrc:
  source /opt/ros/humble/setup.bash
  source ~/ros2_ws/install/setup.bash
  source ~/ego_ws/install/setup.bash
  source ~/px4_ego_ws/install/setup.bash
  source ~/zed_ws/install/setup.bash
  source $REPO/install/setup.bash
(or the block in hw/README.md section 1, which also sets ROS_DOMAIN_ID)
Next: hw/README.md sections 2 and 3, then the demo (4) or the bench check (5).
EOF
# A ZED build that failed should fail the script; no SDK (a VM, or CI) is fine
if [ "$zed_rc" != 0 ] && [ "$zed_rc" != 3 ]; then exit 1; fi
