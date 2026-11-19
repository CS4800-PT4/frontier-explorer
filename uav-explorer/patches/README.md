# Upstream Patches

Location: `uav-explorer/patches/`

`git format-patch` series applied automatically to third-party repositories during build so EGO-Planner, the PX4 offboard bridge, and Gazebo simulation work cleanly on ROS 2 Humble and PX4 1.15+.

## Contents

### `ego-swarm-ros2/` (Jetson + Gazebo)
- `0001-Fix-goal-handling-for-PX4-SITL-sim.patch` — Fixes goal state handling in `ego_replan_fsm.cpp` so incoming `/goal_pose` updates do not stall or crash the FSM.
- `0002-Allow-map-safety-settings-to-be-set-from-the-environ.patch` — Exposes inflation radius, ground height, and ceiling height through `EGO_INFLATION`, `EGO_GROUND`, and `EGO_CEIL`.
- `0003-Resume-planning-after-a-short-depth-odom-stall.patch` — Recovers cleanly in `grid_map.cpp` and `ego_replan_fsm.cpp` after brief depth or odometry dropouts.
- `0004-Skip-unknown-NaN-inf-depth-pixels-in-the-map.patch` — Prevents `NaN` / `-inf` depth pixels (blank walls or near-field dropouts) from carving false free-space rays through obstacles.

### `px4_ego/` (Jetson + Gazebo)
- `0001-Subscribe-to-vehicle_status_v4-for-PX4-1.17.patch` — Subscribes to the updated PX4 `vehicle_status` topic format.
- `0002-Also-subscribe-to-vehicle_local_position-for-PX4-1.1.patch` — Subscribes to `vehicle_local_position` for PX4 1.15 compatibility.
- `0101-Take-off-to-2-m-above-current-position-instead-of-fi.patch` — Commands takeoff relative to current altitude (`z - 2.0 m` in NED) instead of a fixed global altitude.

### `ego-planner-ros2-sim/` (Gazebo only)
- `0001-Default-to-ego-world-optional-headless-Gazebo.patch` — Defaults to the EGO world and adds `GZ_HEADLESS` support.
- `0002-Select-Gazebo-world-and-spawn-pose-from-the-environm.patch` — Selects the Gazebo world (e.g., `default_warehouse`) and spawn pose via environment variables.

### `mavros_colcon_ignore.txt` (Gazebo only)
- Lists optional MAVROS sub-packages (`mavros_examples`, `mavros_msgs`, `test_mavros`, `tools`) skipped via `COLCON_IGNORE` when building MAVROS from source in simulation.

## How patches are applied

Do not apply these manually. They are applied automatically onto pinned upstream commits by:
- **Jetson hardware:** `uav-explorer/jetson-runner/02_build.sh` (`ego-swarm-ros2/` + `px4_ego/`)
- **Gazebo simulation:** `gazebo-sim/setup/2_user_setup.sh` (all patch folders + `mavros_colcon_ignore.txt`)
