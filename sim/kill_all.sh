#!/usr/bin/env bash
# Force-stop every piece of the sim stack (no param restore). Use when demo_stop.sh hangs.
pkill -9 -f "[d]emo.sh"; pkill -9 -f "[e]2e_test.sh"
pkill -9 -f "[r]os2 launch"; pkill -9 -f "[s]imulation-gazebo"; pkill -9 -f "[g]z sim"
pkill -9 -f "[r]viz2"; pkill -9 -f "[b]in/px4 "; pkill -9 -f "[m]avros_node"; pkill -9 -f "[M]icroXRCEAgent"
pkill -9 -f "[o]ffboard_control_test"; pkill -9 -f "[e]go_planner_node"; pkill -9 -f "[t]raj_server"
pkill -9 -f "[d]epth_gz_bridge"; pkill -9 -f "[s]tatic_transform_publisher"; pkill -9 -f "[p]arameter_bridge"
pkill -9 -f "[r]os2 topic"; pkill -9 -f "[r]os2 param"
sleep 2
pgrep -af "[g]z sim|[r]viz2|[b]in/px4 |[m]avros_node|[e]go_planner|[r]os2 launch|[M]icroXRCE" || echo "all stopped"
