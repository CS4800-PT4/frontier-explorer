#!/usr/bin/env bash
# Install the Gazebo sim on the Jetson Orin Nano (JetPack 6, Ubuntu 22.04, ARM64).
# Does the WSL README's step 0 (PX4, px4_msgs, XRCE agent) automatically, then runs
# sim/1_sudo_install.sh and sim/2_user_setup.sh, all inside SIM_HOME (default ~/jetson-sim).
# Run as your normal user (it asks for sudo when needed). Safe to re-run. Takes 1.5 to 2 h.
#   Usage: bash sim/jetson/setup.sh 2>&1 | tee ~/jetson_sim_setup.log
#   ALLOW_NON_JETSON=1   run it on a normal Ubuntu 22.04 machine anyway (for testing)
set -eo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SIM=$(cd "$HERE/.." && pwd)
PX4_COMMIT=860aca9864      # the PX4 commit the WSL sim was tested on (sim/README.md)
PX4_MSGS_COMMIT=d49263b    # px4_msgs matching that PX4

. /etc/os-release
[ "$VERSION_ID" = 22.04 ] || { echo "!!! Needs Ubuntu 22.04 (JetPack 6); this is $PRETTY_NAME"; exit 1; }
if [ ! -f /etc/nv_tegra_release ] && [ "${ALLOW_NON_JETSON:-0}" != 1 ]; then
  echo "!!! Not a Jetson. Set ALLOW_NON_JETSON=1 to run it anyway."; exit 1
fi
[ "$(id -u)" != 0 ] || { echo "!!! Run as your normal user, not with sudo."; exit 1; }
[ -f /opt/ros/humble/setup.bash ] || {
  echo "!!! No ROS 2 Humble. Run sudo bash hw/1_jetson_sudo.sh first (it installs ROS)."; exit 1; }

# shellcheck source=env.sh
source "$HERE/env.sh"
mkdir -p "$SIM_HOME"
echo "=== Jetson sim: arch $(uname -m), sim home $SIM_HOME"

# colcon reads ~/.colcon/defaults.yaml: build 2 packages at a time instead of all cores
mkdir -p "$SIM_HOME/.colcon"
printf 'build:\n  parallel-workers: 2\n' > "$SIM_HOME/.colcon/defaults.yaml"
# git needs the real identity/config for clones, and the patches are applied with their own
[ -f "$REAL_HOME/.gitconfig" ] && cp -n "$REAL_HOME/.gitconfig" "$SIM_HOME/.gitconfig"
# A shell that opens in the sim env (used by run.sh with no arguments)
cat > "$SIM_HOME/.bashrc" <<'RC'
source /opt/ros/humble/setup.bash
PS1="(jetson-sim) $PS1"
RC

# --- Gazebo Harmonic + ros_gz (WSL got these from PX4's ubuntu.sh; here we add the repo ourselves) ---
echo "=== Gazebo Harmonic"
if ! dpkg -s gz-harmonic >/dev/null 2>&1 || ! dpkg -s ros-humble-ros-gzharmonic >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y curl lsb-release gnupg
  sudo curl -sSL https://packages.osrfoundation.org/gazebo.gpg -o /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/gazebo-stable.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y gz-harmonic ros-humble-rviz2
  sudo apt-get install -y ros-humble-ros-gzharmonic || {
    echo "!!! ros-humble-ros-gzharmonic is not available for $(dpkg --print-architecture)."
    echo "    Send this log to Aaron; the sim's depth bridge needs it."; exit 1; }
fi

# --- PX4 SITL (README step 0.2) ---
echo "=== PX4 $PX4_COMMIT"
if [ ! -d "$HOME/PX4-Autopilot/.git" ]; then
  git clone --recursive https://github.com/PX4/PX4-Autopilot.git "$HOME/PX4-Autopilot"
fi
( cd "$HOME/PX4-Autopilot" && git checkout -q "$PX4_COMMIT" && git submodule update --init --recursive )
if [ ! -f "$SIM_HOME/.px4_deps_done" ]; then
  # --no-nuttx: no flight-controller cross compiler (not needed for SITL)
  # --no-sim-tools: Gazebo is installed above
  bash "$HOME/PX4-Autopilot/Tools/setup/ubuntu.sh" --no-nuttx --no-sim-tools
  touch "$SIM_HOME/.px4_deps_done"
fi
if [ ! -x "$HOME/PX4-Autopilot/build/px4_sitl_default/bin/px4" ]; then
  # j=2 / CMAKE_BUILD_PARALLEL_LEVEL keep PX4's ninja build to 2 jobs (all 6 cores runs out of memory)
  ( cd "$HOME/PX4-Autopilot" && CMAKE_BUILD_PARALLEL_LEVEL=2 make px4_sitl_default j=2 )
fi

# --- px4_msgs matching that PX4 (README step 0.3), in the sim's own ~/ros2_ws ---
echo "=== px4_msgs $PX4_MSGS_COMMIT"
source /opt/ros/humble/setup.bash
mkdir -p "$HOME/ros2_ws/src"
[ -d "$HOME/ros2_ws/src/px4_msgs/.git" ] || git clone https://github.com/PX4/px4_msgs.git "$HOME/ros2_ws/src/px4_msgs"
( cd "$HOME/ros2_ws/src/px4_msgs" && git checkout -q "$PX4_MSGS_COMMIT" )
[ -f "$HOME/ros2_ws/install/setup.bash" ] || ( cd "$HOME/ros2_ws" && colcon build )

# --- Micro XRCE-DDS agent (README step 0.4). hw/2 already installs v2.4.2 system-wide. ---
echo "=== Micro XRCE-DDS agent"
if ! command -v MicroXRCEAgent >/dev/null; then
  [ -d "$HOME/Micro-XRCE-DDS-Agent/.git" ] || \
    git clone --branch v2.4.2 https://github.com/eProsima/Micro-XRCE-DDS-Agent.git "$HOME/Micro-XRCE-DDS-Agent"
  # the 2.12.x Fast-DDS branch it downloads was deleted upstream; use its last tag
  sed -i 's/set(_fastdds_tag 2\.12\.x)/set(_fastdds_tag v2.12.2)/' "$HOME/Micro-XRCE-DDS-Agent/CMakeLists.txt"
  ( cd "$HOME/Micro-XRCE-DDS-Agent" && mkdir -p build && cd build && cmake .. && make && sudo make install && sudo ldconfig /usr/local/lib/ )
fi

# --- The normal sim setup (README steps 1 and 2) ---
echo "=== sim/1_sudo_install.sh"
sudo bash "$SIM/1_sudo_install.sh"
echo "=== sim/2_user_setup.sh"
bash "$SIM/2_user_setup.sh"

cat <<EOF
=== Jetson sim setup done ===
Every sim command goes through run.sh, so it uses the sim's own workspaces:
  bash $HERE/run.sh $SIM/e2e_test.sh 4.0 2.0     # headless check, ~3 min
  bash $HERE/run.sh $SIM/demo.sh                 # Gazebo + RViz on the Jetson's monitor
  bash $HERE/run.sh                              # a shell in the sim env
EOF
