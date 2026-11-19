# Frontier Explorer (CS 4800)

Autonomous frontier-based UAV exploration stack built on ROS 2 Humble, EGO-Planner, and PX4. The same exploration package (`uav_frontier_exploration`) runs in Gazebo simulation and on a Jetson Orin Nano with a Stereolabs ZED depth camera and PX4 flight controller.

## How the stack works

1. **Depth & odometry** come from Gazebo + PX4 SITL in simulation or a ZED camera + MAVROS on hardware.
2. **EGO-Planner (`ego-swarm-ros2`)** builds an inflated 3D occupancy map and plans collision-free trajectories.
3. **Frontier Explorer (`uav_frontier_exploration`)** reads the occupancy map, odometry, and depth freshness, detects and ranks unexplored frontier clusters, publishes coverage maps and RViz markers, and sends the best target to `/goal_pose` when triggered via `/frontier/go_best`.
4. **Offboard bridge (`px4_ego`)** translates EGO trajectory setpoints into PX4 offboard commands over Micro XRCE-DDS.

See [STACK.md](STACK.md) for the full topic and link diagram.

## Repository layout

Everything lives under `uav-explorer/` and `gazebo-sim/` (consolidating the previous `hw/`, `sim/`, `live-demo/`, `worlds/`, and `src/` folders):

```text
frontier-explorer/
├── STACK.md                           # System architecture and topic flow
├── gazebo-sim/                        # Gazebo Harmonic + PX4 SITL simulation
│   ├── setup/                         # Ubuntu & warehouse install scripts
│   ├── scripts/                       # Interactive launch, demo, and stop scripts
│   ├── tests/                         # Smoke, warehouse, frontier, and hardware-profile tests
│   ├── launch/                        # PX4 SITL launch file and sim helpers (fake_zed.py)
│   └── worlds/                        # Gazebo world definitions (default_warehouse.sdf, ego.sdf)
└── uav-explorer/
    ├── README.md                      # Unified stack overview and hardware.launch.py reference
    ├── hardware.launch.py             # Single-command Jetson hardware launch
    ├── jetson-runner/                 # Jetson Orin Nano install, build, live-flight (04-06), and bench scripts
    ├── uav_frontier_exploration/      # ROS 2 Python package (exploration_manager, vision_relay, extrinsic_node)
    ├── config/                        # ZED VGA override and RViz display layout
    └── patches/                       # Upstream patches for EGO-Planner, px4_ego, and Gazebo sim
```

## Flight controller links (MAVROS & Micro XRCE-DDS)

PX4 uses two links: **MAVROS** (`fcu_url`) carries vehicle state out and ZED vision pose in on hardware, while **Micro XRCE-DDS** (`xrce_args`) carries offboard trajectory setpoints in and `/fmu/out/...` status out. An optional `gcs_url` forwards telemetry to QGroundControl.

| Parameter | Controls | Gazebo sim default | Real drone default | Where to edit |
|---|---|---|---|---|
| `fcu_url` | MAVROS link to PX4 (`mavros/launch/px4.launch`) | `udp://:14540@127.0.0.1:14555` | `/dev/ttyACM0:57600` (USB) | Drone: `uav-explorer/hardware.launch.py` (line 46)<br>Sim: `gazebo-sim/launch/px4_sitl_ros2.launch.py` (line 17) & `gazebo-sim/tests/frontier_test.sh` (line 74) |
| `xrce_args` | `MicroXRCEAgent` transport arguments | `udp4 -p 8888` | `serial --dev /dev/ttyTHS1 -b 921600` (Jetson UART → TELEM2) | Drone: `uav-explorer/hardware.launch.py` (lines 48–49)<br>Sim: `gazebo-sim/launch/px4_sitl_ros2.launch.py` (line 24) & `gazebo-sim/tests/frontier_test.sh` (line 74) |
| `gcs_url` | Optional QGroundControl bridge | *(unused)* | `""` (disabled; e.g. `udp-b://@`) | Drone: `uav-explorer/hardware.launch.py` (line 47) |

On the Jetson, `uav-explorer/jetson-runner/04_run_stack.sh` forwards all extra CLI arguments directly to `uav-explorer/hardware.launch.py`, so you can override ports at runtime without editing any files (for example: `bash uav-explorer/jetson-runner/04_run_stack.sh fcu_url:=/dev/ttyUSB0:921600`).

## Quick start

- **Unified stack & hardware launch:** [uav-explorer/README.md](uav-explorer/README.md)
- **Jetson Orin Nano (install, bench check, live demo):** [uav-explorer/jetson-runner/README.md](uav-explorer/jetson-runner/README.md)
- **Gazebo + PX4 SITL simulation:** [gazebo-sim/README.md](gazebo-sim/README.md)
- **ROS 2 exploration package:** [uav-explorer/uav_frontier_exploration/README.md](uav-explorer/uav_frontier_exploration/README.md)
- **Configs & upstream patches:** [uav-explorer/config/README.md](uav-explorer/config/README.md) · [uav-explorer/patches/README.md](uav-explorer/patches/README.md)
