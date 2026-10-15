# frontier_explorer

Frontier-based exploration for the PX4 + EGO-Planner drone.

## Frontier explorer (R1)

`explorer_node` builds its own map of what the drone has seen, finds frontiers (the edge
between seen free space and unseen space) and picks the next goal. In R1 the goal is only
shown in RViz. Calling `/frontier/go_best` sends it to EGO once. Closed-loop exploration
comes in R3.

| File | Class | What it does |
| --- | --- | --- |
| `map_view.py` | MapView | 2D grid (0.1 m cells) of EGO's 40 x 40 m map. Occupied cells come from EGO's cloud, using only points between 0.7 and 1.3 m. Free cells come from sweeping the camera's 73 deg, 4 m field of view from odom. |
| `frontier_detector.py` | FrontierDetector | Free cells next to unseen cells, grouped into clusters and cut into 2 m pieces. Small pieces are dropped. |
| `frontier_ranker.py` | FrontierRanker | Drops goals too close to the drone, an obstacle, the map edge or a failed goal. Picks the lowest cost: distance + turn - frontier size (capped at 2 m). |
| `explorer_node.py` | ExplorerNode | ROS wrapper. Callbacks only store messages, a 2 Hz timer does the work. It sweeps only with a fresh cloud, only while depth frames are arriving on `depth_topic` (default `/depth_camera_bestef`; set the ZED depth topic on hardware, or `none` to skip the check), and not while turning faster than 0.5 rad/s. A goal from `go_best` that the drone has not reached by the next call is marked failed and skipped. |

Topics:

| Direction | Topic | Type |
| --- | --- | --- |
| in | `/drone_0_grid/grid_map/occupancy_inflate` | sensor_msgs/PointCloud2 |
| in | `/mavros/local_position/odom` | nav_msgs/Odometry |
| out | `/frontier/map` | nav_msgs/OccupancyGrid |
| out | `/frontier/map_cloud` | sensor_msgs/PointCloud2 (seen cells, intensity 1 = obstacle; only while someone subscribes) |
| out | `/frontier/markers` | visualization_msgs/MarkerArray |
| out | `/frontier/best_goal` | geometry_msgs/PoseStamped |
| out | `/frontier/status` | std_msgs/String (`known_m2=... frontiers=... best=x,y failed=...`) |
| out | `/goal_pose` | geometry_msgs/PoseStamped, only when `/frontier/go_best` is called |
| service | `/frontier/go_best` | std_srvs/Trigger |

Every number above is a ROS parameter (`ros2 param list /explorer_node`), e.g.
`ros2 run frontier_explorer explorer_node --ros-args -p clearance:=0.5`.

Run it:

```bash
# Unit tests (no ROS or sim needed)
cd src/frontier_explorer && python3 -m pytest test -q

# GUI demo in the warehouse, then in a second terminal let the explorer pick goals
bash sim/frontier_demo.sh
bash sim/frontier_go.sh 5
bash sim/demo_stop.sh

# Headless test, prints PASS/FAIL
bash sim/frontier_test.sh
```

## Hardware launch (R2)

`launch/hardware.launch.py` starts the drone stack with one command: the ZED wrapper, MAVROS,
the XRCE agent, EGO (with the ZED's intrinsics), the px4_ego bridge, `explorer_node` and the
two nodes below. Setup and bring-up: [hw/README.md](../../hw/README.md).

| File | Node | What it does |
| --- | --- | --- |
| `mount.py` | | Camera mount math. EGO moves depth points from the camera's optical frame onto the drone with a fixed cam2body transform; this builds it from the measured offset and tilt. |
| `extrinsic_node.py` | extrinsic_node | Publishes that transform on `/vins_estimator/extrinsic` once a second, the only way to set EGO's camera mount without editing EGO. Params `cam_x`, `cam_y`, `cam_z` (m, forward/left/up), `cam_pitch_deg` (down). |
| `vision_relay.py` | vision_relay | Forwards ZED odometry (`/zed/zed_node/odom`) to `/mavros/vision_pose/pose` so PX4 has a position indoors. Drops poses with NaNs and warns when the ZED stops sending. |

```bash
# On the drone
ros2 launch frontier_explorer hardware.launch.py camera_model:=zed2i cam_x:=0.10 cam_z:=0.05
# In the sim, with a fake ZED (prints PASS/FAIL)
bash sim/hw_profile_test.sh
```

## Node Documentation

This documentation is to provide guidance on creating and interacting with a ROS2 node.

## Node Setup
###  Step 1:
Create a new python file under src/frontier_explorer/frontier_explorer.

###  Step 2:
Write code in the python file to create a ROS2 Node. Use the template from template_node.py as a starting point.

### Step 3:
After writing the code necessary for a ROS2 node, go to setup.py. Relative to the root of the repository, this is located in src/frontier_explorer/setup.py. In setup.py under console_scripts in entry_points, follow this format to create the node.

"{node_name} = {package_name}.{python_file_name}:main"

For example, if you want to name the node template_node  under the frontier_explorer package and the python file name is template_node.py, this is how it would appear.

```bash
entry_points={
    'console_scripts': [
        "template_node = frontier_explorer.template_node:main"
    ],
},
```

### Step 4:
Edit ~/.bashrc to include the setup script from this repository if this has not been done yet. If ~/.bashrc does not have "source ~/frontier-explorer/install/setup.bash", run these commands.

```bash
echo "source ~/frontier-explorer/install/setup.bash" >> ~/.bashrc
source ~/.bashrc
```

### Step 5:
Run the build command from the root of the repository to include the changes to the build.

```bash
# Must run this command from the root of the repository
colcon build
```

## Node Execution
### Step 1:
Run this command to execute your node.
```bash
# Follow this format
ros2 run {package_name} {node_name}

# Here is an example with template_node
ros2 run frontier_explorer template_node

```

### Step 2:
To stop the node, press ctrl + c.
