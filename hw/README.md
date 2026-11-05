# Hardware bring-up (Jetson Orin Nano + ZED + PX4 1.15)

This folder sets up and checks the drone. The sim lives in `sim/`. Both run the same
`frontier_explorer` package, and on the drone everything starts from one launch file:

```bash
ros2 launch frontier_explorer hardware.launch.py camera_model:=zed2i
```

**Current goal (Nov 2026): the stationary demo in section 4.** The Jetson is on the drone and
plugged into the flight controller, RViz shows the map, the frontiers and EGO's planned path,
and nothing flies.

- `hw/CLEAN_INSTALL.md` checks the setup scripts on a clean VM, and has notes for running them on
  the real Jetson.
- `docs/STACK.md` shows how the pieces connect in the sim and on the drone.
- `sim-sev/jetson-runner/` is Sev's version of the same install and run steps. It builds the same
  workspaces in the same folders, but builds the ZED wrapper from master, adds a px4_ego patch
  that takes off to 2 m above the current spot, and starts its own launch file
  (`sim-sev/hardware.launch.py`). Pick one path per Jetson. This README uses `hw/` and the
  `frontier_explorer` launch file.

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
3. Check the flight controller's firmware in QGroundControl first. If it isn't 1.15, run this
   step as `PX4_MSGS_BRANCH=release/1.xx bash hw/2_jetson_setup.sh` (1.xx = the firmware), since
   mismatched messages show topics with no data. Then `bash hw/2_jetson_setup.sh` builds
   px4_msgs (release/1.15), the XRCE agent, EGO, the bridge and this repo, then runs
   `hw/zed_setup.sh` for the ZED. It builds one package at a time so the Orin Nano doesn't run
   out of memory (`COLCON_WORKERS=2` is faster if you have swap). Safe to re-run if a step fails.
   - **ZED SDK:** if `/usr/local/zed` exists, the installed SDK is kept as is. If not, it
     downloads SDK 5.5 for this JetPack, or the newest older one Stereolabs builds for it, and
     installs it (it asks for your password). On L4T 36.3 that's SDK 5.2. Pick another with
     `ZED_SDK_VERSION=5.2`.
   - **ZED wrapper:** builds the wrapper release made for that SDK (SDK 5.5 -> `v5.5.0`). If it
     doesn't build, it tries the next two older releases. Logs: `~/zed_ws/logs/`. Force one
     with `ZED_WRAPPER_REF=<tag>`. A `~/zed_ws` that someone else already built (the Jetson's
     owner, or Sev's jetson-runner) is left as is unless you run it with `ZED_REBUILD=1`.
   - The first-generation ZED (sold as "ZED 2K Stereo") is still a camera model in SDK 5.5
     (`sl::MODEL::ZED` in its headers, checked Nov 2026).
4. Load ROS and the workspaces in every new terminal. First run
   `grep -n 'ROS_DOMAIN_ID\|setup.bash' ~/.bashrc`. If the Jetson is already set up that way,
   keep the ID it has and skip the block. Otherwise pick a `ROS_DOMAIN_ID` (0 to 101) that no
   other team on the network uses (use the same one on any laptop that runs RViz), change
   `~/frontier-explorer` if the repo is somewhere else (part 2 prints the path), then open a
   new terminal:

```bash
cat >> ~/.bashrc <<'EOF'
export ROS_DOMAIN_ID=42
source /opt/ros/humble/setup.bash
for ws in ~/ros2_ws ~/ego_ws ~/px4_ego_ws ~/zed_ws ~/frontier-explorer; do
  [ -f $ws/install/setup.bash ] && source $ws/install/setup.bash
done
EOF
```

On a fresh x86 Ubuntu with CUDA already installed, part 1 took about 3 minutes and part 2 about
10.5 (with `ZED_SDK_INSTALL=1`, so that includes the ZED SDK and wrapper). The Orin Nano is
slower, so plan on an hour.

## 2. Wiring and PX4 settings (QGroundControl)

On the demo drone the professor set up the camera and the flight controller, and we don't have
their settings. Use this section to check what's there, and ask before changing anything.

- Flight controller USB to a Jetson USB port (MAVROS).
- Flight controller TELEM2 to the Jetson's 40-pin UART (TX to RX, RX to TX, GND to GND). Check
  the device name with `ls /dev/ttyTHS*` and pass `xrce_args:="serial --dev /dev/ttyTHSx -b 921600"`
  if it isn't `ttyTHS1`. The stationary demo doesn't use this link.

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
`EKF2_EV_CTRL` and `EKF2_GPS_CTRL`, and prints `EKF2_HGT_REF`, `EKF2_EV_DELAY`,
`EKF2_EV_POS_X/Y/Z`, `COM_OF_LOSS_T`, `COM_OBL_RC_ACT` and `UXRCE_DDS_CFG`. Check the rest in
QGroundControl.

**First-generation ZED (no IMU).** Its pose is level only if the camera was level when tracking
started. If the drone sits nose-up on its gear, the ZED's "up" is tilted, and taking height from
it makes the drone climb or sink as it flies forward (about 35 cm over 10 m at 2 degrees). So for
`camera_model:=zed`, set `EKF2_EV_CTRL` = 9 (horizontal position + yaw) and `EKF2_HGT_REF` = Baro,
and start the launch with the drone level. The ZED 2/2i/Mini have an IMU and don't have this problem.

## 3. Camera mount and intrinsics

1. Check which camera it is (the label on it) and use that model everywhere below: `zed2i` for a
   ZED 2i, `zed` for the first-generation ZED.
2. Measure the ZED's left lens from the flight controller: forward, left, up in meters (`cam_x`,
   `cam_y`, `cam_z`) and how far it tilts down (`cam_pitch_deg`). EGO uses these. Keep the
   camera level for now: `vision_relay` and the explorer assume a level camera.
3. Start the ZED alone and save its intrinsics (once per camera and resolution). Leave it
   running for step 4, then stop it with Ctrl-C, since the full launch starts the ZED too.

```bash
ros2 launch zed_wrapper zed_camera.launch.py camera_model:=zed2i \
  ros_params_override_path:=$(ros2 pkg prefix frontier_explorer)/share/frontier_explorer/config/zed_override.yaml
bash hw/zed_intrinsics.sh      # second terminal; writes ~/.ego_hw/zed_intrinsics.yaml
```

`config/zed_override.yaml` sets VGA, 15 Hz, position tracking on and area memory off. EGO
crashes on depth images bigger than 640 x 480, so the script refuses to save anything bigger.
With EGO on (the default), the main launch exits with an error if this file is missing, unless
you pass all of `fx`, `fy`, `cx` and `cy`.

4. Work out `EKF2_EV_POS_X/Y/Z`. The pose the ZED sends PX4 is for the frame named in
   `child_frame_id` of its odometry, not the left lens, so the offset is different from `cam_*`:

```bash
ros2 topic echo /zed/zed_node/odom --once --no-arr | grep child_frame_id   # e.g. zed_camera_link
ros2 run tf2_ros tf2_echo zed_camera_link zed_left_camera_frame            # left lens from that frame
```

   With the tf2_echo translation as (tx, ty, tz): `EV_POS_X = cam_x - tx`, `EV_POS_Y = -(cam_y - ty)`,
   `EV_POS_Z = -(cam_z - tz)`. PX4 is x forward, y right, z down, which is why Y and Z flip. A
   wrong offset makes the position swing in a circle when the drone yaws.

## 4. Stationary demo (the drone does not fly)

`bridge:=false` and `xrce:=false` leave out the only pieces that send commands to PX4, so EGO
plans paths but nothing follows them.

Before you start:
- ZED in a USB 3 port (blue) and the flight controller on USB: `lsusb | grep -i stereolabs` and
  `ls /dev/ttyACM*`
- `groups | grep dialout` (log out and back in after part 1 if it's missing)
- intrinsics saved (section 3)
- the same `ROS_DOMAIN_ID` in every terminal and on the RViz laptop

Use the camera model from section 3 in place of `zed2i` in every command here (`zed` for the
first-generation ZED, and then start the launch with the drone sitting level).

```bash
# terminal 1: the stack
ros2 launch frontier_explorer hardware.launch.py camera_model:=zed2i bridge:=false xrce:=false
# terminal 2: RViz, on the Jetson's monitor (not over plain SSH) or on a laptop that has ROS 2
# Humble and this repo built and sourced (or pass -d the path to src/frontier_explorer/rviz/frontier.rviz)
rviz2 -d $(ros2 pkg prefix frontier_explorer)/share/frontier_explorer/rviz/frontier.rviz
# terminal 3: live numbers
ros2 topic echo /frontier/status
```

Wait for `ZED tracking OK` from `vision_relay` in terminal 1. (With the ZED-only command below,
`vision_relay` is off, so wait for `ros2 topic hz /zed/zed_node/odom` to show a rate instead.)
Then:

1. Pick the drone up to chest height and walk it slowly around the room. The explorer only
   marks space as seen when the drone is at least 0.5 m above where its position started
   (`min_sweep_z`), and it skips frames while the drone turns faster than about 30 degrees a
   second. Sitting on the floor, no free space gets marked (you may still see a few
   obstacles), so there are no frontiers.
2. Watch the map grow in RViz.
3. Ask for a goal from a fourth terminal: `ros2 service call /frontier/go_best std_srvs/srv/Trigger`. The explorer sends
   the green goal to EGO, and EGO draws its planned path (at 1 m height). Nothing follows it.
   You can also click a goal with RViz's 2D Goal Pose tool. Asking again before the drone is
   within 0.6 m of the last goal counts that goal as not reached (`failed` goes up) and picks a
   different one, which is expected when nothing flies.

What RViz shows:

| What | Meaning |
| --- | --- |
| light blue | seen and free |
| dark gray | obstacle |
| blank | not seen yet |
| orange squares | frontier cells, the edge between seen and unseen |
| blue spheres | frontier goals |
| green sphere and line | the goal `go_best` would send |
| text above the drone | m2 seen and the number of frontiers |
| red, green and blue axes | the drone's pose (`/mavros/local_position/odom`), red points forward |
| EGO's displays | its 3D map (`map inflate`) and planned path (`optimal_traj`) |

The `simulation_map`, `drone_path` and `robot` displays only have data in the sim, so they stay
empty on the drone.

`/frontier/status` prints `known_m2=<area> frontiers=<n> best=<x,y or none> failed=<n>` twice a
second. The explorer only counts obstacles 0.7 to 1.3 m above where its position started.

**If PX4 has no position** (EGO keeps printing `no odom.`, usually because the flight controller
isn't using the ZED), take the pose straight from the ZED and leave MAVROS out:

```bash
ros2 launch frontier_explorer hardware.launch.py camera_model:=zed2i bridge:=false xrce:=false \
  mavros:=false vision:=false odom_topic:=/zed/zed_node/odom
```

In RViz, change the Odometry display's topic to `/zed/zed_node/odom`. Heights are then measured
from where the ZED started. Leave `cam_x/y/z` at 0 for this. That pose is already the camera's
center, which is only a few cm from the left lens, close enough for the demo.

**Stopping:** Ctrl-C once in terminal 1 and wait. If it hangs for more than 15 seconds, run
`pkill -f "ros2 launch"`. A second Ctrl-C while it shuts down can make `extrinsic_node` get
killed (exit code -9) or `traj_server` abort (exit code -6). Both are harmless.

## 5. Bench check (props off)

This needs the full launch (MAVROS and the XRCE agent on). With the demo flags from section 4,
the XRCE checks fail, which is expected. Point the camera at a wall or a box 1 to 4 m away, then:

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
- the explorer mapping (hold the drone above 0.5 m for this one, see section 4)
- `EKF2_EV_CTRL` and `EKF2_GPS_CTRL`, and prints some of the other PX4 settings (section 2)

Options: `VISION=0` skips the vision checks, `DEPTH_TOPIC=...` times a different depth topic,
`SIM=1` is for the sim test.

Then do the hand checks:
- Carry the drone 1 m forward and watch `/mavros/local_position/odom` move about 1 m.
- Yaw it in place: the position should stay put (if it circles, `EKF2_EV_POS_*` is off).
- Cover the lens. `vision_relay` should log "ZED lost tracking" and stop forwarding, and PX4
  should report vision lost and the position as bad within a second or two. When the ZED loses
  tracking it keeps publishing its last pose, so this check is the one that proves PX4 won't
  hold a frozen position.
- Check obstacles in RViz (section 4).

## 6. First flight (not the current goal)

Not until the bench check passes and the hand checks look right. Use a net or a tether, a
safety pilot on RC with a kill switch, and slow settings (the launch defaults are 0.5 m/s).

**Known problem: the bridge fights RC takeover.** Every 20 ms the px4_ego bridge re-sends
OFFBOARD whenever PX4 isn't in it (and arm when disarmed, in takeoff mode) while it is in 't',
and in 'o' once EGO has sent a command. It re-sends LAND every 20 ms in 'l'. If the pilot flips
to Position, the bridge switches it straight back. (The bridge source isn't in this repo; this
is from Sev's copy, `sim-sev/offboard_control_test.py`.) There's no fix for this in `sim/patches/px4_ego` yet (only 0001 and 0002), so the only
abort that is sure to work is the RC kill switch. Test this props off: in 'o', flip the RC mode
switch and see what QGroundControl shows.

Mode keys go to the bridge on `/mode_key`. It subscribes best effort, so send each key a few
times, since one message can be lost before the bridge connects:

```bash
key() { ros2 topic pub -r 2 -t 3 /mode_key std_msgs/msg/String "{data: $1}"; }
```

1. RC in Position mode, kill switch in reach. Start the launch and wait for "ZED tracking OK".
2. `key t`: arms, switches to OFFBOARD and climbs to 0.9 m above where PX4's position started.
   (A bridge built by Sev's jetson-runner climbs to 2 m above the current spot instead, which is
   above EGO's 1.6 m ceiling.) Wait for a steady hover.
3. `key o`: the bridge now follows EGO. Press it **before** asking for a goal: a goal sent
   while the bridge is in 't' or 'p' leaves EGO's command waiting, and the drone flies straight
   at it when 'o' is pressed.
4. `ros2 service call /frontier/go_best std_srvs/srv/Trigger` for each frontier goal. Watch
   RViz and wait for the drone to stop before the next one.
5. `key l` to land. `key d` disarms once it is on the ground (PX4 refuses to disarm in the air).

What the other keys do: `p` holds the current point (still in OFFBOARD). `m` stops sending
trajectory setpoints but keeps sending the offboard heartbeat, so PX4 may not see offboard as
lost and may hold the last setpoint. Neither is a quick abort.

`KNOWN_ISSUES.md` (from Sev's runs) says starting the explorer between takeoff and `o` crashes
the explorer or the bridge. This launch starts the explorer before takeoff. If it misbehaves,
start with `explorer:=false` and run the explorer by hand after `o`. It needs the ZED topics,
since its defaults are the sim's:

```bash
ros2 run frontier_explorer explorer_node --ros-args \
  -p depth_topic:=/zed/zed_node/depth/depth_registered -p odom_topic:=/mavros/local_position/odom
```

## Launch arguments

`ros2 launch frontier_explorer hardware.launch.py --show-args` lists them all.

| Argument | Default | |
| --- | --- | --- |
| `zed`, `mavros`, `xrce`, `ego`, `bridge`, `explorer`, `vision` | `true` | turn a piece off to run it by hand |
| `camera_model` | none, needed with `zed:=true` | `zed`, `zedm`, `zed2` or `zed2i` |
| `fcu_url` | `/dev/ttyACM0:57600` | MAVROS link |
| `gcs_url` | empty | optional QGroundControl link, e.g. `udp-b://@` |
| `xrce_args` | `serial --dev /dev/ttyTHS1 -b 921600` | XRCE agent link |
| `odom_topic` | `/mavros/local_position/odom` | the pose EGO and the explorer use |
| `intrinsics_file` | `~/.ego_hw/zed_intrinsics.yaml` | from `hw/zed_intrinsics.sh` |
| `fx`, `fy`, `cx`, `cy` | empty | give all four to skip the intrinsics file |
| `cam_x`, `cam_y`, `cam_z`, `cam_pitch_deg` | `0.0` | camera mount, section 3 |
| `zed_override` | `config/zed_override.yaml` | ZED params file |
| `depth_topic`, `zed_odom`, `zed_status` | the ZED wrapper's names | change if a wrapper renames them |
| `max_vel`, `max_acc` | `0.5`, `0.8` | slower than the sim (0.8, 1.0) for first flights |
| `inflation`, `ground`, `ceil` | `0.4`, `0.3`, `1.6` | same as the warehouse sim |
| `map_size_x`, `map_size_y`, `map_size_z` | `40`, `40`, `4` | EGO's map size (the explorer uses x and y) |
| `depth_timeout` | `1.0` | EGO stops after this long without depth or odometry (s) |

## If something goes wrong

| What you see | Fix |
| --- | --- |
| `set camera_model:=` | add `camera_model:=zed2i` (or your model) |
| `no camera intrinsics: run bash hw/zed_intrinsics.sh first` | section 3, or pass `fx fy cx cy` |
| `depth is ... EGO only handles up to 640x480` | the ZED isn't at VGA: check `zed_override`, then redo the intrinsics |
| `zed_wrapper is not installed` | open a new terminal so `~/.bashrc` runs, or re-run part 2 |
| `CAMERA NOT DETECTED` every few seconds, then the ZED's container dies | USB 3 port, reseat the cable, check `lsusb`, then restart the launch |
| EGO keeps printing `no odom.` | nothing on `odom_topic`: check `ls /dev/ttyACM*`, `dialout` and `fcu_url`, or use the ZED-only command in section 4 |
| map stays empty, `known_m2=0.0` | lift the drone above 0.5 m, and check `ros2 topic hz /zed/zed_node/depth/depth_registered` (about 15) |
| `go_best` says `no usable frontier` | nothing seen yet, or every frontier is too close, too near a wall, near the map edge or already failed |
| nodes or topics you didn't start | another team's ROS traffic: set `ROS_DOMAIN_ID` in every terminal |
| exit code -9 or -6 when stopping | the harmless shutdown race, see section 4 |
| a compiler gets `Killed` during part 2 | out of memory: `MAKEFLAGS=-j2 bash hw/2_jetson_setup.sh` |

## Checked (Nov 2026)

- Full install on a fresh Ubuntu 22.04 x86 machine (CUDA 12.6 first, then part 1, then part 2
  with `ZED_SDK_INSTALL=1` for the ZED SDK and wrapper), then this launch with the ZED on and
  MAVROS, XRCE, the bridge and `vision_relay` off: it loads SDK 5.5.1 and reports no camera,
  while EGO and the explorer run. CI runs parts 1 and 2 on ARM without the ZED.
- XRCE agent v2.4.2 with Fast-DDS 2.12.2 builds and starts.
- ZED wrapper topic and parameter names (`depth/depth_registered`, `odom`, `pose/status` with
  `PosTrackStatus`, and the ones in `config/zed_override.yaml`) are the same in releases v5.2.2
  through v5.5.0 and master.

## Not confirmed yet (check on the Jetson)

- The ZED SDK install on the Jetson itself. Its installer was downloaded and its options
  checked, but it has only run on x86.
- Which camera is on the drone. Notes call it "ZED2K" (first-generation, `camera_model:=zed`,
  with the EKF settings in section 2), but the demo commands use `zed2i`.
- The flight controller's settings, set by the professor. `bench_check.sh` prints some of them.
- The UART device name (`ttyTHS1` vs `ttyTHS0`) depends on the JetPack version.
- The XRCE agent talking to the real flight controller.
- Start order. In the sim, PX4 SITL (1.18 beta) crashed when the XRCE agent started after PX4
  had booted, so the sim test starts the agent first. On the drone the flight controller boots
  before the Jetson. If `bench_check.sh` shows no `/fmu/out` data, reboot the flight
  controller (QGroundControl or power) while the launch is running.
- The ZED-only fallback in section 4. The explorer's turn check reads the turn rate from that
  odometry, and it isn't checked whether the ZED fills it in.
- Whether EGO plans a path while the drone sits on the floor, below its 0.3 m map floor. Hold it
  up for the demo.

The sim test `bash sim/hw_profile_test.sh` runs this same launch file and `bench_check.sh`
against the warehouse sim, with `sim/fake_zed.py` standing in for the camera.
