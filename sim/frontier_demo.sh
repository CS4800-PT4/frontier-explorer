#!/usr/bin/env bash
# GUI demo of the frontier explorer (R1): the warehouse demo plus explorer_node.
# RViz shows the explored map (light blue = seen and free, dark gray = obstacle, blank = not
# seen yet), frontier cells (orange), frontier goals (blue) and the goal it would pick (green).
# Fly around with 2D Goal Pose, or let the explorer pick: bash sim/frontier_go.sh 5
# Stop with: bash sim/demo_stop.sh
# Usage: bash sim/frontier_demo.sh   (GZ_WORLD=default for the small EGO world)
export FRONTIER=1 GZ_WORLD=${GZ_WORLD:-default_warehouse}
exec bash "$(dirname "$0")/demo.sh"
