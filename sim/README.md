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
   ```

## Step 1 — Install packages (needs sudo, ~5 min)
```bash
sudo bash sim/1_sudo_install.sh
```

## Step 2 — Build everything (~10 min)
```bash
bash sim/2_user_setup.sh
```
This builds MAVROS, clones the three planner/sim repos, applies our fixes (`sim/patches/`), and builds them.

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
| Build errors | Re-run `bash sim/2_user_setup.sh` (safe to repeat) |

Logs: `~/.ego_sim/`. Full details, what we fixed and why: [`REFERENCE.md`](REFERENCE.md).
