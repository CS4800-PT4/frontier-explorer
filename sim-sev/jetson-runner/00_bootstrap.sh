#!/usr/bin/env bash
# Git-runner entry: install (incl. ZED SDK) + build on the Jetson.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)

echo "=== jetson-runner bootstrap ==="
echo "Repo scripts live only under sim-sev/jetson-runner (plus read-only sim/patches)."

if [ ! -f /etc/nv_tegra_release ]; then
  echo "!!! Run this on the Jetson (no /etc/nv_tegra_release)."
  exit 1
fi
echo "Jetson: $(head -n1 /etc/nv_tegra_release)"

if [ "${EUID:-}" -eq 0 ]; then
  echo "Don't run bootstrap as root. It will call sudo for step 1."
  exit 1
fi

echo "--- step 1/2: sudo install (ROS, MAVROS, ZED SDK) ---"
sudo bash "$HERE/01_sudo_install.sh"

echo "--- step 2/2: build workspaces ---"
bash "$HERE/02_build.sh"

echo "=== bootstrap finished. Log out/in once for dialout, then: bash $HERE/04_run_stack.sh ==="
