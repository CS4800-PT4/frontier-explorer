# frontier-explorer
Frontier-based autonomous exploration planner for a UAV (CS 4800 Project #4)

## Simulation setup

To run the simulated drone (PX4 + Gazebo + EGO-Planner) in WSL, follow [sim/README.md](sim/README.md).

## Frontier explorer

The ROS package is in [src/frontier_explorer](src/frontier_explorer/README.md). To see it run in the sim: `bash sim/frontier_demo.sh` (details in [sim/README.md](sim/README.md), Step 7).

## Hardware

The drone (Jetson Orin Nano, ZED, PX4 1.15) runs the same package from one launch file: [hw/README.md](hw/README.md). How the sim and drone stacks connect: [docs/STACK.md](docs/STACK.md). Test the drone launch in the sim first: `bash sim/hw_profile_test.sh`.

## Submodules

The repositories under `external/` are managed as Git submodules. See [docs/SUBMODULE_WORKFLOW.md](docs/SUBMODULE_WORKFLOW.md) for how to update a submodule and then record its new commit in `frontier-explorer`.
