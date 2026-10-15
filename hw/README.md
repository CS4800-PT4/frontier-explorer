# Hardware bring-up (Jetson Orin Nano + ZED + PX4 1.15)

This folder sets up and checks the drone. The sim lives in `sim/`. Both run the same
`frontier_explorer` package, and on the drone everything starts from one launch file:

```bash
ros2 launch frontier_explorer hardware.launch.py camera_model:=zed2i
```

`docs/STACK.md` shows how the pieces connect in the sim and on the drone.

## What runs on the drone

| Piece | Talks to | Link |
| --- | --- | --- |
| ZED wrapper | depth to EGO and the explorer, odometry to `vision_relay` | USB 3 |
| MAVROS | PX4 state out (`/mavros/local_position/odom`), vision pose in | Flight controller USB (`/dev/ttyACM0`) |
| Micro XRCE-DDS agent | setpoints from the bridge in (`/fmu/in/...`), status out (`/fmu/out/...`) | Jetson UART to TELEM2 (`/dev/ttyTHS1`, 921600) |
| EGO planner | plans around what the ZED sees | |
| px4_ego bridge | turns EGO's commands into PX4 setpoints | |
| explorer_node | builds the explored map and picks frontier goals | |
| extrinsic_node | tells EGO where the camera sits on the drone | |
| vision_relay | forwards ZED odometry to PX4 through MAVROS (indoor position) | |

## 1. Install (once)

1. Check the JetPack version: `cat /etc/nv_tegra_release`. JetPack 6 (L4T R36) is Ubuntu 22.04,
   which ROS 2 Humble needs.
2. `sudo bash hw/1_jetson_sudo.sh`: ROS 2 Humble and system packages. Log out and back in
   afterwards so the serial ports work (it adds you to `dialout`).
3. Install the ZED SDK for your JetPack from https://www.stereolabs.com/developers/release.
   If the camera is the first-generation ZED (sold as "ZED 2K Stereo"), check the SDK release
   notes say it is still supported.
4. `bash hw/2_jetson_setup.sh`: builds px4_msgs (release/1.15), the XRCE agent, MAVROS, EGO,
   the bridge, the ZED wrapper and this repo, then prints the lines to add to `~/.bashrc`.
   Pin the wrapper to the release that matches your SDK: `ZED_WRAPPER_REF=<tag> bash hw/2_jetson_setup.sh`.

Check the flight controller's firmware in QGroundControl first. If it isn't 1.15, run step 4
with `PX4_MSGS_BRANCH=release/1.xx` to match. Mismatched messages show topics with no data.

## 2. Wiring and PX4 settings (QGroundControl)

- Flight controller USB to a Jetson USB port (MAVROS).
- Flight controller TELEM2 to the Jetson's 40-pin UART (TX to RX, RX to TX, GND to GND). Check
  the device name with `ls /dev/ttyTHS*` and pass `xrce_args:="serial --dev /dev/ttyTHSx -b 921600"`
  if it isn't `ttyTHS1`.

| Parameter | Set to | Why |
| --- | --- | --- |
| `UXRCE_DDS_CFG` | TELEM 2 | XRCE client on the port wired to the Jetson |
| `SER_TEL2_BAUD` | 921600 | Matches `xrce_args` |
| `MAV_1_CONFIG` | Disabled, if it was TELEM 2 | Only one thing can use TELEM2 |
| `EKF2_EV_CTRL` | 11 (horizontal position + vertical position + yaw) | Use the ZED pose |
| `EKF2_HGT_REF` | Vision | Height from the ZED, not the barometer |
| `EKF2_GPS_CTRL` | 0 | No GPS indoors |
| `EKF2_MAG_TYPE` | None | Indoor magnetometer readings fight the vision yaw |
| `EKF2_EV_DELAY` | start at 50 ms | Tune from a flight log later |
| `EKF2_EV_POS_X/Y/Z` | camera position, **x forward, y right, z down** | Note: `cam_y`/`cam_z` in the launch are left/up, so `EV_POS_Y = -cam_y`, `EV_POS_Z = -cam_z` |
| `COM_OBL_RC_ACT` | Land (or Position once vision is trusted) | What PX4 does if offboard setpoints stop |
| `COM_OF_LOSS_T` | 1.0 (default) | The sim uses 5.0 only because WSL stalls |
| `COM_RCL_EXCEPT` | 0 (default) | RC loss still triggers a failsafe in offboard |
| `COM_ARM_WO_GPS` | allow | Arm without GPS |

Values are from the PX4 1.15 parameter list. Check each one in QGroundControl's dropdown,
since the numbers behind the names can change between versions. `bench_check.sh` prints the
ones it can read.

## 3. Camera mount and intrinsics

1. Measure the ZED's left lens from the flight controller: forward, left, up in meters (`cam_x`,
   `cam_y`, `cam_z`) and how far it tilts down (`cam_pitch_deg`). Keep it level for now:
   `vision_relay` assumes a level camera.
2. Start the ZED alone and save its intrinsics (once per camera and resolution):

```bash
ros2 launch zed_wrapper zed_camera.launch.py camera_model:=zed2i \
  ros_params_override_path:=$(ros2 pkg prefix frontier_explorer)/share/frontier_explorer/config/zed_override.yaml
bash hw/zed_intrinsics.sh      # second terminal; writes ~/.ego_hw/zed_intrinsics.yaml
```

`config/zed_override.yaml` only sets VGA, 15 Hz and position tracking. EGO crashes on depth
images bigger than 640 x 480, so the script refuses to save anything bigger.

## 4. Bench check (props off)

```bash
ros2 launch frontier_explorer hardware.launch.py camera_model:=zed2i \
  cam_x:=0.10 cam_z:=0.05          # your measurements
bash hw/bench_check.sh             # second terminal
```

It checks depth at 10+ Hz (`MIN_DEPTH_HZ` changes that), MAVROS connected, XRCE data (status and local position), the
vision pose reaching MAVROS, the camera mount reaching EGO, EGO's map, and the explorer
mapping. Then it prints the PX4 settings above. Then do the hand checks from the release
plan: carry the drone 1 m forward and watch `/mavros/local_position/odom` move about 1 m,
cover the lens and confirm PX4 flags the position as bad, and check obstacles in RViz from a
laptop on the same network.

Launch arguments (`ros2 launch frontier_explorer hardware.launch.py --show-args` lists them all):

| Argument | Default | |
| --- | --- | --- |
| `zed`, `mavros`, `xrce`, `ego`, `bridge`, `explorer`, `vision` | `true` | turn a piece off to run it by hand |
| `fcu_url` | `/dev/ttyACM0:57600` | MAVROS link |
| `xrce_args` | `serial --dev /dev/ttyTHS1 -b 921600` | XRCE agent link |
| `max_vel`, `max_acc` | `0.5`, `0.8` | slower than the sim (0.8, 1.0) for first flights |
| `inflation`, `ground`, `ceil` | `0.4`, `0.3`, `1.6` | same as the warehouse sim |

## Not confirmed yet (check on the Jetson)

- ZED wrapper parameter and topic names come from the wrapper's 4.x docs. If
  `ros2 topic list` shows different names, pass `depth_topic:=` and `zed_odom:=`.
- The UART device name (`ttyTHS1` vs `ttyTHS0`) depends on the JetPack version.
- XRCE agent v2.4.2 is the version the PX4 1.15 guide uses.
- Start order. In the sim, PX4 SITL (1.18 beta) crashed when the XRCE agent started after PX4
  had booted, so the sim test starts the agent first. On the drone the flight controller boots
  before the Jetson. If `bench_check.sh` shows no `/fmu/out` data, reboot the flight
  controller (QGroundControl or power) while the launch is running.
- The ZED model ("ZED2K") sets `camera_model`.

The sim test `bash sim/hw_profile_test.sh` runs this same launch file and `bench_check.sh`
against the warehouse sim, with `sim/fake_zed.py` standing in for the camera.
