#!/usr/bin/env bash
# Collects what is needed to debug the drone stack into one text file, to pass on:
# the Jetson, CUDA, ZED SDK and camera, ROS 2 and the packages it finds, our workspaces and
# their git versions, the serial ports, recent kernel errors (USB, out of memory), the output
# of the last stationary_setup.sh / stationary_test.sh runs, and the last ros2 launch log.
# If the stack is running, it also records the live nodes, topics and rates.
# It only reads: no sudo, no installs, nothing started or stopped. It doesn't record IP
# addresses or the full environment (only ROS/CUDA variables).
# Usage: bash hw/collect_info.sh        (best while hw/stationary_test.sh is running, or
#                                         right after something failed)
#   LIVE=0          skip the live ROS checks
#   FE_WS=~/fe_ws   where hw/stationary_setup.sh put things
FE_WS=${FE_WS:-$HOME/fe_ws}
REPO=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$FE_WS/reports"
OUT=$FE_WS/reports/report_$(date +%m%d_%H%M%S).txt

if [ -f "$FE_WS/env.sh" ]; then
  # shellcheck disable=SC1091
  source "$FE_WS/env.sh" 2>/dev/null
elif [ -f /opt/ros/humble/setup.bash ]; then
  source /opt/ros/humble/setup.bash
fi

sec() { printf '\n===== %s =====\n' "$*"; }
# Runs a command line with a time limit and keeps at most MAX lines of its output
run() {  # [max_lines] command_line
  local max=60
  if [[ $1 =~ ^[0-9]+$ ]]; then max=$1; shift; fi
  echo "\$ $1"
  timeout 20 bash -c "$1" 2>&1 | head -n "$max"
}
show() {  # file [lines]   last lines of a file, if it exists
  [ -f "$1" ] || return
  echo "--- $1 (last ${2:-80} lines)"
  tail -n "${2:-80}" "$1"
}
# Explorer status lines ("... failed=0") are left out of these searches
ERRS='error|fatal|exception|traceback|failed|segmentation|core dumped|died|not found|refus|denied|timed? ?out|!!!|FAIL'

{
echo "collect_info report, $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "repo: $REPO   FE_WS: $FE_WS"

sec "System"
run "uname -srm"
run "grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release"
run "cat /etc/nv_tegra_release"
run "dpkg-query -W -f='\${Package} \${Version}\n' nvidia-jetpack nvidia-l4t-core 2>/dev/null"
run "cat /proc/device-tree/model 2>/dev/null | tr -d '\0'; echo"
run "nproc; free -h"
run "df -h / $HOME"
run "uptime"
run 3 "timeout 3 tegrastats --interval 1000 2>/dev/null | head -2"
run "ls /etc/nvpmodel.conf >/dev/null 2>&1 && nvpmodel -q 2>/dev/null"

sec "CUDA"
run "ls -d /usr/local/cuda* 2>/dev/null"
run "/usr/local/cuda/bin/nvcc --version 2>/dev/null | tail -2"

sec "ZED SDK and camera"
run "ls /usr/local/zed 2>/dev/null"
run "grep -rhoE 'define ZED_SDK_(MAJOR|MINOR|PATCH)_VERSION +[0-9]+' /usr/local/zed/include 2>/dev/null"
run "lsusb 2>/dev/null | grep -iE '2b03|stereolabs|zed' || echo 'no ZED on USB (vendor 2b03)'"
run "lsusb -t 2>/dev/null | grep -iE 'video|5000M|10000M' | head -10"
run "ls -l /dev/video* 2>/dev/null"
run "ls ~/zed 2>/dev/null; ls /usr/local/zed/settings 2>/dev/null"

sec "Serial ports (flight controller)"
run "ls -l /dev/ttyACM* /dev/ttyUSB* /dev/ttyTHS* 2>/dev/null"
run "id -nG"

sec "ROS 2"
run "env | grep -E '^(ROS_|RMW_|AMENT_PREFIX_PATH|COLCON_PREFIX_PATH|CYCLONEDDS|FASTRTPS|CUDA|LD_LIBRARY_PATH)' | sort"
run "dpkg-query -W -f='\${Package} \${Version}\n' 'ros-humble-ros-base' 'ros-humble-desktop' 'ros-humble-rviz2' \
  'ros-humble-cv-bridge' 'ros-humble-pcl-conversions' 'ros-humble-mavros' 'ros-humble-rmw-*' python3-colcon-common-extensions 2>/dev/null"
run "dpkg-query -W 'ros-humble-*' 2>/dev/null | wc -l | sed 's/$/ ros-humble packages installed/'"
for p in zed_wrapper zed_msgs ego_planner frontier_explorer px4_ego_py mavros px4_msgs; do
  printf '%-18s %s\n' "$p" "$(timeout 10 ros2 pkg prefix "$p" 2>/dev/null || echo 'not found')"
done

sec "Our setup ($FE_WS)"
run "ls -la $FE_WS"
run "cat $FE_WS/env.sh"
run "cat $FE_WS/apt_added.txt"
run "cat $FE_WS/zed_intrinsics.yaml ~/.ego_hw/zed_intrinsics.yaml"
run "cd $REPO && git log --oneline -3 && git status -sb | head -15"
for d in "$FE_WS/ego_ws/src/ego-swarm-ros2" ~/ego_ws/src/ego-swarm-ros2 "$FE_WS/zed_ws/src/zed-ros2-wrapper" \
         ~/zed_ws/src/zed-ros2-wrapper ~/px4_ego_ws/src/px4_ego; do
  [ -d "$d/.git" ] && run "cd $d && echo \$PWD && git describe --tags --always && git branch --show-current && git log --oneline -6"
done
ZPFX=$(timeout 10 ros2 pkg prefix zed_wrapper 2>/dev/null)
if [ -n "$ZPFX" ]; then
  ZSRC=$(cd "$ZPFX/../.." 2>/dev/null && pwd)/src
  run "find $ZSRC -maxdepth 2 -name .git -execdir sh -c 'echo \$PWD; git describe --tags --always' \; 2>/dev/null"
  run 40 "grep -A3 -E 'grab_resolution|grab_frame_rate|pos_tracking_enabled' $ZPFX/share/zed_wrapper/config/common*.yaml 2>/dev/null"
fi

sec "Kernel messages (USB, out of memory, crashes)"
run 40 "journalctl -k -b --no-pager 2>/dev/null | grep -iE 'oom|killed process|usb.*(error|disconnect|reset)|uvc|2b03|segfault|nvgpu.*error' | tail -40 \
  || echo 'no access to kernel log (that needs the adm group)'"

sec "Script runs"
L=$(ls -td "$FE_WS"/logs/setup_*.log 2>/dev/null | head -1)
[ -n "$L" ] && show "$L" 60
L=$(ls -td "$FE_WS"/logs/*/ 2>/dev/null | head -1)
if [ -n "$L" ]; then
  echo "latest test run: $L"
  run "ls -la $L"
  show "$L/run.log" 80
  for f in "$L"/*.log; do
    [ "$(basename "$f")" = run.log ] && continue
    echo "--- errors and warnings in $f"
    grep -aiE "$ERRS|warn" "$f" | grep -v "known_m2=" | tail -25
    show "$f" 40
  done
fi
show ~/setup2.log 40
L=$(ls -td ~/.ros/log/*/ 2>/dev/null | head -1)
[ -n "$L" ] && [ -f "$L/launch.log" ] && { echo "--- errors in $L/launch.log"; grep -aiE "$ERRS" "$L/launch.log" | grep -v "known_m2=" | tail -30; }

if [ "${LIVE:-1}" = 1 ]; then
  sec "Live ROS (what is running right now)"
  if [ -n "$(timeout 15 ros2 node list --no-daemon --spin-time 3 2>/dev/null)" ]; then
    run 80 "ros2 node list --no-daemon --spin-time 3"
    run 120 "ros2 topic list --no-daemon --spin-time 3 -t"
    for t in /zed/zed_node/depth/depth_registered /zed/zed_node/odom /mavros/local_position/odom; do
      echo "rate $t: $(timeout 8 ros2 topic hz "$t" 2>/dev/null | awk '/average rate/{r=$3}END{print (r=="") ? "none" : r " Hz"}')"
    done
    run 12 "ros2 topic echo /zed/zed_node/depth/camera_info --once --no-arr 2>/dev/null | grep -E '^(width|height|  frame_id)'"
    run 15 "ros2 topic echo /zed/zed_node/odom --once --no-arr 2>/dev/null | head -15"
    run 10 "ros2 topic echo /zed/zed_node/pose/status --once 2>/dev/null"
    run 5 "ros2 topic echo /drone_0_grid/grid_map/occupancy_inflate --once --no-arr 2>/dev/null | grep -E '^(width|  frame_id)'"
    run 5 "ros2 topic echo /frontier/status --once 2>/dev/null"
    run 5 "ros2 topic echo /mavros/state --once 2>/dev/null | grep -E 'connected|armed|mode'"
    run 30 "ros2 param get /zed/zed_node general.grab_resolution; ros2 param get /zed/zed_node general.grab_frame_rate"
  else
    echo "no ROS 2 nodes seen: nothing is running (or it uses a different ROS_DOMAIN_ID)"
  fi
fi
echo
echo "end of report"
} > "$OUT" 2>&1

echo "[collect] report saved: $OUT ($(wc -l < "$OUT") lines)"
echo "[collect] send it with RustDesk's file transfer, or copy it: cat $OUT"
