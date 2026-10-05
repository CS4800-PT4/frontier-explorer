#!/usr/bin/env bash
# Part 1 (needs sudo): system packages for the EGO-Planner + PX4 sim stack.
# Run once:  sudo bash sim/1_sudo_install.sh
set -euo pipefail

apt-get update
apt-get install -y \
  ros-humble-pcl-ros ros-humble-pcl-conversions ros-humble-cv-bridge \
  ros-humble-image-transport ros-humble-laser-geometry ros-humble-tf2-geometry-msgs \
  ros-humble-ros-gzharmonic \
  ros-humble-mavlink ros-humble-mavros-msgs geographiclib-tools libgeographic-dev \
  python3-rosdep python3-vcstool ros-humble-diagnostic-updater ros-humble-angles \
  ros-humble-eigen-stl-containers ros-humble-message-filters \
  libasio-dev ros-humble-ament-cmake-google-benchmark \
  libpcl-dev libarmadillo-dev libeigen3-dev libboost-all-dev \
  python3-opencv python3-numpy wget git

# MAVROS crashes on startup without the GeographicLib datasets.
if [ ! -d /usr/share/GeographicLib/geoids ]; then
  wget -qO /tmp/install_geographiclib_datasets.sh \
    https://raw.githubusercontent.com/mavlink/mavros/ros2/mavros/scripts/install_geographiclib_datasets.sh
  bash /tmp/install_geographiclib_datasets.sh
fi

echo "=== Part 1 done. Now run: bash sim/2_user_setup.sh ==="
