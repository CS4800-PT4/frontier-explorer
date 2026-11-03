# Jetson live-demo dry-run notes

Repo clone on Fedora includes Ubuntu-local work copied into `sim-sev/` (jetson-runner, patches, demo script edits). Nothing in this file was pushed to GitHub unless you push it later.
---

## 1) `02_build.sh` dry-run

| Check | Result |
| --- | --- |
| `bash -n 02_build.sh` (and `00`, `03`) | **PASS** — syntax OK |
| Full colcon dry-run on Fedora/Ubuntu desktop | **Not possible** without ZED SDK + CUDA + Jetson/Jammy arm64 host |

### Gates `02_build.sh` hits first (would stop before colcon)

1. **FAIL** — `/usr/local/zed` missing (ZED SDK)
2. **FAIL** — `/usr/local/cuda/bin/nvcc` missing
3. Then requires `sim/patches/{ego-swarm-ros2,px4_ego}` (present in the Fedora clone) and `source /opt/ros/humble/setup.bash`

### Workspaces the build creates (only in `02`, not in `00`/`01`)

| Path | Created by | Ubuntu desk status |
| --- | --- | --- |
| `~/ros2_ws` (`px4_msgs`) | `02_build.sh` | Present (install yes; src has other packages) |
| `~/Micro-XRCE-DDS-Agent` | `02` if agent missing | Source tree present; agent binary/libs broken when probed from Fedora |
| `~/ego_ws` | `02` | Present (install yes) |
| `~/px4_ego_ws` | `02` | **Missing** — Ubuntu still has older **`~/px4_ego`** |
| repo `frontier_explorer` colcon | `02` | Present under Ubuntu `~/frontier-explorer/install` |
| `~/zed_ws` | `02` | **Missing** |

`00_bootstrap.sh` does **not** clone workspaces; it only runs `01` then `02`. `01_sudo_install.sh` installs apt packages + ZED SDK + dialout — **no git clones**.

---

## 2) Sudo install checklist (Ubuntu 22.04 disk, not Jetson)

| Item | Result | Notes |
| --- | --- | --- |
| `packages.ros.org` jammy Humble | PASS (from Fedora network) | `ros-humble-ros-base`, `ros-humble-mavros` in amd64/arm64 indexes |
| `/etc/apt/sources.list.d/ros2.list` | PASS on Ubuntu; FAIL on Fedora | Ubuntu: `deb … packages.ros.org/ros2/ubuntu jammy main` |
| `ros-humble-ros-base` | PASS | `0.10.0-1jammy…` |
| `ros-humble-mavros` (+ extras) | PASS | `2.16.0-1jammy…` |
| Most other `01` apt ROS/dev deps | PASS | pcl, cv-bridge, colcon, rosdep, etc. |
| `ros-humble-ament-cmake-google-benchmark` | **FAIL** | Not installed on Ubuntu |
| GeographicLib (`libgeographic-dev`, `geographiclib-tools`) | **PASS** | `1.52-1` |
| GeographicLib datasets (`…/geoids`, egm96) | **PASS** | `egm96-5.pgm` present |
| CUDA / `nvcc` / `/usr/local/cuda` | **FAIL** | No jetpack/cuda packages; expected via JetPack on Jetson |
| ZED SDK `/usr/local/zed` (script default **5.5**) | **FAIL** | Must install on Jetson via `01` |
| `sev` in `dialout` | **FAIL** on Ubuntu | Group exists; user not a member |
| `MicroXRCEAgent` | **Partial / FAIL** | Binary under `/usr/local/bin`; shared libs broken when run off-rootfs |

Fedora: no apt, no Humble, no ZED/CUDA — live stack is **not** meant to run there.

---

## 3) Fresh Jetson tomorrow — issues and fixes

### Bring-up order

1. Clone/copy this repo onto the Jetson (include `sim-sev/jetson-runner`).
2. **`bash 00_bootstrap.sh`** (preferred) — requires Jetson (`/etc/nv_tegra_release`), non-root; runs **`01_sudo_install.sh`** then **`02_build.sh`**.
   - Or run `sudo bash 01_sudo_install.sh` then `bash 02_build.sh` separately.
3. Log out/in once for **`dialout`**.
4. Wire ZED USB3, FC USB/UART, TELEM2 @ 921600 as in class handout.
5. Every flight: Terminal 1 **`04_run_stack.sh`** (leave it up).
6. Once (ZED up): Terminal 3 **`05_capture_intrinsics.sh`** → `~/.ego_hw/zed_intrinsics.yaml`; restart 04 if EGO complained.
7. Terminal 2 **`06_run_demo.sh`** with **04 still running**.

### What `01` must deliver on Jetson

- ROS 2 apt source (`ros2.list`) + Humble packages (ros-base, mavros, …)
- GeographicLib tools/dev + geoid datasets (script installs if missing)
- CUDA / `nvcc` via JetPack packages
- **ZED SDK 5.5** under `/usr/local/zed` (override with `ZED_SDK_VERSION` / `ZED_SDK_URL` if L4T differs)
- Add user to **`dialout`**

### What `02` must create

- `~/ros2_ws`, `~/ego_ws`, **`~/px4_ego_ws`** (not the old `~/px4_ego` name), **`~/zed_ws`**, plus repo `install/` for `frontier_explorer`
- Applies `sim/patches` and `sim-sev/patches/px4_ego` (2 m takeoff patch)

If an old `~/px4_ego` exists from sim day, still let `02` build **`~/px4_ego_ws`**; `03_env.sh` sources `~/px4_ego_ws/install/setup.bash`. Prefer `06_run_demo.sh` over `live-demo/run_demo.sh` (the latter still mentions `~/px4_ego` in its source lines).

### Known runtime issues (already documented / patched here)

| Issue | Fix |
| --- | --- |
| Starting Explorer **before** offboard `o` crashes | See [`../KNOWN_ISSUES.md`](../KNOWN_ISSUES.md). `06_run_demo.sh` and `../live-demo/run_demo.sh` now do **t → o → explorer**. |
| Stopping `04` before `06` | **Do not.** `06` does not relaunch the stack; it needs `/mavros/local_position/odom` from MAVROS in `04`. |
| Intrinsics | `05` once with stack up → `~/.ego_hw/zed_intrinsics.yaml` |
| Map size | **40.0 m × 40.0 m** (`map_size_x` / `map_size_y`); set in `06_run_demo.sh` and defaults in `../hardware.launch.py` (`map_size_z` default **4.0** m) |
| Camera mount offset | `cam_x` / `cam_y` / `cam_z` / `cam_pitch_deg` in `hardware.launch.py` (default **0.0**); measure on airframe |

### Jetson reachability (desk check)

- Not connected as a Grok machine; SSH to `10.145.158.205` failed from home Fedora.
- Tomorrow: get Jetson on network, SSH in, then re-run the PASS/FAIL list on-device (`/usr/local/zed`, `nvcc`, workspaces, `ros2.list`, `groups`, `ldd $(which MicroXRCEAgent)`).

---

## Quick command cheat sheet

```bash
cd ~/frontier-explorer/sim-sev/jetson-runner
bash 00_bootstrap.sh          # first time on Jetson
# log out/in for dialout

bash 04_run_stack.sh          # terminal 1 — leave running
bash 05_capture_intrinsics.sh # once, ZED up
bash 06_run_demo.sh           # terminal 2 — t, o, explorer, p, l, d
```

Mode keys in `06`: **t** takeoff/arm · **o** offboard (before explorer) · **p** hover here (stops explorer) · **l** land · **d** disarm.

---

## Debian box — packages.ros.org / Humble index (2026-11-02 night)

Verification on Grok Bot Debian (Trixie), **fetch only — do not install Humble here**.

| Check | Result |
| --- | --- |
| DNS / egress | `packages.ros.org` → `198.18.0.1` (runner egress) |
| Strict HTTPS | **FAIL** curl 60 — cert is `CN=*.osuosl.org` (SAN mismatch via proxy) |
| Plain HTTP | **FAIL** HTTP 500 |
| Index via `curl -k` | **PASS** — jammy `Packages.gz` arm64 (~1.8 MB) and amd64 (~1.9 MB) |
| `ros-humble-ros-base` | PASS in jammy arm64/amd64 indexes (`0.10.0-1jammy…`) |
| `ros-humble-mavros` (+ extras) | PASS (`2.16.0-1jammy…`) |
| `ros-humble-cv-bridge`, `pcl-ros`, `ament-cmake` | PASS |
| `ros-humble-ament-cmake-google-benchmark` | PASS in index (still may be missing on a given Ubuntu install) |
| Install on Debian | **Do not** — Jammy debs are for Ubuntu 22.04 / Jetson only |

Full log: box `/workspace/operations/ros-humble-verify/LATEST.txt` (not in this repo).

