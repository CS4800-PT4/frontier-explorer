# Clean install check

Runs `hw/1_jetson_sudo.sh` and `hw/2_jetson_setup.sh` on a brand-new Ubuntu 22.04 machine, the
same way the Jetson runs them, then checks the result. It catches anything that only built
before because it was already on someone's machine. Plan on about an hour, mostly waiting.

**Branch:** `fix-xrce-fastdds-tag` until PR #25 is merged, then `main`. Older copies of `main`
fail on the XRCE agent, so don't test those.

You need about 30 GB free, and 8 GB of RAM if you can. Doing this on the real Jetson? Read
[On the real Jetson](#on-the-real-jetson) first.

## Checklist

- [ ] 1. Make a clean VM
- [ ] 2. Get the code
- [ ] 3. Run part 1 (`exit: 0`)
- [ ] 4. Run part 2 (`exit: 0`)
- [ ] 5. Run the checks (nothing says MISSING or NOT RUNNING)
- [ ] 6. Post your results
- [ ] 7. Delete the VM

## 1. Make a clean VM

It has to be a fresh install. A VM that already has ROS on it proves nothing. Pick one:

- **Windows (easiest).** In PowerShell:
  ```powershell
  wsl --update
  wsl --install Ubuntu-22.04 --name fe-clean --location C:\wsl\fe-clean
  ```
  Make a username and password when it asks. To get back in later: `wsl -d fe-clean`. This is
  separate from any Ubuntu you already have. Never used WSL? First run PowerShell as
  administrator, run `wsl --install --no-distribution`, restart, then run the two commands above.
- **VMware or VirtualBox.** New VM from the Ubuntu 22.04 ISO with 4+ CPUs, 8 GB RAM and a 40 GB
  disk. On VirtualBox, tick "Skip Unattended Installation" and install Ubuntu by hand, or your
  user may not get sudo. Take a snapshot right after the install so you can start over.
- **Mac with an M chip.** UTM > Virtualize > Linux with `ubuntu-22.04.5-live-server-arm64.iso`,
  4+ CPUs, 8 GB RAM and a 40 GB disk. Tick "Install OpenSSH server", then SSH in from Terminal
  so you can paste commands and copy results, since this image has no desktop. This is the
  closest to the Jetson, since it's ARM too.

## 2. Get the code

In the VM's terminal:

```bash
sudo apt-get update && sudo apt-get install -y git python3-pytest
# once PR #25 is merged, drop "-b fix-xrce-fastdds-tag"
git clone -b fix-xrce-fastdds-tag https://github.com/CS4800-PT4/frontier-explorer.git ~/frontier-explorer
mkdir -p ~/build_logs
```

## 3. Run part 1

Installs ROS 2 Humble, MAVROS and the system packages.

```bash
cd ~/frontier-explorer
sudo bash hw/1_jetson_sudo.sh 2>&1 | tee ~/build_logs/1_sudo.log; echo "exit: ${PIPESTATUS[0]}"
```

It should end with `exit: 0`.

## 4. Run part 2

Builds px4_msgs, the XRCE agent, EGO with our patches, the px4_ego bridge and our package. This
is the long one. Stay nearby, because it asks for your password partway through to install the
agent.

```bash
cd ~/frontier-explorer
bash hw/2_jetson_setup.sh 2>&1 | tee ~/build_logs/2_setup.log; echo "exit: ${PIPESTATUS[0]}"
```

It should end with `exit: 0`. On a VM it also prints `ZED SDK not found` and
`ZED wrapper built: no`. That's expected, because a VM can't run the ZED SDK.

On a VM, ignore what the scripts tell you to do next (install the ZED SDK, log out, edit
`~/.bashrc`, go to `hw/README.md`). The checks below set up everything they need.

## 5. Run the checks

Copy this whole block. It takes about a minute, and it prints nothing for about 20 seconds near
the end, so give it time. It starts the agent and the planner for a few seconds each. Nothing can
fly, because no flight controller is connected and the bridge stays off.

```bash
cd ~/frontier-explorer
{
echo "commit: $(git log --oneline -1)"; uname -m; grep PRETTY /etc/os-release
echo "local changes: [$(git status --short | wc -l)]"
grep -h '_fastdds_tag' ~/Micro-XRCE-DDS-Agent/CMakeLists.txt
source /opt/ros/humble/setup.bash
for ws in ~/ros2_ws ~/ego_ws ~/px4_ego_ws ~/frontier-explorer; do source $ws/install/setup.bash; done
for p in px4_msgs ego_planner quadrotor_msgs px4_ego_py mavros frontier_explorer; do
  echo "$p: $(ros2 pkg prefix $p 2>/dev/null || echo MISSING)"; done
python3 -c "import px4_msgs.msg, quadrotor_msgs.msg; print('messages import: ok')"
(cd src/frontier_explorer && python3 -m pytest test -q | tail -1)
echo "--- XRCE agent"
which MicroXRCEAgent || echo "MicroXRCEAgent MISSING"
ldd $(which MicroXRCEAgent) | grep -E 'microxrcedds_agent|fastcdr|fastrtps|fastdds|not found'
timeout 5 MicroXRCEAgent udp4 -p 8888 > ~/build_logs/agent.log 2>&1; echo "agent exit: $? (want 124)"
echo "--- launch, planner and explorer"
timeout -s INT 25 ros2 launch sim-sev/hardware.launch.py zed:=false mavros:=false xrce:=false \
  bridge:=false vision:=false explorer:=true fx:=320 fy:=320 cx:=320 cy:=240 > ~/build_logs/launch.log 2>&1 &
sleep 18
for n in ego_planner_node traj_server extrinsic_node explorer_node; do
  pgrep -f "$n" >/dev/null && echo "$n: running" || echo "$n: NOT RUNNING"; done
wait
grep -a 'process has died' ~/build_logs/launch.log | grep -v 'exit code -2' || echo "crashes: none"
} 2>&1 | tee ~/build_logs/check.txt
```

What you want to see:

| Line | Good |
| --- | --- |
| `local changes` | `[0]` |
| `_fastdds_tag` | `set(_fastdds_tag v2.12.2)` |
| The six packages | a path on each, no MISSING |
| `messages import` | `ok` |
| pytest | `... passed`, no failures |
| Agent libraries | `libfastcdr.so.1.1.1` and `libfastrtps.so.2.12.2` from `/usr/local/lib`, no `not found` |
| `agent exit` | `124` (the timeout stopped it, so it was still running) |
| The four nodes | all `running` |
| `crashes` | `none` |

## 6. Post your results

Post the output of `cat ~/build_logs/check.txt` and what you ran on (WSL, VMware, VirtualBox or
Mac). If anything looks wrong, also attach `1_sudo.log`, `2_setup.log` and `launch.log`. On
Windows they're in File Explorer at `\\wsl$\fe-clean\home\<your username>\build_logs`.

## 7. Delete the VM

- **WSL:** `wsl --unregister fe-clean` in PowerShell. Make sure it says `fe-clean` and not your
  normal Ubuntu, because this deletes everything in it.
- **VMware, VirtualBox or UTM:** delete the VM.

## If something fails

Both scripts are safe to re-run, so fix the problem and run the same command again.

| What you see | What to do |
| --- | --- |
| `invalid reference: 2.12.x` | You're on an old copy. Get the branch at the top of this page. |
| `Could not get lock` | Ubuntu is updating itself. Wait a few minutes and run the same commands again. |
| `No such file or directory` on `hw/...` | You're in the wrong folder. Run `cd ~/frontier-explorer` first. |
| A compiler gets `Killed`, or `c++: fatal error: Killed signal` | Out of memory. Use the out of memory command below. |
| `wsl --install` doesn't know `--name` | Run `wsl --update` again, or use VMware or VirtualBox. |
| `sudo` fails or nothing is there to answer it | Run part 2 in a normal terminal, not in the background. |
| `symbol lookup error`, or `agent exit` isn't 124 | Don't work around it. Post `check.txt` and `agent.log`, because the drone starts the agent the same way. |
| Anything else | Post the end of the log. It's more useful than a summary. |

Out of memory command:

```bash
cd ~/frontier-explorer
MAKEFLAGS=-j2 bash hw/2_jetson_setup.sh 2>&1 | tee ~/build_logs/2_setup.log; echo "exit: ${PIPESTATUS[0]}"
```

## What this does and doesn't prove

It proves the scripts work from zero on Ubuntu 22.04 and Humble, the agent starts with ROS
sourced, and the planner and explorer start from the demo launch file.

It doesn't test:
- **The ZED wrapper.** It needs the ZED SDK and CUDA.
- **ARM,** unless you ran it on a Mac with UTM.
- **The flight controller link.** No XRCE or MAVROS traffic reaches PX4.
- **`run_demo.sh`.** The checks above only use its launch file.

Those get tested on the Jetson.

## On the real Jetson

The Jetson uses the same scripts with these differences. If someone else uses that Jetson, ask
them first, because part 1 changes the system.

1. Check the version: `cat /etc/nv_tegra_release` should say R36 (JetPack 6, Ubuntu 22.04).
2. Get the code. If `~/frontier-explorer` doesn't exist, run section 2. If it does, ask whoever
   owns it before changing branches, then run
   `sudo apt-get install -y git python3-pytest; mkdir -p ~/build_logs`.
3. Check what's already there: `command -v MicroXRCEAgent; ls -d ~/Micro-XRCE-DDS-Agent`. Part 2
   skips the agent if one is installed, so an older agent would stay in place. If either command
   prints something, stop and ask the team before part 2.
4. Run this before part 1, because part 1 installs that package if the CUDA toolkit is missing,
   and it may replace OpenCV:
   `sudo apt-get install -s nvidia-jetpack-dev | grep -E '^(Inst|Remv)' | grep -i opencv`.
   It changes nothing. If it prints any line, stop and post it to the team before part 1.
5. Run part 1, then log out and back in so the serial ports work.
6. Install the ZED SDK for your JetPack before part 2:
   https://www.stereolabs.com/developers/release
7. Check the flight controller's firmware in QGroundControl. Run part 2 with the wrapper release
   that matches the SDK, and if the firmware isn't 1.15, the matching messages too:
   `ZED_WRAPPER_REF=<tag> PX4_MSGS_BRANCH=release/1.15 bash hw/2_jetson_setup.sh`. It should end
   with `ZED wrapper built: yes`.
8. Run the checks in section 5, then carry on from section 2 of `hw/README.md` (wiring, PX4
   settings, intrinsics and the bench check).
