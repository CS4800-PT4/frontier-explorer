# Frontier exploration on the sim-sev stack

Click-to-fly is the prerequisite. Do not start this until t, o, and one
2D Goal Pose move the vehicle on the sim-sev stack. The other stack in
../sim is a separate setup. This phase publishes goals into the same
path the 2D Goal Pose tool already uses.

## What already exists

- Pose: /mavros/local_position/odom
- Occupancy: /drone_0_grid/grid_map/occupancy_inflate
  (PointCloud2, frame world). Empty width 0 means the map is not ready.
- Goal input the planner already subscribes to: /goal_pose
  (geometry_msgs/PoseStamped). Confirmed on /drone_0_ego_planner_node.
- Planner output: /drone_0_planning/pos_cmd, then px4_ego in offboard.

The frontier node does not fly the drone. It picks a point and publishes
/goal_pose. EGO and px4_ego already turn that into motion.

## OOP split

One ROS node, four small classes. Keep them in one package so the
assignment can see the objects.

- MapView: store the latest occupancy cloud and pose. Expose
  is_known, is_free, is_occupied, world_to_index.
- FrontierDetector: cells that are free and touch an unknown cell.
  Return clusters, not every cell.
- FrontierRanker: drop a candidate if it is in occupied space, inside
  the vehicle radius, or already failed. Score the rest.
  Default score is information gain over distance. Weights are params.
- ExplorationManager: own the loop. Pick the best goal, publish it,
  mark it failed if pose does not get close before a timeout, stop
  when no frontier remains. Count explored cells, path length, failed goals.

The node only wires subscriptions, a timer, and publishers. Detection
and ranking stay out of the callback.

## Topics

Subscribe:
- /drone_0_grid/grid_map/occupancy_inflate
- /mavros/local_position/odom

Publish:
- /goal_pose, frame odom, z kept at the current hover height.
  A z of 0 is the floor and the planner rejects it.
- visualization_msgs/MarkerArray for frontier clusters.

Params:
- cluster_min_cells, goal_timeout_sec, min_goal_sep, w_gain, w_dist

## Loop

1. Wait until the cloud width is not 0 and odom is fresh.
2. Detect and cluster.
3. Filter. Rank. Publish one goal.
4. If the vehicle is within min_goal_sep, mark done and pick again.
5. If the timeout hits, or the planner logs the terminal point in an
   obstacle, append that goal to failed and pick the next.
6. No candidates left: stop publishing and log complete.

One goal at a time. A stream of clicks is what made the path bounce.

## Where to look

- Assignment wording: explored vs unknown boundary, unreachable goal,
  completion, metrics, visualization.
- EGO grid input: ego_planner grid_map, topic occupancy_inflate.
- Goal subscriber: ros2 node info /drone_0_ego_planner_node
  shows /goal_pose.
- Pose frame: echo /mavros/local_position/odom and match goal frame_id
  to the planner, which has been odom.

## Troubleshoot

- occupancy_inflate width 0: depth bridge dead, or NumPy 2 broke
  cv_bridge. pip3 install --user 'numpy<2' and restart C.
- Goal published, drone still: D not in offboard. t, hover, o first.
  Echo /fmu/in/trajectory_setpoint. z of 0 is the old takeoff bug.
- plan_success 0 and terminal point in obstacle: goal z is 0 or the
  point is inside a pillar. Hold hover z and skip that cluster.
- Red path rewrites and the vehicle never moves: goals are being
  published in a loop. One goal, then wait.
- Drone under the grid: a goal or takeoff z went below the floor.
  Disarm, restart C, do not keep clicking.
