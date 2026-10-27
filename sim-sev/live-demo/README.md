# Live demo — hardware (manual)

Everything for this demo lives under **`sim-sev/`** only.

**No Gazebo. No PX4 SITL.** Nothing takes off by itself. You confirm every step (or Ctrl+C to stop).

```text
takeoff (t) → start explorer → offboard (o) → hover here (p) → land here (l) → disarm (d)
```

---

## 0. Set YOUR hardware (do this first)

Plug in:

1. Flight controller → Jetson USB  
2. Flight controller TELEM2 → Jetson UART  
3. ZED → Jetson USB 3  

See what ports appeared:

```bash
ls /dev/ttyACM* /dev/ttyUSB* /dev/ttyTHS*
```

Then set these in **`sim-sev/hardware.launch.py`** (edit the defaults at the top of that file, or pass them on the launch line):

| What | Name | Our default | Change to if different |
|---|---|---|---|
| FC USB port + baud | `fcu_url` | `/dev/ttyACM0:57600` | e.g. `/dev/ttyUSB0:921600` |
| ZED model | `camera_model` | `zed2i` | `zed` / `zedm` / `zed2` / `zed2i` |
| Jetson UART for TELEM2 | `xrce_args` | `serial --dev /dev/ttyTHS1 -b 921600` | change `ttyTHS1` if `ls` shows another |

**Camera offset** (`cam_x` `cam_y` `cam_z`) — measure with a tape/ruler on the drone (meters):

- From the **flight controller** to the ZED’s **left lens** in meters (=0.10 is 10 cm)
- `cam_x` = forward (+) / aft (−)
- `cam_y` = left (+) / right (−)
- `cam_z` = up (+) / down (−)

Example: camera 10 cm in front of the FC and 5 cm above → `cam_x:=0.10 cam_y:=0.0 cam_z:=0.05`.  
If you haven’t measured yet, leave all at `0.0` for a first bench; set real numbers before trusting exploration near obstacles.

Example launch with your ports:

```bash
ros2 launch ~/frontier-explorer/sim-sev/hardware.launch.py \
  fcu_url:=/dev/ttyUSB0:921600 \
  camera_model:=zed2i \
  xrce_args:="serial --dev /dev/ttyTHS1 -b 921600"
```

You also need camera intrinsics once at `~/.ego_hw/zed_intrinsics.yaml` (EGO won’t start without them).

---

## 1. Start the stack (one terminal)

```bash
ros2 launch ~/frontier-explorer/sim-sev/hardware.launch.py
```

Starts ZED, MAVROS, XRCE, EGO, and the offboard bridge. Explorer stays off. Leave this terminal open.

Wait until MAVROS is connected and `/mavros/local_position/odom` is publishing. Kill switch in reach.

### Quick checks (other terminals)

```bash
ros2 topic echo /mavros/state --once
ros2 topic hz /mavros/local_position/odom
ros2 topic hz /zed/zed_node/depth/depth_registered
ros2 topic list | grep fmu
ros2 node list
```

---

## 2. Run the demo helper (second terminal)

```bash
cd ~/frontier-explorer/sim-sev/live-demo
bash run_demo.sh
```

Press **Enter** at each prompt:

| Prompt | What happens | Key |
|---|---|---|
| START / TAKEOFF | arm + climb + hold | `t` |
| (wait until stable) | you confirm hover | — |
| START EXPLORER | start explorer | — |
| OFFBOARD | follow explorer goals | `o` |
| HOVER HERE NOW? | stop explorer + freeze here | `p` |
| LAND HERE | descend in place | `l` |
| DISARM | stop motors | `d` |

- **`p`** = hold where you are  
- **`l`** = land where you are (controlled descent, not a drop)  
- **`d`** = disarm after it’s on the ground  
- **Ctrl+C** = stop the helper; use kill switch or send `p` / `l` / `d` yourself if still up  

Watch explorer:

```bash
tail -f ~/frontier-explorer/sim-sev/live-demo/explorer.log
ros2 topic echo /goal_pose
```

---

- You control every mode change  
- You can abort to hover (`p`) right after offboard  
- Land (`l`), then disarm (`d`) with props safe  
