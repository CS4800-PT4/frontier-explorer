#!/bin/bash
# ROS 2 Humble + Gazebo Harmonic + PX4 deps for class (Ubuntu 22.04, stock kernel)
set -e
L=/media/sev/SevBackup/reinstall-lists/vm/ros-related-packages.txt
echo "==> locale + base"
sudo apt-get update
sudo apt-get install -y locales software-properties-common curl gnupg lsb-release wget
sudo locale-gen en_US en_US.UTF-8; sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
sudo add-apt-repository -y universe
echo "==> ROS 2 apt source"
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu jammy main" | sudo tee /etc/apt/sources.list.d/ros2.list >/dev/null
echo "==> Gazebo (OSRF) apt source"
sudo curl -sSL https://packages.osrfoundation.org/gazebo.gpg -o /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable jammy main" | sudo tee /etc/apt/sources.list.d/gazebo-stable.list >/dev/null
sudo apt-get update
echo "==> ROS Humble desktop + tools + project deps"
sudo apt-get install -y ros-humble-desktop ros-dev-tools python3-colcon-common-extensions python3-rosdep \
  gz-harmonic ros-humble-ros-gzharmonic \
  ros-humble-mavros ros-humble-mavros-msgs ros-humble-mavros-extras \
  ros-humble-cv-bridge ros-humble-pcl-ros ros-humble-pcl-conversions ros-humble-pcl-msgs \
  libeigen3-dev libpcl-dev libopencv-dev libarmadillo-dev
echo "==> MAVROS geographiclib datasets"
sudo /opt/ros/humble/lib/mavros/install_geographiclib_datasets.sh || echo "WARN geographiclib failed"
if [ -f "$L" ]; then
  echo "==> Packages from VM list (Seagate)"
  avail=$(xargs -a "$L" apt-cache policy 2>/dev/null | awk '/^[^ ].*:$/{p=$1} /Candidate:/{if($2!="(none)")print p}' | tr -d ':')
  sudo apt-get install -y $avail || echo "WARN some VM-list packages failed"
fi
echo "==> PX4 deps (no NuttX toolchain, no sim reinstall)"
bash ~/PX4-Autopilot/Tools/setup/ubuntu.sh --no-nuttx --no-sim-tools || echo "WARN PX4 ubuntu.sh had errors"
echo "==> rosdep"
[ -f /etc/ros/rosdep/sources.list.d/20-default.list ] || sudo rosdep init
rosdep update
echo "INSTALL DONE. Next: bash ~/rebuild-px4-ros-workspaces.sh"
