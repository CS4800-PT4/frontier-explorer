#!/usr/bin/env bash
# Source every workspace this runner builds. Safe to source from run scripts.
_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_REPO=$(cd "$_HERE/../.." && pwd)
export WS_ROOT="${WS_ROOT:-$(cd "$_REPO/.." && pwd)}"
# shellcheck disable=SC1091
_HAD_U=0; [[ $- == *u* ]] && _HAD_U=1; set +u
source /opt/ros/humble/setup.bash
[ -f "$WS_ROOT/ros2_ws/install/setup.bash" ] && source "$WS_ROOT/ros2_ws/install/setup.bash"
[ -f "$WS_ROOT/ego_ws/install/setup.bash" ] && source "$WS_ROOT/ego_ws/install/setup.bash"
[ -f "$WS_ROOT/px4_ego_ws/install/setup.bash" ] && source "$WS_ROOT/px4_ego_ws/install/setup.bash"
[ -f "$WS_ROOT/zed_ws/install/setup.bash" ] && source "$WS_ROOT/zed_ws/install/setup.bash"
[ -f "$_REPO/install/setup.bash" ] && source "$_REPO/install/setup.bash"
if [[ $_HAD_U == 1 ]]; then set -u; fi
export FRONTIER_REPO="$_REPO"
export SIM_SEV="$_HERE/.."
