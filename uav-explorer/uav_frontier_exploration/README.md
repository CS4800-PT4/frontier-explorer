# `uav_frontier_exploration`

Location: `uav-explorer/uav_frontier_exploration/`

ROS 2 Python (`ament_python`) package implementing autonomous frontier-based exploration along with the hardware camera-mount and vision-odometry relay nodes used on the Jetson.

## Executables (`console_scripts`)

- **`exploration_manager`** — Core frontier exploration node. Consumes EGO-Planner's inflated occupancy cloud, UAV odometry, and depth frame timestamps; detects, filters, and ranks unexplored frontier clusters; publishes a 2D coverage map and RViz markers; and sends the best frontier to `/goal_pose` when triggered via `/frontier/go_best`.
- **`extrinsic_node`** — Publishes the camera-to-body extrinsic transform (`/vins_estimator/extrinsic`) required by EGO-Planner on hardware.
- **`vision_relay`** — Relays ZED odometry (`/zed/zed_node/odom`) to MAVROS (`/mavros/vision_pose/pose_cov`) for PX4 EKF2 indoor position fusion.

## Package modules

| Module | Responsibility |
|---|---|
| `exploration_manager.py` | ROS 2 node owning subscriptions, timer loop, goal dispatch, failure tracking, and publishing. |
| `frontier.py` | Data classes for frontier candidates and scored frontiers. |
| `frontier_detector.py` | `MapView` (2D occupancy projection, ray-swept free space, and free/occupied/unknown queries) and `FrontierDetector` (BFS clustering of free cells bordering unknown space). |
| `frontier_filter.py` | Drops candidates inside obstacles, within safety clearance, outside map edge margin, or near failed goals. |
| `frontier_ranker.py` | Scores remaining frontier clusters by information gain and distance. |
| `goal_selector.py` | Picks the top-scoring frontier and builds a `geometry_msgs/PoseStamped` target. |
| `frontier_visualizer.py` | Publishes RViz `MarkerArray` visuals (`/frontier/markers`) for frontier cells, clusters, and the selected goal. |
| `metrics_tracker.py` | Tracks explored area, path length, goals sent, and failures. |
| `mount.py` | Camera-to-body rotation and quaternion math used by `extrinsic_node`. |
| `extrinsic_node.py` / `vision_relay.py` | Hardware extrinsic publisher and ZED-to-MAVROS odometry relay nodes. |

## ROS 2 interface

- **Subscribed topics:**
  - `/drone_0_grid/grid_map/occupancy_inflate` (`sensor_msgs/PointCloud2`, param `cloud_topic`)
  - `/mavros/local_position/odom` (`nav_msgs/Odometry`, param `odom_topic`)
  - `/depth_camera_bestef` (`sensor_msgs/Image`, param `depth_topic`; set to `none` to disable freshness checks; overridden to `/zed/zed_node/depth/depth_registered` on hardware)
- **Published topics:**
  - `/frontier/map` (`nav_msgs/OccupancyGrid`) — 2D explored coverage map
  - `/frontier/best_goal` (`geometry_msgs/PoseStamped`) — best frontier preview for RViz
  - `/frontier/markers` (`visualization_msgs/MarkerArray`) — frontier cells, clusters, and target markers
  - `/frontier/status` (`std_msgs/String`) — concise exploration metrics summary
  - `/goal_pose` (`geometry_msgs/PoseStamped`, param `goal_topic`) — goal sent to EGO-Planner when triggered
- **Service:**
  - `/frontier/go_best` (`std_srvs/srv/Trigger`) — publishes the current best frontier to `/goal_pose` once

## Key parameters (`exploration_manager`)

| Parameter | Default | Meaning |
|---|---|---|
| `frame_id` / `goal_z` | `'map'` / `1.0` | Output frame and flight altitude (m) for goals and markers. |
| `map_size_x` / `map_size_y` / `resolution` | `40.0` / `40.0` / `0.1` | 2D coverage grid bounds and cell size (m); match EGO's map size (`10.0` on Jetson). |
| `band_low` / `band_high` | `0.7` / `1.3` | Vertical height band (m) used when projecting obstacles into 2D. |
| `fov_deg` / `max_range` / `min_sweep_z` | `73.0` / `4.0` / `0.5` | Camera FOV (deg), ray sweep range (m), and minimum altitude to mark free space. |
| `min_frontier_size` / `split_size` | `8` / `2.0` | Minimum cells per cluster and max cluster span before splitting (m). |
| `min_goal_dist` / `clearance` / `edge_margin` | `1.0` / `0.3` / `1.0` | Goal filtering thresholds (m). |
| `arrive_dist` / `max_yaw_rate` / `depth_max_age` / `rate` | `0.6` / `0.5` / `0.3` / `2.0` | Arrival radius (m), yaw-rate sweep guard (rad/s), depth freshness limit (s), and timer rate (Hz). |

## Build and run

```bash
source /opt/ros/humble/setup.bash
colcon build --base-paths uav-explorer/uav_frontier_exploration --packages-select uav_frontier_exploration --symlink-install
source install/setup.bash

# Run exploration_manager standalone (with EGO-Planner + MAVROS already running)
ros2 run uav_frontier_exploration exploration_manager

# Trigger one frontier goal send to EGO-Planner
ros2 service call /frontier/go_best std_srvs/srv/Trigger {}
```
