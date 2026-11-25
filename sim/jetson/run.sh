#!/usr/bin/env bash
# Run a sim command on the Jetson with the sim's own home folder (see env.sh).
#   bash sim/jetson/run.sh sim/e2e_test.sh 4.0 2.0
#   bash sim/jetson/run.sh sim/demo.sh
#   bash sim/jetson/run.sh            (a shell in the sim env; type exit to leave)
# Don't use sim/launch_all.sh here: its new terminal tabs don't get the sim's home folder.
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=env.sh
source "$HERE/env.sh"
[ -x "$SIM_HOME/PX4-Autopilot/build/px4_sitl_default/bin/px4" ] || {
  echo "!!! The sim isn't installed in $SIM_HOME yet. Run: bash $HERE/setup.sh"; exit 1; }
cd "$(cd "$HERE/../.." && pwd)" || exit 1
if [ $# = 0 ]; then exec bash; fi
case $1 in
  *launch_all.sh) echo "!!! Use sim/demo.sh instead (launch_all's tabs lose the sim home folder)"; exit 1 ;;
  *.sh) exec bash "$@" ;;
  *) exec "$@" ;;
esac
