# Jetson Runner

Location: `uav-explorer/jetson-runner/`

Numbered install, build, verification, and live-flight scripts for running the autonomous exploration stack on a Jetson Orin Nano (JetPack 6 / Ubuntu 22.04, ROS 2 Humble) with a Stereolabs ZED camera and PX4 flight controller. Scripts `04`–`06` replace the legacy live-demo workflow.

## Hardware connection order

1. **ZED camera (USB 3):** plug in before starting `04_run_stack.sh` or `05_capture_intrinsics.sh` and confirm with `lsusb`. `../config/zed_override.yaml` locks depth output to **VGA at 15 Hz** (at or below 640×480, which is EGO-Planner's depth buffer limit).
2. **Flight controller → Jetson USB (MAVROS):** defaults to `fcu_url:=/dev/ttyACM0:57600`. Verify with `ls /dev/ttyACM* /dev/ttyUSB*` and override when calling `04_run_stack.sh` (e.g., `fcu_url:=/dev/ttyUSB0:921600`).
3. **Flight controller TELEM2 → Jetson UART (Micro XRCE-DDS):** defaults to `xrce_args:="serial --dev /dev/ttyTHS1 -b 921600"`. Match TELEM2 baud rate to `921600` in QGroundControl.
4. **Serial permissions:** after running `01_sudo_install.sh`, log out and back in once so membership in the `dialout` group takes effect.

## Changing MAVROS & XRCE connection settings

The single source of truth for real-drone link defaults is `uav-explorer/hardware.launch.py` (lines 46–49, passed to MAVROS on lines 167–169 and `MicroXRCEAgent` on line 176):

| Argument | Controls | Real drone default | Gazebo sim default | File to edit for permanent default |
|---|---|---|---|---|
| `fcu_url` | MAVROS link (PX4 state out, vision pose in) | `/dev/ttyACM0:57600` | `udp://:14540@127.0.0.1:14555` | Drone: `uav-explorer/hardware.launch.py` (line 46)<br>Sim: `gazebo-sim/launch/px4_sitl_ros2.launch.py` (line 17) & `gazebo-sim/tests/frontier_test.sh` (line 74) |
| `xrce_args` | `MicroXRCEAgent` link (offboard setpoints in, `/fmu/out/...` out) | `serial --dev /dev/ttyTHS1 -b 921600` | `udp4 -p 8888` | Drone: `uav-explorer/hardware.launch.py` (lines 48–49)<br>Sim: `gazebo-sim/launch/px4_sitl_ros2.launch.py` (line 24) & `gazebo-sim/tests/frontier_test.sh` (line 74) |
| `gcs_url` | Optional QGroundControl telemetry link | `""` (off) | *(unused)* | Drone: `uav-explorer/hardware.launch.py` (line 47) |

Because `04_run_stack.sh` forwards all extra CLI arguments directly to `uav-explorer/hardware.launch.py`, override ports at runtime whenever your flight controller enumerates on a different device:

```bash
# Example: USB-to-serial adapter on ttyUSB0 at 921600 baud + optional QGC broadcast
bash uav-explorer/jetson-runner/04_run_stack.sh \
  fcu_url:=/dev/ttyUSB0:921600 \
  xrce_args:="serial --dev /dev/ttyTHS1 -b 921600" \
  gcs_url:=udp-b://@
```

## Scripts

| Script | Purpose |
|---|---|
| `00_bootstrap.sh` | One-shot setup entry point that runs `01_sudo_install.sh` followed by `02_build.sh`. |
| `01_sudo_install.sh` | Installs ROS 2 Humble, MAVROS, GeographicLib datasets, CUDA headers, and the ZED SDK (`sudo`). Supports `SKIP_ZED_SDK=1` (keep existing `/usr/local/zed`), `ZED_SDK_VERSION` (default `5.5`), and `ZED_SDK_URL`. |
| `02_build.sh` | Clones, applies `../patches/` (`ego-swarm-ros2` + `px4_ego`), and builds `px4_msgs`, Micro XRCE-DDS Agent, EGO-Planner, `px4_ego`, `zed-ros2-wrapper` (`ZED_WRAPPER_REF`, default `master`), and `uav_frontier_exploration`. |
| `03_env.sh` | Sources ROS 2 Humble and all built workspaces (`source uav-explorer/jetson-runner/03_env.sh`). |
| `04_run_stack.sh` | Launches `../hardware.launch.py` with `map_size_x:=10.0 map_size_y:=10.0` and `explorer:=false` (so flight mode is established before exploration starts). Forwards any extra launch arguments. |
| `05_capture_intrinsics.sh` | Reads `/zed/zed_node/depth/camera_info` once and saves `width, height, fx, fy, cx, cy` to `$WS_ROOT/.ego_hw/zed_intrinsics.yaml`. Run once per camera/resolution while ZED is active. |
| `06_run_demo.sh` | Interactive live-flight demo helper (Enter-prompted step by step). Starts `exploration_manager`, enforces an 8.0 m geofence (`MAX_RADIUS`) and 25 s goal timeout, and logs to `explorer.log`. |
| `bench_check.sh` | Props-off pre-flight verification run in a second terminal while `04_run_stack.sh` is active. Checks depth rate, odometry, ZED vision relay, EKF2 fusion flags, and PX4 parameters (`VISION=0`, `SIM=1`, `DEPTH_TOPIC`, `MIN_DEPTH_HZ`). |

## Live-flight sequence (`04` → `05` → `bench_check` → `06`)

```bash
# 1. One-time install & build on a fresh Jetson
bash uav-explorer/jetson-runner/00_bootstrap.sh

# 2. Terminal 1 — start the hardware stack (override fcu_url / camera_model as needed)
bash uav-explorer/jetson-runner/04_run_stack.sh camera_model:=zed2i

# 3. Terminal 2 — capture ZED intrinsics once (then restart step 2 if first time)
bash uav-explorer/jetson-runner/05_capture_intrinsics.sh

# 4. Terminal 2 — props-off bench check
bash uav-explorer/jetson-runner/bench_check.sh

# 5. Terminal 2 — interactive flight demo (after props-off checks pass)
bash uav-explorer/jetson-runner/06_run_demo.sh
```

### `06_run_demo.sh` flight keys (sent on `/mode_key`)

- **`t`** — arm and take off
- **`o`** — enter offboard mode (**must happen before starting Explorer**; starting Explorer before offboard causes a crash)
- **`p`** — hover in place (freeze current x/y/z)
- **`l`** — land in place
- **`d`** — disarm

### Viewing the map in RViz

Run RViz in its **own separate terminal** (do not pass `rviz:=true` to `hardware.launch.py`, so an RViz crash stays isolated from the flight stack). On the bench, run on the Jetson monitor; for flights, run on a ground-station laptop over Wi-Fi using the same `ROS_DOMAIN_ID` so the Jetson GPU stays dedicated to ZED and EGO:

```bash
source uav-explorer/jetson-runner/03_env.sh
rviz2 -d uav-explorer/config/rviz/frontier.rviz
```
