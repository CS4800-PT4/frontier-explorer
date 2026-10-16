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
2. `sudo bash hw/1_jetson_sudo.sh`: ROS 2 Humble, MAVROS (from apt) and system packages, plus
   the CUDA toolkit if the Jetson doesn't have it. Log out and back in afterwards so the serial
   ports work (it adds you to `dialout`).
3. Install the ZED SDK for your JetPack from https://www.stereolabs.com/developers/release.
   If the camera is the first-generation ZED (sold as "ZED 2K Stereo"), check the SDK release
   notes say it is still supported.
4. `bash hw/2_jetson_setup.sh`: builds px4_msgs (release/1.15), the XRCE agent, EGO, the
   bridge, this repo and the ZED wrapper, then prints the lines to add to `~/.bashrc`.
   Pin the wrapper to the release that matches your SDK: `ZED_WRAPPER_REF=<tag> bash hw/2_jetson_setup.sh`.
   It builds one package at a time so the Orin Nano doesn't run out of memory
   (`COLCON_WORKERS=2` is faster if you have swap). Safe to re-run if a step fails.

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
| `EKF2_EV_CTRL` | 11 (horizontal position + vertical position + yaw) | Use the ZED pose. 9 for the first-generation ZED, see below |
| `EKF2_HGT_REF` | Vision | Height from the ZED, not the barometer. Baro for the first-generation ZED |
| `EKF2_GPS_CTRL` | 0 | No GPS indoors |
| `EKF2_MAG_TYPE` | None | Indoor magnetometer readings fight the vision yaw |
| `EKF2_EV_DELAY` | start at 50 ms | Tune from a flight log later |
| `EKF2_EV_POS_X/Y/Z` | where the ZED's pose is measured, **x forward, y right, z down** | Not the same point as `cam_x/y/z`, see section 3 |
| `COM_OBL_RC_ACT` | Land (or Position once vision is trusted) | What PX4 does if offboard setpoints stop |
| `COM_OF_LOSS_T` | 1.0 (default) | The sim uses 5.0 only because WSL stalls |
| `COM_RCL_EXCEPT` | 0 (default) | RC loss still triggers a failsafe in offboard |
| `COM_ARM_WO_GPS` | allow | Arm without GPS |

Values are from the PX4 1.15 parameter list. Check each one in QGroundControl's dropdown,
since the numbers behind the names can change between versions. `bench_check.sh` checks
`EKF2_EV_CTRL` and `EKF2_GPS_CTRL` and prints the rest.

**First-generation ZED (no IMU).** Its pose is level only if the camera was level when tracking
started. If the drone sits nose-up on its gear, the ZED's "up" is tilted, and taking height from
it makes the drone climb or sink as it flies forward (about 35 cm over 10 m at 2 degrees). So for
`camera_model:=zed`, set `EKF2_EV_CTRL` = 9 (horizontal position + yaw) and `EKF2_HGT_REF` = Baro,
and start the launch with the drone level. The ZED 2/2i/Mini have an IMU and don't have this problem.

## 3. Camera mount and intrinsics

1. Measure the ZED's left lens from the flight controller: forward, left, up in meters (`cam_x`,
   `cam_y`, `cam_z`) and how far it tilts down (`cam_pitch_deg`). EGO uses these. Keep the
   camera level for now: `vision_relay` and the explorer assume a level camera.
2. Start the ZED alone and save its intrinsics (once per camera and resolution):

```bash
ros2 launch zed_wrapper zed_camera.launch.py camera_model:=zed2i \
  ros_params_override_path:=$(ros2 pkg prefix frontier_explorer)/share/frontier_explorer/config/zed_override.yaml
bash hw/zed_intrinsics.sh      # second terminal; writes ~/.ego_hw/zed_intrinsics.yaml
```

`config/zed_override.yaml` only sets VGA, 15 Hz and position tracking. EGO crashes on depth
images bigger than 640 x 480, so the script refuses to save anything bigger.

3. Work out `EKF2_EV_POS_X/Y/Z`. The pose the ZED sends PX4 is for the frame named in
   `child_frame_id` of its odometry, not the left lens, so the offset is different from `cam_*`:

```bash
ros2 topic echo /zed/zed_node/odom --once --no-arr | grep child_frame_id   # e.g. zed_camera_link
ros2 run tf2_ros tf2_echo zed_camera_link zed_left_camera_frame            # left lens from that frame
```

   With the tf2_echo translation as (tx, ty, tz): `EV_POS_X = cam_x - tx`, `EV_POS_Y = -(cam_y - ty)`,
   `EV_POS_Z = -(cam_z - tz)`. PX4 is x forward, y right, z down, which is why Y and Z flip. A
   wrong offset makes the position swing in a circle when the drone yaws.

## 4. Bench check (props off)

Point the camera at a wall or a box 1 to 4 m away, then:

```bash
ros2 launch frontier_explorer hardware.launch.py camera_model:=zed2i \
  cam_x:=0.10 cam_z:=0.05          # your measurements
bash hw/bench_check.sh             # second terminal
```

It checks:
- depth at 10+ Hz (`MIN_DEPTH_HZ` changes that)
- MAVROS connected, XRCE data (status and local position)
- PX4 has a valid position (`xy_valid`, `z_valid`) and EKF2 is fusing the ZED
- the vision pose reaching MAVROS (`/mavros/vision_pose/pose_cov`)
- the camera mount reaching EGO, and EGO's map having occupied points (so it is really fusing depth)
- the explorer mapping
- `EKF2_EV_CTRL` and `EKF2_GPS_CTRL`, and prints the other PX4 settings

Then do the hand checks:
- Carry the drone 1 m forward and watch `/mavros/local_position/odom` move about 1 m.
- Yaw it in place: the position should stay put (if it circles, `EKF2_EV_POS_*` is off).
- Cover the lens. `vision_relay` should log "ZED lost tracking" and stop forwarding, and PX4
  should report vision lost and the position as bad within a second or two. When the ZED loses
  tracking it keeps publishing its last pose, so this check is the one that proves PX4 won't
  hold a frozen position.
- Check obstacles in RViz from a laptop on the same network.

## 5. First flight

Not until the bench check passes and the hand checks look right. Use a net or a tether, a
safety pilot on RC with a kill switch, and slow settings (the launch defaults are 0.5 m/s).

**Known problem: the bridge fights RC takeover.** The px4_ego bridge re-sends OFFBOARD (and
arm, in takeoff mode) every 20 ms while it is in 't' or 'o', and re-sends LAND every 20 ms in 'l'.
If the pilot flips to Position, the bridge switches it straight back. Until the bridge is fixed
(planned as px4_ego patch 0003), the only abort that is sure to work is the RC kill switch.
Test this props off: in 'o', flip the RC mode switch and see what QGroundControl shows.

Mode keys go to the bridge on `/mode_key`. It subscribes best effort, so send each key a few
times (`mode_key.py` in the px4_ego repo sends it once):

```bash
key() { ros2 topic pub -r 2 -t 3 /mode_key std_msgs/msg/String "{data: $1}"; }
```

1. RC in Position mode, kill switch in reach. Start the launch and wait for "ZED tracking OK".
2. `key t`: arms, switches to OFFBOARD and climbs to 0.9 m. Wait for a steady hover.
3. `key o`: the bridge now follows EGO. Press it **before** asking for a goal: a goal sent
   while the bridge is in 't' or 'p' leaves EGO's command waiting, and the drone flies straight
   at it when 'o' is pressed.
4. `ros2 service call /frontier/go_best std_srvs/srv/Trigger` for each frontier goal. Watch
   RViz and wait for the drone to stop before the next one.
5. `key l` to land. `key d` disarms once it is on the ground (PX4 refuses to disarm in the air).

What the other keys do: `p` holds the current point (still in OFFBOARD). `m` stops sending
setpoints, so after `COM_OF_LOSS_T` PX4 runs the `COM_OBL_RC_ACT` failsafe. Neither is a quick
abort.

Launch arguments (`ros2 launch frontier_explorer hardware.launch.py --show-args` lists them all):

| Argument | Default | |
| --- | --- | --- |
| `zed`, `mavros`, `xrce`, `ego`, `bridge`, `explorer`, `vision` | `true` | turn a piece off to run it by hand |
| `fcu_url` | `/dev/ttyACM0:57600` | MAVROS link |
| `xrce_args` | `serial --dev /dev/ttyTHS1 -b 921600` | XRCE agent link |
| `max_vel`, `max_acc` | `0.5`, `0.8` | slower than the sim (0.8, 1.0) for first flights |
| `inflation`, `ground`, `ceil` | `0.4`, `0.3`, `1.6` | same as the warehouse sim |

## Not confirmed yet (check on the Jetson)

- ZED wrapper parameter and topic names were checked against the wrapper's master branch
  (Oct 2026). An older wrapper may differ: pass `depth_topic:=`, `zed_odom:=` and `zed_status:=`.
- The UART device name (`ttyTHS1` vs `ttyTHS0`) depends on the JetPack version.
- XRCE agent v2.4.2 is the version the PX4 1.15 guide uses.
- Start order. In the sim, PX4 SITL (1.18 beta) crashed when the XRCE agent started after PX4
  had booted, so the sim test starts the agent first. On the drone the flight controller boots
  before the Jetson. If `bench_check.sh` shows no `/fmu/out` data, reboot the flight
  controller (QGroundControl or power) while the launch is running.
- The ZED model ("ZED2K") sets `camera_model`.

The sim test `bash sim/hw_profile_test.sh` runs this same launch file and `bench_check.sh`
against the warehouse sim, with `sim/fake_zed.py` standing in for the camera.
