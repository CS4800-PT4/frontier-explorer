# How the stack connects

The same planner, bridge and explorer run in the sim and on the drone. Only the sources
change: Gazebo and PX4 SITL in the sim, the ZED and the real flight controller on the drone.

```
             sim                                   drone
   Gazebo depth camera                       ZED wrapper
   /depth_camera_bestef                      /zed/zed_node/depth/depth_registered
            \                                  /
             +---> EGO grid map <-------------+         <- /vins_estimator/extrinsic
             |     (EGO planner)                           (extrinsic_node: camera mount)
             |          | /drone_0_grid/grid_map/occupancy_inflate
             |          v
             |     explorer_node --/goal_pose--> EGO planner
             |                                       | /drone_0_planning/pos_cmd
             |                                       v
             |                               px4_ego bridge
             |                                       | /fmu/in/trajectory_setpoint
             |                                       | /fmu/in/offboard_control_mode
             |                                       v  (Micro XRCE-DDS agent)
   PX4 SITL (UDP)  <---------------------------- PX4 (serial on the drone)
        |                                            ^
        | MAVLink (MAVROS)                           | /mavros/vision_pose/pose (drone only,
        v                                            |  vision_relay <- /zed/zed_node/odom)
   /mavros/local_position/odom ----> EGO, explorer_node, frontier scripts
```

- PX4 has two links. MAVROS carries state out (and the vision pose in on the drone).
  The XRCE agent carries setpoints in and `/fmu/out/...` status out. EGO never talks to PX4.
- EGO maps from a depth image plus odometry. It projects pixels with `fx, fy, cx, cy` and
  moves them onto the drone with its cam2body transform. On the drone the intrinsics come from
  the ZED (`hw/zed_intrinsics.sh`) and the mount from `extrinsic_node`.
- The explorer only uses EGO's obstacle cloud, odometry and the depth topic's arrival time,
  so it doesn't care which camera feeds EGO.

## Sim vs drone

| Piece | Sim | Drone | Set by |
| --- | --- | --- | --- |
| Start command | `sim/demo.sh`, `sim/frontier_test.sh` | `ros2 launch frontier_explorer hardware.launch.py` | |
| Depth into EGO | `/depth_camera_bestef`, 640 x 480 | `/zed/zed_node/depth/depth_registered`, VGA (672 x 376) | `depth_topic:=` |
| Intrinsics | EGO's defaults (the sim camera) | `~/.ego_hw/zed_intrinsics.yaml` | `hw/zed_intrinsics.sh` |
| Camera mount | EGO's default (level, at the body origin) | measured offset | `cam_x/y/z`, `cam_pitch_deg` |
| MAVROS link | `udp://:14540@127.0.0.1:14555` | `/dev/ttyACM0:57600` (USB) | `fcu_url:=` |
| XRCE link | `udp4 -p 8888` | `serial --dev /dev/ttyTHS1 -b 921600` | `xrce_args:=` |
| Indoor position | Gazebo's simulated GPS | ZED odometry through `vision_relay` and MAVROS | PX4 `EKF2_*` params |
| PX4 version, px4_msgs | 1.18 beta, px4_msgs `d49263b` | 1.15, px4_msgs `release/1.15` | |
| Local position topic | `/fmu/out/vehicle_local_position_v1` | `/fmu/out/vehicle_local_position` | bridge listens to both (patch 0002) |
| Speed | 0.8 m/s | 0.5 m/s to start | `max_vel:=` |
| `COM_OF_LOSS_T` | 5 s (WSL stalls) | 1 s (default) | |

`sim/hw_profile_test.sh` runs the drone column in the sim: the hardware launch with
`zed:=false`, the sim links, and `sim/fake_zed.py` publishing the sim camera under the ZED
topic names.
