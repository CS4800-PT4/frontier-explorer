# Configuration Files

Location: `uav-explorer/config/`

Runtime configuration files shared by `../hardware.launch.py` and RViz visualization.

## Files

- **`zed_override.yaml`** — Parameter overrides passed to `zed_wrapper`. Locks the ZED depth stream to **VGA resolution (≤640×480) at 15 Hz**, which is required because EGO-Planner's depth buffer overflows on higher-resolution images.
- **`rviz/frontier.rviz`** — Pre-configured RViz2 layout displaying the EGO occupancy map, UAV odometry, `/frontier/map`, `/frontier/markers`, `/frontier/best_goal`, `/goal_pose`, and the EGO trajectory.

## Usage

Run RViz in a separate terminal from the flight stack:

```bash
source uav-explorer/jetson-runner/03_env.sh
rviz2 -d uav-explorer/config/rviz/frontier.rviz
```
