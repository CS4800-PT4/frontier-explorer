#!/usr/bin/env bash
# Part 1 on the Jetson (needs sudo): ROS 2 Humble and the system packages for the
# drone stack. JetPack 6 is Ubuntu 22.04, so this is the same as a normal Humble install.
# Run once:  sudo bash hw/1_jetson_sudo.sh
# The ZED SDK is separate: download the installer for your JetPack version from
# https://www.stereolabs.com/developers/release and run it before hw/2_jetson_setup.sh.
set -euo pipefail

. /etc/os-release
[ "$VERSION_ID" = 22.04 ] || { echo "Needs Ubuntu 22.04 (JetPack 6); this is $PRETTY_NAME"; exit 1; }

# ROS 2 apt repo, unless it is already set up (ros2.list, or ros2.sources from the
# ros2-apt-source package the current ROS docs use; adding both breaks apt-get update)
if ! grep -rqs "packages.ros.org/ros2" /etc/apt/sources.list /etc/apt/sources.list.d/; then
  apt-get update
  apt-get install -y curl gnupg lsb-release software-properties-common
  add-apt-repository -y universe
  curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $UBUNTU_CODENAME main" \
    > /etc/apt/sources.list.d/ros2.list
fi

apt-get update
apt-get install -y \
  ros-humble-ros-base ros-humble-rviz2 python3-colcon-common-extensions python3-rosdep \
  build-essential cmake git wget \
  ros-humble-pcl-ros ros-humble-pcl-conversions ros-humble-cv-bridge \
  ros-humble-image-transport ros-humble-laser-geometry ros-humble-tf2-geometry-msgs \
  ros-humble-mavros ros-humble-mavros-extras geographiclib-tools libgeographic-dev \
  python3-vcstool ros-humble-diagnostic-updater ros-humble-angles \
  ros-humble-eigen-stl-containers ros-humble-message-filters \
  libasio-dev ros-humble-ament-cmake-google-benchmark \
  libpcl-dev libarmadillo-dev libeigen3-dev libboost-all-dev \
  python3-opencv python3-numpy python3-yaml

[ -d /etc/ros/rosdep/sources.list.d ] || rosdep init

# MAVROS crashes on startup without the GeographicLib datasets (the apt package ships the script)
if [ ! -d /usr/share/GeographicLib/geoids ]; then
  bash /opt/ros/humble/lib/mavros/install_geographiclib_datasets.sh
fi

# The ZED wrapper builds against CUDA. A Jetson flashed without the JetPack SDK
# components has the CUDA runtime but not the toolkit (nvcc).
if [ -f /etc/nv_tegra_release ] && [ ! -x /usr/local/cuda/bin/nvcc ]; then
  apt-get install -y nvidia-jetpack-dev
fi

# Serial ports for the flight controller (MAVROS on USB, XRCE agent on the UART)
U=${SUDO_USER:-}
if [ -n "$U" ]; then usermod -aG dialout "$U"; echo "Added $U to dialout (log out and back in)"; fi

echo "=== Part 1 done. Install the ZED SDK, then run (no sudo): bash hw/2_jetson_setup.sh ==="
