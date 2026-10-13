# EGO-Planner + PX4 SITL Simulation — Setup Reference (WSL)

Detailed reference for the `sim/` folder. **For setup steps, see [README.md](README.md).**
Tested 2026-09-29 on WSL2 Ubuntu 22.04 (ROS 2 Humble). Scripts and patches: `sim/`. Runtime logs and state: `~/.ego_sim/`.

**Status: working, verified end to end.**
- GUI demo: 2D Goal Pose clicks in RViz fly the drone (confirmed by user).
- Headless test: takeoff → offboard → goal (7.9, 3.2) reached at (7.80, 3.10, 0.99); a second goal sent mid-flight (0.6, −1.0) reached at (0.59, −0.97) with the planner staying up.

> **Brief:** The stock stack couldn't follow 2D Goal Pose clicks because of seven separate faults: MAVROS missing (no odometry for the planner), a stale bundled `px4_msgs`, the offboard bridge listening to the wrong PX4 status topic (`_v1` vs `_v4`), a NumPy 2 conflict crashing the depth bridge, a 10 m planner map that treated farther goals as obstacles, a ROS 1→2 porting bug that crashed the planner on a busy-time goal, and unreliable one-shot CLI publishes. We built MAVROS 2.15.1 from source, pinned NumPy < 2, and fixed the rest with small patches committed on a local `sim-fixes` branch in **ego-swarm-ros2**, **px4_ego** and **ego-planner-ros2-sim** (exported as `.patch` files); **mavros** only got build-config `COLCON_IGNORE`s and **PX4-Autopilot** only the copied launch file.

---

## 1. Quick start

### GUI demo (easiest)
```bash
bash sim/demo.sh          # Gazebo + RViz open (~45 s), auto takeoff + offboard, flies to (4, 2), prints READY
                                  # then: RViz → 2D Goal Pose → click a goal (you can click again mid-flight)
bash sim/demo_stop.sh     # in a 2nd terminal when done (restores the arming setting)
bash sim/kill_all.sh      # only if demo_stop hangs
```
The demo doesn't need QGC (it temporarily sets PX4 `NAV_DLL_ACT=0`; `demo_stop.sh` restores it from `~/.ego_sim/nav_dll_act_orig`). It refuses to start if a sim is already running. Clicked goals → `~/.ego_sim/demo_logs/goals.log`, positions → `positions.log`.

### Manual (the author's workflow)
```bash
bash sim/launch_all.sh    # Windows Terminal tabs: C PX4+Gazebo+MAVROS → B EGO → A RViz → D bridge → E keys
```
1. **Open QGroundControl** (required here — PX4 refuses to arm with `Preflight Fail: No connection to the GCS` without it).
2. Tab **E**: `t` (takeoff) → wait for a steady hover (~0.9 m) → `o` (offboard).
3. RViz: **2D Goal Pose** → click. Drone flies there at z = 1.0 m.

Keys (tab E): `t` takeoff · `p` position hold · `o` offboard/follow EGO · `l` land · `d` disarm

### Rules of thumb
- **Goals in free space, within ±20 m of the start.** Out-of-map points count as obstacles; a goal on/near a cylinder (e.g. (3, 0) — cylinder at (2.52, −0.20)) is refused (`terminal point ... is in obstacle`) and the drone stops short.
- **Never press Ctrl+Z** in a sim terminal — it *suspends* (freezes) everything and leaves ROS wedged. Use Ctrl+C or `demo_stop.sh`. If ROS commands hang afterwards: `wsl --shutdown` in PowerShell, reopen Ubuntu.
- Only one sim at a time (two PX4/MAVROS instances collide).

### Sourcing order (any manual terminal)
```bash
source /opt/ros/humble/setup.bash
source ~/mavros_ws/install/setup.bash
source ~/ros2_ws/install/setup.bash       # px4_msgs (matches PX4 1.18)
source ~/ego_ws/install/setup.bash
source ~/px4_ego_ws/install/setup.bash
```

### Health checks
```bash
ros2 topic hz /mavros/local_position/odom                    # ~30 Hz; if missing, planner ignores goals ("no odom.")
ros2 topic echo --qos-reliability best_effort /fmu/out/vehicle_status_v4 --once   # PX4 -> ROS link
ros2 topic echo --qos-reliability best_effort /depth_camera_bestef --once --field encoding   # 32FC1 = obstacle map OK
ros2 topic echo /goal_pose --once                            # then click in RViz
ros2 topic echo /drone_0_planning/pos_cmd --once             # appears after a click
```
Humble's `ros2 topic hz` has no QoS flag, so it shows nothing for best-effort topics — use `echo --qos-reliability best_effort`.

### Automated test (headless, no display needed)
```bash
bash sim/e2e_test.sh 4.0 2.0              # goal x y
bash sim/e2e_test.sh 7.9 3.2 0.6 -1.0     # + second goal sent mid-flight
```
Runs Gazebo without GUI (`GZ_HEADLESS=1`), takes off (retrying until z > 0.6 m), goes offboard, sends goal(s), prints positions and whether the planner survived, then shuts down and restores `NAV_DLL_ACT`. Logs → `~/.ego_sim/e2e_logs/`.

---

## 2. How the pieces connect

```
RViz 2D Goal Pose ──/goal_pose──► ego_planner ──/drone_0_planning/pos_cmd──► offboard_control_test ──/fmu/in/*──► PX4 SITL
                                     ▲    ▲                                   (px4_ego_py)   ◄──/fmu/out/*_v1,_v4──┘ (MicroXRCEAgent udp 8888)
      MAVROS ──/mavros/local_position/odom┘    │
      Gazebo /depth_camera ─► depth_gz_bridge.py ─/depth_camera_bestef─┘ (obstacle map)
/mode_key (mode_key.py: t/p/o/l/d) ──► offboard_control_test
```

---

## 3. Repositories

| Path | Repo | Base commit | Our changes |
|---|---|---|---|
| `~/ego_ws/src/ego-swarm-ros2` | github.com/DongnanHu6556/ego-swarm-ros2 | `fd80847` | branch `sim-fixes` (`aea15a0`): 40 m map, planner crash fix, ignore bundled `px4_msgs` |
| `~/px4_ego_ws/src/px4_ego` | github.com/DongnanHu6556/px4_ego | `77e9a5f` | branch `sim-fixes` (`588bcf4`): subscribe to `vehicle_status_v4` |
| `~/ego-planner-ros2-sim` | github.com/DongnanHu6556/ego-planner-ros2-sim | `fdbe874` | branch `sim-fixes` (`2068b78`): `ego` world default, optional headless Gazebo |
| `~/mavros_ws/src/mavros` | github.com/mavlink/mavros | tag `2.15.1` (`22ae5b7`) | `COLCON_IGNORE` in `mavros_msgs`, `test_mavros`, `mavros_examples` (build config only) |

See the exact diff for any repo: `git -C <path> diff main..sim-fixes`. Revert to stock: `git -C <path> checkout main` and rebuild.

Already present before this setup:

| Path | Version | Changes |
|---|---|---|
| `~/PX4-Autopilot` | `v1.18.0-beta1-794-g860aca9864` | untracked `launch/px4_sitl_ros2.launch.py` (copied from the sim repo) |
| `~/ros2_ws/src/px4_msgs`, `px4_ros_com` | px4_msgs `d49263b` (main) | none |
| `~/Micro-XRCE-DDS-Agent` | `v3.0.2` → `/usr/local/bin/MicroXRCEAgent` | none |

---

## 4. Installed packages

### apt (`sim/1_sudo_install.sh`)

| Package | Why |
|---|---|
| `ros-humble-pcl-ros`, `ros-humble-pcl-conversions`, `libpcl-dev` | `local_sensing` / `plan_env` need PCL |
| `ros-humble-cv-bridge`, `ros-humble-image-transport`, `python3-opencv`, `python3-numpy` | depth image handling |
| `ros-humble-laser-geometry`, `ros-humble-tf2-geometry-msgs` | planner build deps |
| `libarmadillo-dev`, `libeigen3-dev`, `libboost-all-dev` | planner math/build deps |
| `ros-humble-ros-gzharmonic` | `ros_gz_bridge` for Gazebo Harmonic |
| `ros-humble-mavlink`, `ros-humble-mavros-msgs` (2.15.1) | MAVROS source build deps |
| `geographiclib-tools`, `libgeographic-dev` | MAVROS dependency |
| `python3-rosdep`, `python3-vcstool` | dependency tooling |
| `ros-humble-diagnostic-updater`, `ros-humble-angles`, `ros-humble-eigen-stl-containers`, `ros-humble-message-filters` | MAVROS build deps |
| `libasio-dev`, `ros-humble-ament-cmake-google-benchmark` | MAVROS build deps |

### Other
- **GeographicLib datasets** → `/usr/share/GeographicLib/` (geoids egm96-5, gravity egm96, magnetic emm2015). MAVROS crashes at startup without them.
- **rosdep** initialized (`sudo rosdep init`, `rosdep update`).
- **pip (user):** `numpy` 2.2.6 → **1.26.4** in `~/.local` (fault 4).

---

## 5. Files copied / modified outside git

| Action | Detail |
|---|---|
| Copied | `~/ego-planner-ros2-sim/px4_sitl_ros2.launch.py` → `~/PX4-Autopilot/launch/` (patched version) |
| Copied | `simulation-gazebo`, `depth_gz_bridge.py` → `~/ros_proj/gazebo_start/` (chmod +x) |
| Downloaded | Gazebo models/worlds → `~/.simulation-gazebo/` (via `simulation-gazebo --dryrun`) |
| Copied | `ego.sdf` → `~/.simulation-gazebo/worlds/` |
| Downloaded + edited | Fuel models `Depot` → `~/.simulation-gazebo/models/depot` (collisions added, static) and `Standing person` → `models/person` (static, local mesh path), by `sim/warehouse_setup.sh` |
| Copied | `worlds/default_warehouse.sdf` → `~/.simulation-gazebo/worlds/` |

---

## 6. Faults found and fixed

| # | Symptom | Cause | Fix | Where |
|---|---|---|---|---|
| 1 | Planner ignores goals, prints `no odom.` | Planner reads `/mavros/local_position/odom`; MAVROS not installed, and `ros-humble-mavros` is missing from the ROS apt repo. PX4 launch starts MAVROS via shell, so it fails quietly | Built MAVROS 2.15.1 from source in `~/mavros_ws` + GeographicLib data | mavros (build only) |
| 2 | Arm/mode commands mismatched | ego-swarm-ros2 bundles an older `px4_msgs` (`VehicleStatus`/`VehicleCommand` differ from PX4 1.18) that shadowed `~/ros2_ws`'s | `COLCON_IGNORE` on `utils/px4_msgs` | ego-swarm-ros2 |
| 3 | After `o`, drone never follows trajectories | Bridge only subscribed to `vehicle_status`/`_v1`; PX4 1.18 publishes `vehicle_status_v4`, so it never saw OFFBOARD | +6 lines: subscribe to `fmu/out/vehicle_status_v4` | px4_ego |
| 4 | No obstacle map; `depth_gz_bridge.py` crashes `_ARRAY_API not found` | PX4's setup pip-installed NumPy 2.2.6, breaking Humble's cv_bridge/OpenCV | `pip3 install --user "numpy<2"` | system |
| 5 | Clicks beyond 5 m → drone stuck/jittering | `single_uav_gazebo.launch.py` set map 10 × 10 m; out-of-map cells count as obstacles (`getInflateOccupancy()` = −1) | `map_size_x/y` 10 → 40 | ego-swarm-ros2 |
| 6 | Planner dies: `Node ... has already been added to an executor` | ROS 1→2 port: `planNextWaypoint()` calls `spin_some(node_)` inside the `/goal_pose` callback when a goal arrives while the FSM is busy | Switch FSM state directly (EXEC_TRAJ → REPLAN_TRAJ, else GEN_NEW_TRAJ) | ego-swarm-ros2 |
| 7 | Takeoff key/goal sometimes lost; test Gazebo GUI segfaults from a background shell | `ros2 topic pub --once` can fire before discovery; Gazebo GUI crashes in software GL without a proper display | Scripts publish 3× and wait for real hover; `GZ_HEADLESS=1` option in launch file | ego-planner-ros2-sim + scripts |
| 8 | Any world but `ego`: PX4 prints `Timed out waiting for Gazebo world` | PX4's x500 airframe defaults `PX4_GZ_WORLD=default` and waits for `/world/default/...`; `ego.sdf` only works because its world is named `default` | Launch file reads `GZ_WORLD`, loads that `.sdf`, and passes its `<world name>` to PX4 | ego-planner-ros2-sim |
| 9 | Drone passes into warehouse shelves/crates | Fuel `Depot` model has no collisions except the floor | `warehouse_setup.sh` adds mesh collisions; model + people made static (otherwise real-time factor drops to ~0.4) | scripts |
| 10 | Drone hits shelf posts, or flies under/over shelves and crashes | Shelves have open levels; EGO plans in 3D with 0.19 m padding, smaller than the x500 (~0.35–0.4 m to prop tip) | Warehouse defaults: `EGO_INFLATION=0.4`, `EGO_GROUND=0.3`, `EGO_CEIL=1.6` (env vars → launch params) | ego-swarm-ros2 + scripts |
| 11 | Drone hovers and ignores all later goals after one hiccup (`Depth Lost! EMERGENCY_STOP` forever) | The map's depth/odom timeout flag was never cleared, and the FSM also turned off fail-safe, so EMERGENCY_STOP could never exit | Clear the flag on fresh data; leave EMERGENCY_STOP once depth is back and the drone has stopped. Slow VMs can also raise `EGO_DEPTH_TIMEOUT` | ego-swarm-ros2 |
| 12 | Runs slow down over time; duplicate depth images | `demo_stop.sh`/`e2e_test.sh` never stopped the depth `parameter_bridge`, so one leaked per run | Kill it in cleanup | scripts |

Other notes:
- **The forwarded `flight_type` fix does not apply.** `single_uav_gazebo.launch.py` already uses `flight_type: 1`; planner and RViz both use `/goal_pose` — **don't** change it to `/move_base_simple/goal`.
- **Goal height is hardcoded** to 1.0 m in `ego_replan_fsm.cpp` → `waypointCallback()`.
- **Arming requires QGC** (`NAV_DLL_ACT=2`) except in `demo.sh`/`e2e_test.sh`.
- `launch_all.sh`/`demo.sh` edits to planner params (map size, speed) in `single_uav_gazebo.launch.py` apply without rebuilding (symlink install); `restart_planner.sh` restarts just the planner. C++ edits need `colcon build --packages-select ego_planner`.
- Harmless log noise: `Failed to load system plugin [libOpticalFlowSystem.so | libGstCameraSystem.so | MotorFailurePlugin]`, `lidar_gz_bridge.py` referenced but commented out, `A message was lost!!!` on best-effort topics.

---

## 7. Rebuild

```bash
# EGO planner (needs px4_msgs from ros2_ws)
source /opt/ros/humble/setup.bash && source ~/ros2_ws/install/setup.bash
cd ~/ego_ws && colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release

# Offboard bridge
source /opt/ros/humble/setup.bash && source ~/ros2_ws/install/setup.bash && source ~/ego_ws/install/setup.bash
cd ~/px4_ego_ws && colcon build --symlink-install

# MAVROS (only if needed)
source /opt/ros/humble/setup.bash
cd ~/mavros_ws && MAKEFLAGS=-j6 colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
```

---

## 8. How the patches work

`sim/2_user_setup.sh` clones each upstream repo, creates a `sim-fixes` branch and applies `sim/patches/<repo>/*.patch` with `git am` (verified to apply cleanly to fresh clones). It's safe to re-run: a patch is skipped when a commit with the same subject is already on `sim-fixes`, so after a `git pull` re-running it applies only the new patches.

To add a fix: commit it on the cloned repo's `sim-fixes` branch, then export it with the next number:
```bash
cd <cloned repo> && git format-patch -1 HEAD -o ~/frontier-explorer/sim/patches/<repo> --start-number <N>
```
Keep the subject under ~60 characters (longer ones wrap in the patch header and won't match on re-runs).

---

## 9. `sim/` contents

| File | What |
|---|---|
| `README.md` | step-by-step setup |
| `REFERENCE.md` | this file |
| `patches/<repo>/*.patch` | our fixes, `git am`-able onto upstream |
| `patches/mavros_colcon_ignore.txt` | the MAVROS build-config markers |
| `1_sudo_install.sh` | apt packages + GeographicLib datasets |
| `2_user_setup.sh` | everything non-sudo, applies patches (idempotent) |
| `demo.sh` / `demo_stop.sh` | GUI demo; stop + restore arming setting |
| `launch_all.sh` | opens tabs A–E in Windows Terminal (manual flow) |
| `e2e_test.sh` | headless takeoff → offboard → goal(s) test |
| `warehouse_setup.sh` | installs the warehouse world + its models (run by `2_user_setup.sh`) |
| `warehouse_test.sh` | headless 4-goal obstacle course in the warehouse, prints PASS/FAIL |
| `smoke.sh` | launches the sim only and checks topics |
| `restart_planner.sh` | restart only the EGO planner (after param edits) |
| `kill_all.sh` | force-stop everything |

Logs (`demo_logs/`, `e2e_logs/`, `warehouse_logs/`, `smoke.log`) and the saved arming setting go to `~/.ego_sim/`, outside the repo.

---

## 10. Warehouse world

- **Select it:** `GZ_WORLD=default_warehouse` (any `<name>.sdf` in `~/.simulation-gazebo/worlds/` works). `SPAWN_POSE=x,y` moves the drone; the default (−6, 0) is open floor, 3.6 m from the nearest obstacle.
- **Layout (Gazebo frame):** walls at x ±15.3, y ±7.7 m. Shelf rows around x 1–3, 5–7 and 9–10.5 (y 0–5), crates at x 0–12, y −1.6 to −6. Planner x = Gazebo x + 6.
- **Planner settings** (env vars, read by `advanced_param.launch.py`; `demo.sh`, `e2e_test.sh` and `warehouse_test.sh` apply the warehouse values automatically):

| Variable | Stock | Warehouse | Meaning |
|---|---|---|---|
| `EGO_INFLATION` | 0.19 | 0.4 | obstacle padding (m) |
| `EGO_GROUND` | −0.01 | 0.3 | lowest altitude the planner may use (m) |
| `EGO_CEIL` | 2.9 | 1.6 | highest altitude (m) |
| `EGO_DEPTH_TIMEOUT` | 1.0 | 1.0 | seconds without depth/odom before an emergency stop; use 3.0 on slow VMs |

- **Course results** (Oct 2026, headless, same 4 goals): stock settings crashed into shelving in both runs. Warehouse settings completed it.
- **Still open:** the planner can still dip under a shelf's lowest level (closest pass 0.37 m). The real fix is a map that treats a whole column as blocked if anything occupies it at flight height (planned frontier mapper).
