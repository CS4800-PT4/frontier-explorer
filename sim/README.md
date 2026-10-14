# Simulation Setup (EGO-Planner + PX4 + Gazebo)

A simulated drone that flies to goals you click in RViz and avoids obstacles on the way. Tested on WSL2 Ubuntu 22.04 with ROS 2 Humble.

Run every command in your **Ubuntu (WSL) terminal**, from the repo root (`~/frontier-explorer`).

---

## Step 0 — Prerequisites (skip what you already have)

1. **ROS 2 Humble**: follow the [install guide](https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debians.html) (`ros-humble-desktop`), then add `source /opt/ros/humble/setup.bash` to `~/.bashrc`.
2. **PX4** (same commit we tested):
   ```bash
   git clone --recursive https://github.com/PX4/PX4-Autopilot.git ~/PX4-Autopilot
   cd ~/PX4-Autopilot && git checkout 860aca9864 && git submodule update --init --recursive
   bash Tools/setup/ubuntu.sh        # restart WSL afterwards
   make px4_sitl_default
   ```
3. **px4_msgs**:
   ```bash
   mkdir -p ~/ros2_ws/src && cd ~/ros2_ws/src
   git clone https://github.com/PX4/px4_msgs.git && cd px4_msgs && git checkout d49263b
   cd ~/ros2_ws && colcon build
   ```
4. **Micro XRCE-DDS Agent** (the snap doesn't work, build it):
   ```bash
   git clone -b v3.0.2 https://github.com/eProsima/Micro-XRCE-DDS-Agent.git ~/Micro-XRCE-DDS-Agent
   cd ~/Micro-XRCE-DDS-Agent && mkdir -p build && cd build && cmake .. && make -j4
   sudo make install && sudo ldconfig
   ```

5. **bashrc file**: If your ROS_LOCAL_HOST and RMW_IMPLEMENTATION are not set in bashrc yet, run these commands. If they are already set but have different values, change them to the values shown below.
   ```bash
   echo "export ROS_LOCALHOST_ONLY=0" >> ~/.bashrc
   echo "export RMW_IMPLEMENTATION=rmw_fastrtps_cpp" >> ~/.bashrc
   source ~/.bashrc
   ```

## Step 1 — Install packages (needs sudo, ~5 min)
```bash
sudo bash sim/1_sudo_install.sh
```

## Step 2 — Build everything (~10 min)
```bash
bash sim/2_user_setup.sh
```
This builds MAVROS, clones the three planner/sim repos, applies our fixes (`sim/patches/`), installs the warehouse world, and builds everything.

**Already set up before?** Run `git pull` and then this step again. It only applies the new fixes and rebuilds.

## Step 3 — Check it works (~3 min, no windows open)
```bash
bash sim/e2e_test.sh 4.0 2.0
```
Pass = `pos after goal` shows about `x: 4.0 y: 2.0 z: 1.0`.

## Step 4 — Fly it
```bash
bash sim/demo.sh
```
1. Wait ~1.5 min. Gazebo and RViz open, and the drone takes off and flies to (4, 2) by itself.
2. When the terminal says `READY`: in RViz click **2D Goal Pose**, then click a spot on the grid.
3. The drone flies there at 1 m height. Click again any time.

## Step 5 — Stop it
In a **second** Ubuntu terminal:
```bash
bash sim/demo_stop.sh        # if it hangs: bash sim/kill_all.sh
```

## Step 6 — Warehouse world
Test it (~5 min, no windows open):
```bash
bash sim/warehouse_test.sh
```
Pass = `[warehouse] PASS (4/4 goals)`.

Fly it yourself:
```bash
GZ_WORLD=default_warehouse bash sim/demo.sh
```
Same as Step 4, in a warehouse. The drone starts in open floor; the shelves and crates are ahead of it. Stop with Step 5.

## Step 7 — Frontier explorer
Test it (~6 min, no windows open):
```bash
bash sim/frontier_test.sh
```
Pass = `[frontier] PASS`. It flies to 5 frontiers the explorer picks and prints how much of the map it has seen.

Watch it:
```bash
bash sim/frontier_demo.sh      # warehouse + explorer_node + RViz with the explored map
bash sim/frontier_go.sh 5      # second terminal, once it says READY: fly to 5 frontiers in a row
```
In RViz ("explored map"): light blue = seen and free, dark gray = obstacle, blank = not seen yet, orange = frontier cells, blue = frontier goals, green = the goal the explorer would pick next. You can still click 2D Goal Pose. Stop with Step 5.
The same map is also on `/frontier/map` as an OccupancyGrid ("frontier map" display, off by default because its shader fails on some WSL graphics drivers).

---

## Rules
- **Never press Ctrl+Z.** It freezes the sim instead of stopping it. If things hang after that, run `wsl --shutdown` in PowerShell and reopen Ubuntu.
- **Click open space within ~15 m of the start.** Goals on or near a cylinder get refused, and the drone stops short.
- **Run one sim at a time.**

## Troubleshooting
| Problem | Fix |
|---|---|
| Gazebo/RViz windows don't appear | Run from your own Ubuntu terminal; try `wsl --shutdown` and reopen |
| Drone never takes off | Check `~/.ego_sim/demo_logs/C_px4.log` for `Arming denied` |
| Drone ignores clicks | `ros2 topic hz /mavros/local_position/odom` should show ~30 Hz |
| Slow PC or VM: planner log shows `odom or depth lost` | Start with `EGO_DEPTH_TIMEOUT=3.0` in front of the command, e.g. `EGO_DEPTH_TIMEOUT=3.0 bash sim/demo.sh` |
| Warehouse: `Timed out waiting for Gazebo world` | Re-run `bash sim/2_user_setup.sh` (installs the world and the launch fix) |
| Build errors | Re-run `bash sim/2_user_setup.sh` (safe to repeat) |

Logs: `~/.ego_sim/`. Full details, what we fixed and why: [`REFERENCE.md`](REFERENCE.md).
