#!/usr/bin/env bash
# Sends the drone to the frontier explorer's best goal, waits until it gets there, and repeats.
# Needs a running frontier demo or test (explorer_node up, drone in offboard).
# Usage: bash sim/frontier_go.sh [steps]     (default 1)
# Exit: 0 = every goal reached, 1 = no goal to send, 2 = a goal was not reached in time
REPO=$(cd "$(dirname "$0")/.." && pwd)
source /opt/ros/humble/setup.bash
source ~/mavros_ws/install/setup.bash
source $REPO/install/setup.bash
STEPS=${1:-1}
xy() { timeout 5 ros2 topic echo /mavros/local_position/odom --once --field pose.pose.position 2>/dev/null | awk '/^x:/{x=$2}/^y:/{y=$2}/^z:/{z=$2}END{if(x!="")printf "%.2f %.2f %.2f",x,y,z}'; }

for s in $(seq 1 $STEPS); do
  out=$(timeout 15 ros2 service call /frontier/go_best std_srvs/srv/Trigger 2>&1)
  msg=$(echo "$out" | grep -oE "message='[^']*'" | cut -d"'" -f2)
  if ! echo "$out" | grep -q "success=True"; then
    echo "[go] step $s: ${msg:-no answer from explorer_node (is the frontier demo running?)}"; exit 1
  fi
  read gx gy <<< "$(echo "$msg" | awk '{print $2, $3}')"
  echo "[go] step $s/$STEPS: flying to ($gx, $gy)"
  start=$SECONDS; reached=no
  while [ $((SECONDS - start)) -lt 45 ]; do
    sleep 1
    p=$(xy)
    if [ -n "$p" ] && awk -v p="$p" -v gx=$gx -v gy=$gy 'BEGIN{split(p,a," "); exit !((a[1]-gx)^2+(a[2]-gy)^2 < 0.36 && a[3] > 0.25 && a[3] < 2.0)}'; then
      reached=yes; break
    fi
  done
  status=$(timeout 5 ros2 topic echo /frontier/status --once --field data 2>/dev/null | head -1)
  if [ $reached = yes ]; then
    echo "[go]   reached in $((SECONDS - start)) s at ($p)   $status"
  else
    echo "[go]   NOT reached after 45 s, drone at (${p:-no odometry})   $status"; exit 2
  fi
done
exit 0
