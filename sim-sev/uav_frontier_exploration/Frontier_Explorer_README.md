# UAV Frontier Exploration Manager

ROS 2 node that consumes the EGO-Planner occupancy cloud and UAV pose, detects frontiers, filters and ranks them, and publishes exploration goals to `/goal_pose`.

## Prerequisites

- Ubuntu 22.04
- ROS 2 Humble
- Working PX4 SITL + Gazebo Harmonic + MAVROS + QGC stack
- Working EGO-Planner (ego-swarm-ros2) and px4_ego offboard bridge

## Build

```bash
source /opt/ros/humble/setup.bash
cd ~/ego_ws
colcon build --packages-select uav_frontier_exploration --symlink-install
source install/setup.bash
```

## Run order

1. **Terminal C** – PX4 + Gazebo  
   ```bash
   source /opt/ros/humble/setup.bash
   ros2 launch ~/PX4-Autopilot/launch/px4_sitl_ros2.launch.py
   ```

2. **QGC** (AppImage)  
   Start the QGC AppImage and confirm the vehicle connects.

3. **Terminal B** – EGO Planner  
   ```bash
   source /opt/ros/humble/setup.bash
   source ~/ego_ws/install/setup.bash
   ros2 launch ego_planner single_uav_gazebo.launch.py
   ```

4. **Terminal A**  
   ```bash
   source /opt/ros/humble/setup.bash
   source ~/ego_ws/install/setup.bash
   ros2 launch ego_planner rviz.launch.py
   ```

5. **Terminal D** – Offboard bridge  
   ```bash
   source /opt/ros/humble/setup.bash
   source ~/ego_ws/install/setup.bash
   source ~/px4_ego/install/setup.bash
   ros2 run px4_ego_py offboard_control_test
   ```

6. **Terminal E** – Mode keys  
   ```bash
   source /opt/ros/humble/setup.bash
   cd ~/px4_ego
   python3 mode_key.py
   ```
   Type `t` (takeoff), wait for hover, then `o` (offboard).

7. **Terminal F** – Exploration manager  
   ```bash
   source /opt/ros/humble/setup.bash
   source ~/ego_ws/install/setup.bash
   ros2 run uav_frontier_exploration exploration_manager
   ```

## Notes

- Goals are published to `/goal_pose` with a 0.6 m clearance check against the occupancy cloud.
- The node only publishes a new goal if it is at least 1.5 m from the previous one and at least 8 s have passed.
- Occupancy topic: `/drone_0_grid/grid_map/occupancy_inflate`  
- Odometry topic: `/mavros/local_position/odom`
