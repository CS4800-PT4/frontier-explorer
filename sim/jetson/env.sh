#!/usr/bin/env bash
# Shared settings for running the Gazebo sim on the Jetson. Sourced by setup.sh and run.sh.
# The sim gets its own home folder (SIM_HOME), so its PX4, px4_msgs, EGO and MAVROS builds
# never touch the hardware build in the real home (~/ros2_ws has px4_msgs release/1.15 there,
# the sim needs the newer px4_msgs that matches its PX4).
REAL_HOME=${REAL_HOME:-$HOME}
SIM_HOME=${SIM_HOME:-$REAL_HOME/jetson-sim}
export REAL_HOME SIM_HOME
# GUI windows still need the real X login after HOME changes
export XAUTHORITY=${XAUTHORITY:-$REAL_HOME/.Xauthority}
export DISPLAY=${DISPLAY:-:0}
export ROS_LOCALHOST_ONLY=0
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
# The Orin Nano has 8 GB shared with the GPU: keep compiles small so the build isn't killed
export MAKEFLAGS=${MAKEFLAGS:--j2}
export HOME=$SIM_HOME
