# Jetson runner (sim-sev only)

Numbered scripts — run in order.

| Step | Script | When |
| --- | --- | --- |
| 0 | `00_bootstrap.sh` | First time: does 01 + 02 |
| 1 | `01_sudo_install.sh` | Once (sudo): ROS, MAVROS, **ZED SDK**, dialout |
| 2 | `02_build.sh` | Once (or re-run): build workspaces |
| 3 | `03_env.sh` | Sourced by later scripts (workspaces) |
| 4 | `04_run_stack.sh` | Every flight: ZED + MAVROS + XRCE + EGO + bridge |
| 5 | `05_capture_intrinsics.sh` | Once per camera/resolution (stack must be up) |
| 6 | `06_run_demo.sh` | Every flight: manual takeoff → explorer → land |

## First time on the Jetson

```bash
cd ~/frontier-explorer/sim-sev/jetson-runner
bash 00_bootstrap.sh
```

Log out/in once for `dialout`. Wire FC USB, TELEM2 UART, ZED USB 3. Set QGC TELEM2 / 921600.

## Every flight

Terminal 1:
```bash
bash 04_run_stack.sh
```

First time after ZED is up (Terminal 3), then restart 04 if needed:
```bash
bash 05_capture_intrinsics.sh
```

Terminal 2:
```bash
bash 06_run_demo.sh
```

## Notes

- Edits stay under `sim-sev/` only. `02_build.sh` **reads** `sim/patches` but does not modify them.
- `02_build.sh` then applies extra px4_ego patches from `sim-sev/patches/px4_ego/` (e.g. `0101-…` = take off to 2 m above start instead of fixed 0.9 m). Re-run `02` to pick it up on an existing build.
- Original helper also remains at `../live-demo/run_demo.sh` (unchanged).
- Env knobs: `ZED_SDK_VERSION`, `ZED_SDK_URL`, `ZED_WRAPPER_REF`, `PX4_MSGS_BRANCH`, `COLCON_WORKERS`, `SKIP_ZED_SDK=1`.
