# Jetson runner (sim-sev) — live-demo rundown

Numbered scripts under `sim-sev/jetson-runner/`. Edits stay in `sim-sev/` only.
For the CS4800 demo: bring the stack up with `04`, fly with `06`.

---

## 1) Hardware — plug in this order

1. **ZED camera first.**  
   Code never sets a USB device path for the ZED. The wrapper opens by
   `camera_model` (default `zed2i` in `hardware.launch.py`).  
   Practical: use a **USB 3** port on the Jetson, plug it in before starting
   `04` / `05`, confirm with `lsusb` (Stereolabs / ZED).  
   Resolution comes from `sim-sev/config/zed_override.yaml`: **VGA @ 15 Hz**
   (EGO rejects depth bigger than 640×480).

2. **Flight controller → Jetson USB (MAVROS).**  
   Default in `hardware.launch.py`:  
   `fcu_url:=/dev/ttyACM0:57600`  
   Check: `ls /dev/ttyACM* /dev/ttyUSB*`  
   Override when you launch `04` (args are forwarded with `"$@"`), e.g.:  
   `bash 04_run_stack.sh fcu_url:=/dev/ttyUSB0:921600`

3. **Flight controller TELEM2 → Jetson UART (Micro XRCE-DDS).**  
   Default: `xrce_args:="serial --dev /dev/ttyTHS1 -b 921600"`  
   Check: `ls /dev/ttyTHS*` — change `ttyTHS1` if your board uses another.  
   In QGC, set TELEM2 to 921600 to match.

4. **Before flight, verify:**  
   - You are in `dialout` (log out/in once after `01`).  
   - `bash 04_run_stack.sh` is running and stays up.  
   - `/mavros/local_position/odom` publishes (`06` checks this for 20 s).  
   - Intrinsics file exists: `$WS_ROOT/.ego_hw/zed_intrinsics.yaml`
     (written by `05`; `04` warns if missing).

---

## 2) Script order

| Step | Script | What it really does |
| --- | --- | --- |
| 0 | `00_bootstrap.sh` | Jetson-only. Runs `01` (sudo) then `02`. Exit if not on Jetson / if run as root. |
| 1 | `01_sudo_install.sh` | Once with sudo: ROS 2 Humble (+ rviz2), MAVROS, GeographicLib, CUDA/nvcc bits, **ZED SDK** (~5.5), adds you to `dialout`. |
| 2 | `02_build.sh` | No apt. Builds `ros2_ws` (px4_msgs), MicroXRCEAgent, `ego_ws`, `px4_ego_ws` (+ `sim-sev/patches/px4_ego` takeoff patch), `frontier_explorer`, `zed_ws`. |
| 3 | `03_env.sh` | Sourced by later scripts. Sets `WS_ROOT`, sources Humble + every workspace. Saves `-u`, does `set +u` before ROS `setup.bash`, restores `set -u` after (lines 7–14). |
| 4 | `04_run_stack.sh` | Every flight. Sources `03`, launches `sim-sev/hardware.launch.py` with intrinsics file + **`map_size_x:=10.0 map_size_y:=10.0`** (line 43, already applied). Starts ZED + MAVROS + XRCE + EGO + bridge; explorer stays off. Extra args (`fcu_url:=…`) pass through. |
| 5 | `05_capture_intrinsics.sh` | Once per camera/resolution. Stack (`04`) must be up with ZED on VGA. Reads `/zed/zed_node/depth/camera_info`, writes `$WS_ROOT/.ego_hw/zed_intrinsics.yaml`. Rejects non-VGA. Restart `04` if EGO complained about missing intrinsics. |
| 6 | `06_run_demo.sh` | Every flight. Manual confirms for takeoff / hover / offboard / start explorer, then **autonomous** frontier goals, then land + disarm. |

First time on the Jetson:

```bash
cd ~/dev/ProjTeam4Fall2026/frontier-explorer/sim-sev/jetson-runner   # or your clone path
bash 00_bootstrap.sh
# log out/in once for dialout
```

Every flight (two terminals):

```bash
# Terminal 1
bash 04_run_stack.sh

# Once, with ZED already up under VGA — then restart 04 if needed
bash 05_capture_intrinsics.sh

# Terminal 2
bash 06_run_demo.sh
```

---

## 3) `06_run_demo.sh` flow (current file)

Constants (top of script): `MAX_RADIUS=8.0`, `MAP_SIZE=10.0`,
`ARRIVE_DIST=0.6`, `GOAL_TIMEOUT=25`.

1. **Odom check** — waits up to 20 s for `/mavros/local_position/odom`. Fails with a hint to start `04` if missing.
2. **STEP 1 TAKEOFF** — `confirm`, then `pub_key t 8` (arm + takeoff). Sets `FLYING=1`.
3. **Hovering stable?** — another `confirm` (Enter only to proceed).
4. **STEP 2 OFFBOARD** — `confirm` (line 170), then **`pub_key o 8` (line 171)**. Must be before explorer.  
   Known issue: explorer before `o` crashes — see `sim-sev/KNOWN_ISSUES.md`.
5. **STEP 3 START EXPLORER** — `confirm`, then starts `explorer_node` in the background with depth/odom topics, `map_size_x/y:=$MAP_SIZE`, FOV from the intrinsics file (fallback 73°).
6. **Autonomous loop** — sends the first goal right away (`/frontier/go_best`).  
   Next goal when within **`ARRIVE_DIST=0.6` m** of the current goal, or after **`GOAL_TIMEOUT=25` s** (explorer marks that goal failed and skips it).  
   If no `/frontier/best_goal` yet, retries about every **3 s**.  
   While the loop runs you can still type `p` / `t` / `l` + Enter to take over.

### `confirm()` (lines 133–152)

- **Empty Enter** → proceed.  
- **`p` / `t` / `l`** → only while `FLYING=1`; otherwise prints "Not flying" and asks again.  
  After `p`/`t`, same prompt again. After `l`, lands then waits for `d` to disarm.  
- **Anything else** (`yes`, `y`, …) → re-asks. Never proceeds or aborts on its own.  
- **Ctrl+C** while flying → hover, wait 3 s, land (see Safety).

---

## 4) Safety

| Action | What happens |
| --- | --- |
| `p` | Position hover — freeze current x/y/z. Stops explorer. |
| `t` | Takeoff-mode hover — hold x/y, climb **~0.9 m** each time (per `06` comments; see checklist about the 2 m patch). Stops explorer. |
| `l` | Land in place, then type **`d`** on the ground to disarm. |
| Geofence | `MAX_RADIUS=8.0` m from odom origin. Goal outside → not sent, position hover, loop stops, land prompt. No separate min/max x/y. |
| Ctrl+C / TERM / HUP while flying | Position hover → 3 s → land. Then disarm with `d` from any terminal if needed. |
| Script error (non-zero, not 130) while flying | Same safe stop. |
| Map size | `MAP_SIZE=10.0` in `06` **and** `map_size_x:=10.0 map_size_y:=10.0` on **`04` line 43 — DONE**. They must stay matched. (Launch defaults in `hardware.launch.py` are still 40.0; `04` overrides them.) |
| Height | No height geofence in these scripts. EGO `map_size_z` default is 4.0 m; `ceil` default 2.2 m. |
| PX4 geofence (`GF_*`) | Not set in-repo. Configure in QGC if you want it; may not engage indoors without GPS. |

**Order that must not be broken:** takeoff (`t`) → stable hover → offboard (`o`) → *then* explorer. Explorer before `o` crashes.

---

## 5) RViz (optional, separate terminal)

Comment block in `04_run_stack.sh` (lines 8–30). Do **not** use `rviz:=true`.

```bash
source sim-sev/jetson-runner/03_env.sh
rviz2 -d "$(ros2 pkg prefix frontier_explorer)/share/frontier_explorer/rviz/frontier.rviz"
```

- **Bench:** on the Jetson with a monitor.  
- **Flights:** on the Ubuntu laptop, **same `ROS_DOMAIN_ID`** as the Jetson (`echo $ROS_DOMAIN_ID`), so the Jetson GPU stays free for ZED + EGO.  
Explored cloud: `/frontier/map_cloud`.

---

## 6) Uncommitted on Fedora → must reach the Jetson

On this Fedora checkout these are modified

- `sim-sev/jetson-runner/02_build.sh`
- `sim-sev/jetson-runner/03_env.sh`
- `sim-sev/jetson-runner/04_run_stack.sh`
- `sim-sev/jetson-runner/05_capture_intrinsics.sh`
- `sim-sev/jetson-runner/06_run_demo.sh`
- (plus this README once updated)

Copy or commit+pull onto the Jetson clone at  
`~/dev/ProjTeam4Fall2026/frontier-explorer`, then:

1. Re-run **`02_build.sh`** (picks up frontier_explorer / patches).  
2. Re-run **`05_capture_intrinsics.sh`** with the ZED up under VGA.  
3. Use the updated **`04`** / **`06`** for the flight.

---

## 7) `03_env.sh` unbound-variable guard

```bash
_HAD_U=0; [[ $- == *u* ]] && _HAD_U=1; set +u   # line 7
source /opt/ros/humble/setup.bash                 # line 8
# … workspace sources …
if [[ $_HAD_U == 1 ]]; then set -u; fi            # line 14
```

ROS `setup.bash` trips bash `set -u`; this saves the flag, disables `-u` for the sources, then restores it.

---

## 8) Before-flying checklist (still open)

- [ ] Scripts 02–06 (+ this README) on the Jetson; `02` rebuilt; `05` recaptured.  
- [ ] `04` line 43 still has `map_size_x:=10.0 map_size_y:=10.0` matching `MAP_SIZE=10.0` in `06`.  
- [ ] Props-off bench run of `06`: odom check, STEP 1–3 confirms (Enter only), **auto goal loop**, `p`/`t`/`l` takeover, **Ctrl+C** hover-then-land.  
- [ ] Confirm takeoff climb on the **Jetson** bridge copy: Fedora `02` applies `sim-sev/patches/px4_ego/0101-…` (takeoff **2 m** above current). `06` comments still say **~0.9 m** for re-entering `t` mid-flight — verify which build is on the Jetson before the class demo.  
- [ ] Kill switch in hand for any props-on run. Area clear.

---

## Env knobs (optional)

`ZED_SDK_VERSION`, `ZED_SDK_URL`, `ZED_WRAPPER_REF`, `PX4_MSGS_BRANCH`,
`COLCON_WORKERS`, `SKIP_ZED_SDK=1`, `WS_ROOT`.
