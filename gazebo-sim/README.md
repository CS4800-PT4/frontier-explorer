# Gazebo Simulation

Location: `gazebo-sim/`

Scripts, launch files, worlds, and automated tests for running PX4 SITL + Gazebo Harmonic + EGO-Planner + `uav_frontier_exploration` on Ubuntu 22.04 (ROS 2 Humble) without physical drone hardware.

## Directory layout

```text
gazebo-sim/
├── README.md
├── setup/                             # One-time install, workspace build, and world staging
│   ├── 1_sudo_install.sh
│   ├── 2_user_setup.sh
│   └── warehouse_setup.sh
├── scripts/                           # Interactive demos and runtime control helpers
│   ├── demo.sh
│   ├── demo_stop.sh
│   ├── frontier_demo.sh
│   ├── frontier_go.sh
│   ├── kill_all.sh
│   ├── launch_all.sh
│   └── restart_planner.sh
├── tests/                             # Automated headless and smoke test runners
│   ├── smoke.sh
│   ├── e2e_test.sh
│   ├── warehouse_test.sh
│   ├── frontier_test.sh
│   └── hw_profile_test.sh
├── launch/                            # ROS 2 launch and helper Python nodes
│   ├── px4_sitl_ros2.launch.py
│   ├── fake_zed.py
│   └── offboard_control_test.py
└── worlds/                            # Gazebo SDF world definitions
    ├── default_warehouse.sdf
    └── ego.sdf
```

## Prerequisites

- Ubuntu 22.04 with ROS 2 Humble (`ros-humble-desktop`)
- Built `~/PX4-Autopilot` (`px4_sitl_default`), `~/ros2_ws` (`px4_msgs`), and Micro XRCE-DDS Agent

## Setup (`setup/`)

```bash
# 1. Install Gazebo Harmonic and simulation apt dependencies
sudo bash gazebo-sim/setup/1_sudo_install.sh

# 2. Clone, apply patches from ../uav-explorer/patches/, stage warehouse world, and build sim workspaces
bash gazebo-sim/setup/2_user_setup.sh
```

## Contents by subfolder

### `setup/`
- `1_sudo_install.sh` — Installs Gazebo Harmonic, `ros-humble-ros-gzharmonic`, and simulation apt packages.
- `2_user_setup.sh` — Clones and patches sim workspaces (`../uav-explorer/patches/`), builds EGO/MAVROS/`px4_ego`, and runs `warehouse_setup.sh`.
- `warehouse_setup.sh` — Downloads warehouse Gazebo Fuel models, adds mesh collisions, and copies `worlds/default_warehouse.sdf`.

### `scripts/`
- `frontier_demo.sh` — Launches GUI Gazebo + RViz in the warehouse with frontier exploration enabled (`FRONTIER=1`).
- `frontier_go.sh` — Calls `/frontier/go_best` and waits for arrival in a loop (`bash gazebo-sim/scripts/frontier_go.sh 5`).
- `demo.sh` — Base GUI Gazebo + RViz click-to-fly demo (`2D Goal Pose`), auto-takeoff, and offboard entry.
- `demo_stop.sh` — Cleanly stops the simulation and restores temporary PX4 parameters changed by `demo.sh`.
- `kill_all.sh` — Force-kills all Gazebo/PX4/ROS simulation processes if `demo_stop.sh` hangs.
- `restart_planner.sh` — Hot-restarts only EGO-Planner while Gazebo and PX4 stay running.
- `launch_all.sh` — Optional WSL/Windows Terminal tab launcher (WSL-only; not used on native Linux).

### `tests/`
- `frontier_test.sh` — Headless automated warehouse frontier exploration test (also the engine behind `hw_profile_test.sh`).
- `hw_profile_test.sh` — Dry-runs `../uav-explorer/hardware.launch.py` inside Gazebo using `launch/fake_zed.py` and `../uav-explorer/jetson-runner/bench_check.sh` (`SIM=1`).
- `smoke.sh` — 100-second check that PX4, Gazebo, and MAVROS topics come up.
- `e2e_test.sh` — Headless single-goal EGO-Planner flight test (`bash gazebo-sim/tests/e2e_test.sh [goal_x] [goal_y]`).
- `warehouse_test.sh` — Headless multi-waypoint warehouse obstacle-course test (EGO only).

### `launch/` and `worlds/`
- `launch/px4_sitl_ros2.launch.py` — PX4 SITL + Gazebo ROS 2 launch file.
- `launch/fake_zed.py` — Republishes Gazebo depth and odometry on ZED topic names for `tests/hw_profile_test.sh`.
- `launch/offboard_control_test.py` — Patched PX4 offboard takeoff bridge reference node.
- `worlds/default_warehouse.sdf` — Warehouse Gazebo world.
- `worlds/ego.sdf` — Compact EGO obstacle test world.

## MAVROS & Micro XRCE-DDS connection settings

Simulation uses local UDP links instead of physical USB/UART devices. `fcu_url` configures the MAVROS link (PX4 state out) and `xrce_args` configures `MicroXRCEAgent` (offboard setpoints in and `/fmu/out/...` status out).

| Parameter | Gazebo sim default | Real drone default | Where to edit |
|---|---|---|---|
| `fcu_url` (MAVROS) | `udp://:14540@127.0.0.1:14555` | `/dev/ttyACM0:57600` (USB) | Sim: `gazebo-sim/launch/px4_sitl_ros2.launch.py` (line 17) & `gazebo-sim/tests/frontier_test.sh` (line 74)<br>Drone: `uav-explorer/hardware.launch.py` (line 46) |
| `xrce_args` (XRCE agent) | `udp4 -p 8888` | `serial --dev /dev/ttyTHS1 -b 921600` (UART) | Sim: `gazebo-sim/launch/px4_sitl_ros2.launch.py` (line 24) & `gazebo-sim/tests/frontier_test.sh` (line 74)<br>Drone: `uav-explorer/hardware.launch.py` (lines 48–49) |
| `gcs_url` (optional QGC) | *(unused)* | `""` (disabled) | Drone: `uav-explorer/hardware.launch.py` (line 47) |

During `tests/hw_profile_test.sh`, `tests/frontier_test.sh` (line 74) passes the sim UDP values as CLI overrides into `../uav-explorer/hardware.launch.py`. On the physical Jetson, `uav-explorer/jetson-runner/04_run_stack.sh` forwards extra CLI arguments the same way (e.g., `fcu_url:=/dev/ttyUSB0:921600`).

## Useful environment overrides

- `GZ_WORLD=default_warehouse` (or `default` for the smaller EGO world)
- `GZ_HEADLESS=1` (run Gazebo without GUI)
- `EGO_INFLATION`, `EGO_GROUND`, `EGO_CEIL` (obstacle padding and vertical flight band; warehouse scripts default to `0.4`, `0.3`, `1.6`)

## Quick runs

```bash
# GUI frontier exploration demo in the warehouse
bash gazebo-sim/scripts/frontier_demo.sh
# In a second terminal, fly 5 autonomous frontier steps:
bash gazebo-sim/scripts/frontier_go.sh 5
# Clean shutdown:
bash gazebo-sim/scripts/demo_stop.sh

# Headless dry-run of hardware.launch.py in Gazebo:
bash gazebo-sim/tests/hw_profile_test.sh 5
```
