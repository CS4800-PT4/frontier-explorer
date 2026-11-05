#!/usr/bin/env bash
# Build drone stack on the Jetson (sim-sev/jetson-runner). No apt sudo.
# Run after: sudo bash 01_sudo_install.sh
set -eo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SIM_SEV=$(cd "$HERE/.." && pwd)
REPO=$(cd "$SIM_SEV/.." && pwd)
PATCHES=$REPO/sim/patches
SEV_PATCHES=$REPO/sim-sev/patches
PX4_MSGS_BRANCH=${PX4_MSGS_BRANCH:-release/1.15}
ZED_WRAPPER_REF=${ZED_WRAPPER_REF:-master}
export MAKEFLAGS=${MAKEFLAGS:--j4}
BUILD="colcon build --parallel-workers ${COLCON_WORKERS:-1}"
EGO_BASE=fd808477dc1a7447d3bfc91a86a31665be089161
PX4_EGO_BASE=77e9a5fc8df48d1d4156c72247d3de55d15f9ac5

[ -d /usr/local/zed ] || {
  echo "!!! ZED SDK missing (/usr/local/zed). Run: sudo bash $HERE/01_sudo_install.sh"
  exit 1
}
[ -x /usr/local/cuda/bin/nvcc ] || {
  echo "!!! No nvcc. Re-run sudo bash $HERE/01_sudo_install.sh (CUDA toolkit)"
  exit 1
}
[ -d "$PATCHES/ego-swarm-ros2" ] && [ -d "$PATCHES/px4_ego" ] || {
  echo "!!! Missing $PATCHES/{ego-swarm-ros2,px4_ego}. Clone the full frontier-explorer repo."
  exit 1
}

# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash

clone() { local dir=${!#}; [ -d "$dir/.git" ] || git clone "$@"; }

apply_patches() {
  local p subject
  cd "$1"
  [ -d .git/rebase-apply ] && git am --abort
  if git rev-parse --verify -q sim-fixes >/dev/null; then git checkout -q sim-fixes
  else git checkout -q -b sim-fixes "$3"
  fi
  for p in "${4:-$PATCHES}/$2"/*.patch; do
    [ -e "$p" ] || continue
    subject=$(sed -n 's/^Subject: \[PATCH[^]]*\] //p' "$p")
    git log --format=%s | grep -xF -- "$subject" >/dev/null && continue
    git -c user.name="${GIT_NAME:-jetson-runner}" -c user.email="${GIT_EMAIL:-jetson-runner@localhost}" am -q "$p" || {
      git am --abort
      echo "!!! $(basename "$p") did not apply in $1 (base $3)"
      exit 1
    }
  done
  cd - >/dev/null
}

echo "=== px4_msgs ($PX4_MSGS_BRANCH)"
mkdir -p ~/ros2_ws/src
clone --branch "$PX4_MSGS_BRANCH" https://github.com/PX4/px4_msgs.git ~/ros2_ws/src/px4_msgs
( cd ~/ros2_ws/src/px4_msgs && git fetch -q origin "$PX4_MSGS_BRANCH" && git checkout -q "$PX4_MSGS_BRANCH" )
( cd ~/ros2_ws && $BUILD --cmake-args -DCMAKE_BUILD_TYPE=Release )

echo "=== Micro XRCE-DDS Agent"
if ! command -v MicroXRCEAgent >/dev/null; then
  clone --branch v2.4.2 https://github.com/eProsima/Micro-XRCE-DDS-Agent.git ~/Micro-XRCE-DDS-Agent
  sed -i 's/set(_fastdds_tag 2.12.x)/set(_fastdds_tag v2.12.2)/' ~/Micro-XRCE-DDS-Agent/CMakeLists.txt
  ( cd ~/Micro-XRCE-DDS-Agent && mkdir -p build && cd build && cmake .. && make && sudo make install && sudo ldconfig /usr/local/lib/ )
fi

echo "=== EGO planner"
# shellcheck disable=SC1091
source ~/ros2_ws/install/setup.bash
mkdir -p ~/ego_ws/src
clone https://github.com/DongnanHu6556/ego-swarm-ros2.git ~/ego_ws/src/ego-swarm-ros2
apply_patches ~/ego_ws/src/ego-swarm-ros2 ego-swarm-ros2 $EGO_BASE
( cd ~/ego_ws && $BUILD --symlink-install --packages-up-to ego_planner quadrotor_msgs \
    --cmake-args -DCMAKE_BUILD_TYPE=Release )

echo "=== px4_ego bridge"
mkdir -p ~/px4_ego_ws/src
clone https://github.com/DongnanHu6556/px4_ego.git ~/px4_ego_ws/src/px4_ego
apply_patches ~/px4_ego_ws/src/px4_ego px4_ego $PX4_EGO_BASE
apply_patches ~/px4_ego_ws/src/px4_ego px4_ego $PX4_EGO_BASE "$SEV_PATCHES"  # sim-sev: 2 m takeoff
# shellcheck disable=SC1091
source ~/ego_ws/install/setup.bash
( cd ~/px4_ego_ws && $BUILD --symlink-install )

echo "=== frontier_explorer (this repo)"
( cd "$REPO" && $BUILD --symlink-install --packages-select frontier_explorer )

echo "=== zed-ros2-wrapper ($ZED_WRAPPER_REF)"
mkdir -p ~/zed_ws/src
clone --recursive https://github.com/stereolabs/zed-ros2-wrapper.git ~/zed_ws/src/zed-ros2-wrapper
( cd ~/zed_ws/src/zed-ros2-wrapper && git fetch -q --tags origin && git checkout -q "$ZED_WRAPPER_REF" \
    && git submodule update --init --recursive )
( cd ~/zed_ws && rosdep update && rosdep install --from-paths src --ignore-src -r -y \
    && $BUILD --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release )

cat <<MSG
=== 2_build done ===
Add to ~/.bashrc (or always use sim-sev/jetson-runner/03_env.sh):
  source $HERE/03_env.sh

Next:
  bash $HERE/04_run_stack.sh
  # other terminal: bash $SIM_SEV/jetson-runner/06_run_demo.sh
  # once: bash $HERE/05_capture_intrinsics.sh
MSG
