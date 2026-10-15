#!/usr/bin/env bash
# Tests the hardware launch (R2) in the warehouse sim, before it goes on the drone.
# Gazebo and PX4 SITL stand in for the drone and fake_zed.py republishes the sim camera
# under the ZED topic names. Everything else (MAVROS, XRCE agent, EGO, bridge, explorer,
# camera mount, vision relay) starts from hardware.launch.py exactly as on the drone.
# Pass = hw/bench_check.sh passes and the frontier flight passes (see frontier_test.sh).
# Usage: bash sim/hw_profile_test.sh [steps]     (logs in ~/.ego_sim/hw_profile_logs)
HW_PROFILE=1 exec bash "$(dirname "$0")/frontier_test.sh" "$@"
