#!/usr/bin/env bash
# Setup for the stationary test (hw/stationary_test.sh) on a Jetson that is already set up
# and used by someone else. It only adds things and never changes what is there:
#   - EGO (with our patches) and frontier_explorer build in their own folders, with only ROS 2
#     sourced, so they don't link against anyone else's workspaces.
#   - It uses the ZED wrapper already built on the Jetson. Only if there is none, it builds
#     its own copy in $FE_WS/zed_ws.
#   - apt: it only installs packages that are missing, asks first, and stops if that would
#     upgrade or remove anything already installed. What it added goes in $FE_WS/apt_added.txt.
#   - Anything already done is skipped, so it is safe to re-run.
# Everything goes in $FE_WS (default ~/fe_ws), except this repo's own build/ and install/.
# Nothing is added to ~/.bashrc: source $FE_WS/env.sh in each terminal instead.
# Not installed (not needed for this test): MAVROS, the XRCE agent, px4_msgs, the bridge.
# Usage: bash hw/stationary_setup.sh
#   FE_WS=~/fe_ws          where everything goes
#   ZED_WS=<workspace>     use this ZED wrapper workspace instead of searching for one
#   ZED_WRAPPER_REF=<tag>  wrapper version if it has to build its own (default master)
#   YES=1                  install missing apt packages without asking
#   NO_RVIZ=1              don't install RViz if it is missing (no screen on the Jetson)
#   SKIP_ZED=1             no ZED at all (the sim test of these scripts sets it)
set -eo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
FE_WS=${FE_WS:-$HOME/fe_ws}
EGO_URL=${EGO_URL:-https://github.com/DongnanHu6556/ego-swarm-ros2.git}
EGO_BASE=fd808477dc1a7447d3bfc91a86a31665be089161   # same pin as hw/2_jetson_setup.sh
ZED_WRAPPER_REF=${ZED_WRAPPER_REF:-master}
mkdir -p "$FE_WS"

say() { echo "[setup] $*"; }
die() { echo "[setup] !!! $*"; exit 1; }

# Runs a command with only ROS 2 sourced. Workspaces sourced in ~/.bashrc would otherwise
# become part of our builds (and our builds would break if those ever change).
clean() {
  env -i HOME="$HOME" USER="${USER:-$(id -un)}" TERM="${TERM:-xterm}" \
    PATH=/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    MAKEFLAGS="${MAKEFLAGS:--j4}" \
    bash -c "source /opt/ros/humble/setup.bash && $1"
}

installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

# Installs only the missing packages, and only if apt just adds packages. If it would upgrade
# or remove anything already installed, it stops instead.
add_apt() {  # what_for package...
  local why=$1 p a plan missing=()
  shift
  for p in "$@"; do installed "$p" || missing+=("$p"); done
  if [ ${#missing[@]} -eq 0 ]; then say "$why: all apt packages already installed"; return; fi
  say "$why: missing apt packages: ${missing[*]}"
  if [ "${YES:-0}" != 1 ]; then
    read -r -p "[setup] install them with sudo apt-get? Nothing already installed gets changed. [y/N] " a
    [[ $a =~ ^[yY] ]] || die "stopped. Install them yourself or re-run with YES=1."
  fi
  sudo apt-get update -qq || die "apt-get update failed"
  plan=$(apt-get install -s --no-upgrade --no-install-recommends "${missing[@]}" 2>&1) || {
    echo "$plan" | tail -5
    die "apt can't install these. Is the ROS 2 apt source set up?"
  }
  # A new package shows as "Inst name (ver ...)", an upgrade as "Inst name [oldver] (ver ...)"
  if echo "$plan" | grep -qE '^(Inst [^ ]+ \[|Remv )'; then
    echo "$plan" | grep -E '^(Inst [^ ]+ \[|Remv )'
    die "installing ${missing[*]} would upgrade or remove the packages above, so nothing was installed. Ask the Jetson's owner."
  fi
  sudo apt-get install -y --no-upgrade --no-install-recommends "${missing[@]}"
  echo "$plan" | awk '/^Inst /{print $2}' >> "$FE_WS/apt_added.txt"
}

# Same as hw/2_jetson_setup.sh: branch 'sim-fixes' from the pinned commit, plus our patches
apply_patches() {  # repo_dir patch_dir base_commit
  local p subject
  cd "$1"
  [ -d .git/rebase-apply ] && git am --abort
  if git rev-parse --verify -q sim-fixes >/dev/null; then git checkout -q sim-fixes
  else git checkout -q -b sim-fixes "$3"
  fi
  for p in "$2"/*.patch; do
    subject=$(sed -n 's/^Subject: \[PATCH[^]]*\] //p' "$p")
    git log --format=%s | grep -xF -- "$subject" >/dev/null && continue
    git -c user.name=hw-setup -c user.email=hw-setup@localhost am -q "$p" || {
      git am --abort
      die "$(basename "$p") did not apply in $1. Is sim-fixes based on $3?"
    }
  done
  cd - >/dev/null
}

# A ZED wrapper workspace that is already built: ZED_WS, else the first one found that isn't
# ours, else ours from an earlier run. "system" means it is installed in /opt/ros/humble.
find_zed_ws() {
  local d
  if [ -n "${ZED_WS:-}" ]; then echo "${ZED_WS%/}"; return; fi
  if [ -d /opt/ros/humble/share/zed_wrapper ]; then echo system; return; fi
  d=$(find "$HOME" /opt /usr/local -maxdepth 5 -type d \
        \( -path '*/install/zed_wrapper' -o -path '*/install/share/zed_wrapper' \) 2>/dev/null \
      | grep -v "^$FE_WS/" | head -1) || true
  if [ -n "$d" ]; then echo "${d%%/install/*}"; return; fi
  if [ -d "$FE_WS/zed_ws/install/zed_wrapper" ]; then echo "$FE_WS/zed_ws"; fi
}

# --- checks ---
. /etc/os-release
[ "$VERSION_ID" = 22.04 ] || die "needs Ubuntu 22.04 (JetPack 6); this is $PRETTY_NAME"
[ -f /opt/ros/humble/setup.bash ] || die "ROS 2 Humble isn't installed. That changes the whole \
machine, so ask the Jetson's owner first (hw/1_jetson_sudo.sh installs it)."
say "ROS 2 Humble: found"
if [ "${SKIP_ZED:-0}" = 1 ]; then
  say "SKIP_ZED=1: no ZED"
elif [ -d /usr/local/zed ]; then
  v=$(grep -rhoE 'define ZED_SDK_(MAJOR|MINOR|PATCH)_VERSION +[0-9]+' /usr/local/zed/include 2>/dev/null \
      | awk '{print $NF}' | head -3 | paste -sd.) || true
  say "ZED SDK: ${v:-found} (/usr/local/zed)"
else
  die "no ZED SDK in /usr/local/zed"
fi

# --- apt packages (only what is missing) ---
add_apt "build tools" git cmake build-essential python3-colcon-common-extensions
add_apt "EGO" ros-humble-cv-bridge ros-humble-pcl-conversions ros-humble-message-filters \
  libpcl-dev libeigen3-dev libopencv-dev libboost-all-dev
add_apt "frontier_explorer" ros-humble-tf2-ros ros-humble-launch-ros ros-humble-std-srvs \
  ros-humble-nav-msgs ros-humble-visualization-msgs python3-numpy python3-yaml
if [ "${NO_RVIZ:-0}" != 1 ]; then add_apt "RViz" ros-humble-rviz2; fi

# --- ZED wrapper: use the one on the Jetson if there is one ---
ZWS=""
if [ "${SKIP_ZED:-0}" != 1 ]; then
  ZWS=$(find_zed_ws) || true
  if [ -n "$ZWS" ] && [ "$ZWS" != system ] && [ "$ZWS" != "$FE_WS/zed_ws" ]; then
    [ -f "$ZWS/install/setup.bash" ] || die "ZED_WS=$ZWS has no install/setup.bash"
    clean "source '$ZWS/install/setup.bash' && ros2 pkg prefix zed_wrapper >/dev/null" \
      || die "zed_wrapper is in $ZWS but doesn't load. Pass ZED_WS= for another one."
    say "ZED wrapper: using the existing one in $ZWS (not changing it)"
  elif [ "$ZWS" = system ]; then
    say "ZED wrapper: using the one in /opt/ros/humble"
  else
    say "ZED wrapper: none found, building our own in $FE_WS/zed_ws ($ZED_WRAPPER_REF)"
    [ -x /usr/local/cuda/bin/nvcc ] || die "no CUDA toolkit (/usr/local/cuda/bin/nvcc) to build \
the wrapper. Installing it (nvidia-jetpack-dev) is several GB, so ask first. Or point ZED_WS= at \
an existing wrapper build."
    [ -d /etc/ros/rosdep/sources.list.d ] || die "rosdep isn't set up (needs: sudo rosdep init)"
    mkdir -p "$FE_WS/zed_ws/src"
    [ -d "$FE_WS/zed_ws/src/zed-ros2-wrapper/.git" ] || \
      git clone --recursive https://github.com/stereolabs/zed-ros2-wrapper.git "$FE_WS/zed_ws/src/zed-ros2-wrapper"
    ( cd "$FE_WS/zed_ws/src/zed-ros2-wrapper" && git fetch -q --tags origin \
      && git checkout -q "$ZED_WRAPPER_REF" && git submodule update --init --recursive )
    clean "rosdep update >/dev/null"
    # shellcheck disable=SC2046
    add_apt "ZED wrapper" $(clean "cd '$FE_WS/zed_ws' && rosdep install --from-paths src \
      --ignore-src -r -s -y 2>/dev/null" | grep -oE 'apt-get install -y [^ ]+' | awk '{print $NF}')
    clean "cd '$FE_WS/zed_ws' && colcon build --symlink-install --parallel-workers 1 \
      --cmake-args -DCMAKE_BUILD_TYPE=Release" \
      || die "ZED wrapper build failed. If the ZED SDK is older than the wrapper wants, re-run \
with ZED_WRAPPER_REF=<tag> from https://github.com/stereolabs/zed-ros2-wrapper/releases"
    ZWS=$FE_WS/zed_ws
  fi
fi

# --- EGO with our patches, in $FE_WS/ego_ws ---
mkdir -p "$FE_WS/ego_ws/src"
[ -d "$FE_WS/ego_ws/src/ego-swarm-ros2/.git" ] || git clone "$EGO_URL" "$FE_WS/ego_ws/src/ego-swarm-ros2"
apply_patches "$FE_WS/ego_ws/src/ego-swarm-ros2" "$REPO/sim/patches/ego-swarm-ros2" "$EGO_BASE"
say "building EGO (one package at a time, so the Orin Nano doesn't run out of memory)"
clean "cd '$FE_WS/ego_ws' && colcon build --symlink-install --parallel-workers ${COLCON_WORKERS:-1} \
  --packages-up-to ego_planner quadrotor_msgs --cmake-args -DCMAKE_BUILD_TYPE=Release"

# --- this repo ---
say "building frontier_explorer"
clean "cd '$REPO' && colcon build --symlink-install --packages-select frontier_explorer"

# --- env.sh: what to source in each terminal ---
{
  echo "# Written by hw/stationary_setup.sh. Source it in each terminal: source $FE_WS/env.sh"
  echo "source /opt/ros/humble/setup.bash"
  if [ -n "$ZWS" ] && [ "$ZWS" != system ]; then echo "source $ZWS/install/setup.bash"; fi
  echo "source $FE_WS/ego_ws/install/local_setup.bash"
  echo "source $REPO/install/local_setup.bash"
  echo "export FE_WS=$FE_WS FE_REPO=$REPO"
} > "$FE_WS/env.sh"

# --- check that the packages load, and from where ---
say "packages the test will use:"
pkgs="ego_planner frontier_explorer"
[ "${SKIP_ZED:-0}" = 1 ] || pkgs="zed_wrapper $pkgs"
for p in $pkgs; do
  where=$(clean "source '$FE_WS/env.sh' && ros2 pkg prefix $p" 2>/dev/null) || die "$p doesn't load"
  echo "    $p: $where"
done
cat <<EOF
=== Stationary setup done ===
Everything is in $FE_WS (remove it to undo). apt packages added: \
$( [ -s "$FE_WS/apt_added.txt" ] && wc -l < "$FE_WS/apt_added.txt" || echo 0 )$( [ -s "$FE_WS/apt_added.txt" ] && echo " (listed in $FE_WS/apt_added.txt)")
Next: bash hw/stationary_test.sh <camera_model>    (zed, zedm, zed2 or zed2i)
EOF
