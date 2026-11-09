#!/bin/bash
# Rebuild everything (VM paths were /home/sevren -> wipe old build/install/log)
source /opt/ros/humble/setup.bash
LOG=~/rebuild-results.txt; : > $LOG
r(){ echo "== $1: $2" | tee -a $LOG; }
J=$(nproc)
# Micro XRCE-DDS Agent
cd ~/Micro-XRCE-DDS-Agent && rm -rf build && mkdir build && cd build && cmake .. && make -j$J && sudo make install && sudo ldconfig && r XRCE OK || r XRCE FAIL
# PX4 SITL
cd ~/PX4-Autopilot && rm -rf build/px4_sitl_default && make px4_sitl_default -j$J && r PX4 OK || r PX4 FAIL
# colcon workspaces
for ws in ego_ws ros2_ws px4_ego frontier-explorer; do
  cd ~/$ws || continue
  rm -rf build install log
  rosdep install --from-paths src --ignore-src -r -y || true
  colcon build --symlink-install --parallel-workers $J && r $ws OK || r $ws FAIL
done
echo; cat $LOG
