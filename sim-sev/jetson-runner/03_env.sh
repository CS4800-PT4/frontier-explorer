#!/usr/bin/env bash
# Source every workspace this runner builds. Safe to source from run scripts.
_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_REPO=$(cd "$_HERE/../.." && pwd)
# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
[ -f "$HOME/ros2_ws/install/setup.bash" ] && source "$HOME/ros2_ws/install/setup.bash"
[ -f "$HOME/ego_ws/install/setup.bash" ] && source "$HOME/ego_ws/install/setup.bash"
[ -f "$HOME/px4_ego_ws/install/setup.bash" ] && source "$HOME/px4_ego_ws/install/setup.bash"
[ -f "$HOME/zed_ws/install/setup.bash" ] && source "$HOME/zed_ws/install/setup.bash"
[ -f "$_REPO/install/setup.bash" ] && source "$_REPO/install/setup.bash"
export FRONTIER_REPO="$_REPO"
export SIM_SEV="$_HERE/.."
