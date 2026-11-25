# Gazebo sim on the Jetson

Runs the same Gazebo sim we use in WSL (`sim/`) on the Jetson Orin Nano. The sim gets its own
home folder, `~/jetson-sim`, so its PX4, px4_msgs, EGO and MAVROS builds don't touch the
hardware build in your real home. That matters because the sim needs a newer px4_msgs than the
drone's PX4 1.15, and both setups use `~/ros2_ws`.

## What's different from WSL

In WSL you did step 0 of `sim/README.md` by hand. `setup.sh` does it for you:

- Adds the Gazebo apt repo and installs Gazebo Harmonic and `ros-humble-ros-gzharmonic`
  (PX4's setup script did this in WSL)
- Clones PX4 at the tested commit (860aca9864), runs its setup without the flight-controller
  compiler, and builds the SITL binary
- Builds px4_msgs at the matching commit (d49263b) in the sim's own `~/ros2_ws`
- Uses the XRCE agent `hw/2_jetson_setup.sh` already installed, or builds v2.4.2 if it's missing
- Builds with 2 jobs at a time, so the 8 GB Orin Nano doesn't run out of memory
- Then runs `sim/1_sudo_install.sh` and `sim/2_user_setup.sh` like in WSL

## Install (once, about 1.5 to 2 hours)

Needs ROS 2 Humble, so run `sudo bash hw/1_jetson_sudo.sh` first if you haven't. Plug in a
monitor for Gazebo and RViz. Have about 30 GB free (`df -h ~`).

```bash
cd ~/frontier-explorer
bash sim/jetson/setup.sh 2>&1 | tee ~/jetson_sim_setup.log
```

It asks for your password a few times. Safe to re-run if a step fails.

## Run it

Every sim command goes through `run.sh`:

```bash
bash sim/jetson/run.sh sim/e2e_test.sh 4.0 2.0    # headless check, ~3 min
bash sim/jetson/run.sh sim/demo.sh                # Gazebo + RViz on the Jetson's monitor
bash sim/jetson/run.sh sim/frontier_demo.sh       # the frontier explorer demo
bash sim/jetson/run.sh                            # a shell in the sim env (type exit to leave)
```

Stop the demo with `bash sim/jetson/run.sh sim/demo_stop.sh`. Don't use `sim/launch_all.sh`:
its new terminal tabs don't get the sim's home folder.

## If something goes wrong

| Problem | Fix |
|---|---|
| Build killed partway (out of memory) | Re-run setup with `MAKEFLAGS=-j1`. Check swap with `free -h` |
| `ros-humble-ros-gzharmonic is not available` | Send the log; the depth bridge needs it |
| Gazebo or RViz window doesn't open | Run from a terminal on the Jetson's own desktop, not SSH |
| The sim is very slow or EGO says "odom or depth lost" | Close other apps. `sim/demo.sh` already allows 5 s without a setpoint |
| You want to delete the sim | `rm -rf ~/jetson-sim`. The hardware build isn't affected |
