#!/usr/bin/env bash
# Jetson sudo install (sim-sev/jetson-runner only): ROS 2 Humble, MAVROS, deps, ZED SDK.
# Usage: sudo bash sim-sev/jetson-runner/01_sudo_install.sh
set -euo pipefail

. /etc/os-release
[ "${VERSION_ID:-}" = "22.04" ] || {
  echo "Needs Ubuntu 22.04 (JetPack 6); this is ${PRETTY_NAME:-unknown}"
  exit 1
}

if [ ! -f /etc/nv_tegra_release ]; then
  echo "!!! Not a Jetson (/etc/nv_tegra_release missing). Aborting."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# --- ROS 2 apt repo ---
if ! grep -rqs "packages.ros.org/ros2" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
  apt-get update
  apt-get install -y curl gnupg lsb-release software-properties-common
  add-apt-repository -y universe
  curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu ${UBUNTU_CODENAME} main" \
    > /etc/apt/sources.list.d/ros2.list
fi

apt-get update
apt-get install -y \
  ros-humble-ros-base ros-humble-rviz2 python3-colcon-common-extensions python3-rosdep \
  build-essential cmake git wget curl zstd \
  ros-humble-pcl-ros ros-humble-pcl-conversions ros-humble-cv-bridge \
  ros-humble-image-transport ros-humble-laser-geometry ros-humble-tf2-geometry-msgs \
  ros-humble-mavros ros-humble-mavros-extras geographiclib-tools libgeographic-dev \
  python3-vcstool ros-humble-diagnostic-updater ros-humble-angles \
  ros-humble-eigen-stl-containers ros-humble-message-filters \
  libasio-dev ros-humble-ament-cmake-google-benchmark \
  libpcl-dev libarmadillo-dev libeigen3-dev libboost-all-dev \
  python3-opencv python3-numpy python3-yaml

[ -d /etc/ros/rosdep/sources.list.d ] || rosdep init || true

if [ ! -d /usr/share/GeographicLib/geoids ]; then
  bash /opt/ros/humble/lib/mavros/install_geographiclib_datasets.sh
fi

# CUDA toolkit headers (ZED wrapper needs nvcc)
if [ ! -x /usr/local/cuda/bin/nvcc ]; then
  apt-get install -y nvidia-jetpack-dev || apt-get install -y nvidia-jetpack || apt-get install -y cuda-toolkit-12-6 || apt-get install -y nvidia-cuda-dev || true
fi

# --- ZED SDK for this L4T ---
install_zed_sdk() {
  if [ "${SKIP_ZED_SDK:-}" = "1" ] && [ -d /usr/local/zed ]; then
    echo "SKIP_ZED_SDK=1 and /usr/local/zed exists — leaving SDK as-is"
    return 0
  fi

  local line rev major minor l4t ver url tmp
  line=$(head -n1 /etc/nv_tegra_release)
  # Example: # R36 (release), REVISION: 4.3, ...
  major=$(echo "$line" | sed -n 's/.*R\([0-9][0-9]*\).*/\1/p')
  rev=$(echo "$line" | sed -n 's/.*REVISION: \([0-9][0-9]*\)\..*/\1/p')
  if [ -z "$major" ] || [ -z "$rev" ]; then
    echo "!!! Could not parse L4T from: $line"
    echo "    Set ZED_SDK_URL to a direct Stereolabs .run link and re-run."
    exit 1
  fi
  l4t="l4t${major}.${rev}"
  ver="${ZED_SDK_VERSION:-5.5}"
  url="${ZED_SDK_URL:-https://download.stereolabs.com/zedsdk/${ver}/${l4t}/jetsons}"

  echo "=== ZED SDK: L4T ${major}.${rev} → ${url}"
  tmp=$(mktemp -d /tmp/zed-sdk-XXXXXX)
  trap 'rm -rf "$tmp"' RETURN
  if ! curl -fL --retry 3 --retry-delay 2 -o "$tmp/ZED_SDK_Linux.run" "$url"; then
    echo "!!! Download failed for ${url}"
    echo "    Check JetPack / L4T on https://www.stereolabs.com/developers/release"
    echo "    Or set ZED_SDK_URL=https://download.stereolabs.com/zedsdk/<ver>/${l4t}/jetsons"
    exit 1
  fi
  chmod +x "$tmp/ZED_SDK_Linux.run"
  # silent install; skip heavy OD/python extras for a lean Jetson bring-up
  "$tmp/ZED_SDK_Linux.run" -- silent skip_od_module skip_python
  [ -d /usr/local/zed ] || {
    echo "!!! ZED SDK install finished but /usr/local/zed is missing"
    exit 1
  }
  echo "=== ZED SDK installed under /usr/local/zed"
}

install_zed_sdk

U=${SUDO_USER:-}
if [ -n "$U" ]; then
  usermod -aG dialout "$U" || true
  echo "Added $U to dialout (log out and back in for serial ports)"
fi

echo "=== 1_sudo_install done. Next (no sudo): bash 02_build.sh   (or re-run 00_bootstrap.sh)"
