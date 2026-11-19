# `uav-explorer`

Unified root directory for the UAV frontier exploration stack—hardware bring-up, Gazebo simulation, the ROS 2 exploration package, configuration files, and upstream patches.

## Contents

| Path | Purpose |
|---|---|
| `hardware.launch.py` | Single ROS 2 launch file that brings up the full Jetson stack (ZED wrapper, MAVROS, Micro XRCE-DDS agent, EGO-Planner, `px4_ego` offboard bridge, `extrinsic_node`, `vision_relay`, and optional `exploration_manager`). |
| `jetson-runner/` | Numbered install, build, run, intrinsics capture, live-demo (`04`–`06`), and props-off `bench_check.sh` scripts for Jetson Orin Nano. See [jetson-runner/README.md](jetson-runner/README.md). |
| `../gazebo-sim/` | Gazebo Harmonic + PX4 SITL setup, GUI/headless demos, warehouse world, and `hw_profile_test.sh` dry-run harness (at repo root). See [../gazebo-sim/README.md](../gazebo-sim/README.md). |
| `uav_frontier_exploration/` | ROS 2 `ament_python` package containing `exploration_manager`, `extrinsic_node`, and `vision_relay`. See [uav_frontier_exploration/README.md](uav_frontier_exploration/README.md). |
| `config/` | ZED VGA parameter override (`zed_override.yaml`) and RViz layout (`rviz/frontier.rviz`). See [config/README.md](config/README.md). |
| `patches/` | Upstream `git format-patch` series for `ego-swarm-ros2`, `px4_ego`, and `ego-planner-ros2-sim`. See [patches/README.md](patches/README.md). |

## `hardware.launch.py` key arguments

Normally started through `jetson-runner/04_run_stack.sh` (which forwards all extra CLI arguments):

- **Subsystem toggles:** `zed:=true`, `mavros:=true`, `xrce:=true`, `ego:=true`, `bridge:=true`, `vision:=true`, `explorer:=false` (left off by default so `06_run_demo.sh` starts exploration only after takeoff and offboard mode).
- **Flight controller links:** `fcu_url:=/dev/ttyACM0:57600`, `xrce_args:="serial --dev /dev/ttyTHS1 -b 921600"`, `gcs_url:=""`.
- **Camera & extrinsics:** `camera_model:=zed2i`, `intrinsics_file:=~/.ego_hw/zed_intrinsics.yaml`, `cam_x`, `cam_y`, `cam_z`, `cam_pitch_deg`.
- **Map bounds:** `map_size_x`, `map_size_y` (`04_run_stack.sh` passes `10.0` × `10.0` m to match `06_run_demo.sh`).

## MAVROS & Micro XRCE-DDS connection settings

All hardware connection defaults live in `uav-explorer/hardware.launch.py` (lines 46–49), which wires `fcu_url` and optional `gcs_url` into `mavros/launch/px4.launch` (lines 167–169) and launches `MicroXRCEAgent` with `xrce_args` (line 176):

- **`fcu_url`** — Controls the MAVROS link carrying PX4 state out and vision odometry in.
  - **Real drone default:** `/dev/ttyACM0:57600` (USB) — edit `uav-explorer/hardware.launch.py` line 46 to change permanently.
  - **Gazebo sim default:** `udp://:14540@127.0.0.1:14555` — defined in `gazebo-sim/launch/px4_sitl_ros2.launch.py` (line 17) and passed into `hardware.launch.py` by `gazebo-sim/tests/frontier_test.sh` (line 74).
- **`xrce_args`** — Controls the `MicroXRCEAgent` transport carrying offboard trajectory setpoints in and `/fmu/out/...` status out.
  - **Real drone default:** `serial --dev /dev/ttyTHS1 -b 921600` (Jetson UART to PX4 TELEM2) — edit `uav-explorer/hardware.launch.py` lines 48–49 to change permanently.
  - **Gazebo sim default:** `udp4 -p 8888` — defined in `gazebo-sim/launch/px4_sitl_ros2.launch.py` (line 24) and `gazebo-sim/tests/frontier_test.sh` (line 74).
- **`gcs_url`** — Optional QGroundControl telemetry bridge (default `""` on `uav-explorer/hardware.launch.py` line 47, e.g. `udp-b://@`).

### Runtime CLI overrides

`jetson-runner/04_run_stack.sh` forwards any extra CLI arguments straight to `uav-explorer/hardware.launch.py`, so you can switch USB/serial ports or baud rates without editing the launch file:

```bash
bash uav-explorer/jetson-runner/04_run_stack.sh \
  fcu_url:=/dev/ttyUSB0:921600 \
  xrce_args:="serial --dev /dev/ttyTHS1 -b 921600"
```
