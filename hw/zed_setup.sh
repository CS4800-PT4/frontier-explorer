#!/usr/bin/env bash
# ZED SDK and ROS 2 wrapper, matched by version. hw/2_jetson_setup.sh runs this at the end, or
# run it on its own (no sudo, it asks for the password when it needs it): bash hw/zed_setup.sh
# 1. If the ZED SDK is installed (/usr/local/zed) it's used as is, never replaced. If not, on a
#    Jetson it downloads and installs the SDK for this JetPack. Anywhere else it only installs
#    with ZED_SDK_INSTALL=1 (x86 only, needs an NVIDIA GPU and the CUDA 12 toolkit).
# 2. Reads the SDK version and picks the wrapper release made for it (SDK 5.5 -> v5.5.0).
# 3. Builds the wrapper in ~/zed_ws. If it doesn't build, tries the next closest release.
#    A ~/zed_ws that this script didn't build (the Jetson's owner, or another setup script) is
#    left alone unless ZED_REBUILD=1.
# Exit: 0 = wrapper built (or already there), 3 = skipped (no SDK), 1 = failed
#   ZED_SDK_VERSION   SDK to install when none is installed (default 5.5)
#   ZED_SDK_URL       installer link to use instead of the one made from ZED_SDK_VERSION
#   ZED_SDK_INSTALL   1 = install the SDK if it's missing, 0 = never (default 1 on a Jetson, else 0)
#   ZED_WRAPPER_REF   build only this wrapper tag (or branch), no picking and no fallback
#   ZED_TRIES         how many wrapper releases to try (default 3)
#   ZED_REBUILD       1 = build even if ~/zed_ws already has a wrapper build
set -eo pipefail

ZED_SDK_VERSION=${ZED_SDK_VERSION:-5.5}
ZED_TRIES=${ZED_TRIES:-3}
WRAPPER_URL=https://github.com/stereolabs/zed-ros2-wrapper.git
WS=${ZED_WS:-~/zed_ws}
TEGRA=${TEGRA:-/etc/nv_tegra_release}                         # tests point these at fake files
ZED_DIR=${ZED_DIR:-/usr/local/zed}
ZED_HEADER=${ZED_HEADER:-$ZED_DIR/include/sl/Camera.hpp}
NVCC=${NVCC:-/usr/local/cuda/bin/nvcc}
MACHINE=${MACHINE:-$(uname -m)}
export MAKEFLAGS=${MAKEFLAGS:--j4}
BUILD="colcon build --parallel-workers ${COLCON_WORKERS:-1}"

is_jetson() { [ -f "$TEGRA" ]; }

# Installed SDK version as major.minor.patch, read from the SDK's own header
sdk_version() {
  [ -f "$ZED_HEADER" ] || return 1
  awk '$1 == "#define" && $2 ~ /^ZED_SDK_(MAJOR|MINOR|PATCH)_VERSION$/ { v[$2] = $3 }
       END { if (v["ZED_SDK_MAJOR_VERSION"] == "") exit 1
             print v["ZED_SDK_MAJOR_VERSION"] "." v["ZED_SDK_MINOR_VERSION"] "." v["ZED_SDK_PATCH_VERSION"] }' "$ZED_HEADER"
}

# Installer link for an SDK version (major.minor). Jetson: the build for this L4T
# ("# R36 (release), REVISION: 4.3" -> l4t36.4). x86: the CUDA 12 / Ubuntu 22.04 build.
# There's no build for other machines (an ARM board that isn't a Jetson).
sdk_url() {  # version
  if [ -n "$ZED_SDK_URL" ]; then echo "$ZED_SDK_URL"; return; fi
  if is_jetson; then
    local l4t
    l4t=$(sed -n 's/^# R\([0-9]*\) .*REVISION: \([0-9]*\)\..*/\1.\2/p' "$TEGRA")
    [ -n "$l4t" ] || return 1
    echo "https://download.stereolabs.com/zedsdk/$1/l4t$l4t/jetsons"
  elif [ "$MACHINE" = x86_64 ]; then
    echo "https://download.stereolabs.com/zedsdk/$1/cu12/ubuntu22"
  else
    return 1
  fi
}

# SDK versions to try, newest first: the one asked for, then older ones of the same major.
# Stereolabs drops old JetPacks (5.3 and newer aren't built for L4T 36.3).
sdk_versions() {  # version
  local maj min
  maj=$(echo "$1" | cut -d. -f1); min=$(echo "$1" | cut -d. -f2)
  while [ "$min" -ge 0 ]; do echo "$maj.$min"; min=$((min - 1)); done
}

# A link for an SDK that isn't built for this JetPack redirects to the Stereolabs homepage
# (still HTTP 200), so only a link that ends at a .run file counts.
is_installer_url() { case $1 in *.run) return 0 ;; *) return 1 ;; esac; }

install_sdk() {
  local v url real="" tmp
  command -v zstd >/dev/null || { echo "!!! The ZED installer needs zstd: run sudo bash hw/1_jetson_sudo.sh again"; return 1; }
  if [ -n "$ZED_SDK_URL" ]; then
    real=$ZED_SDK_URL
  else
    for v in $(sdk_versions "$ZED_SDK_VERSION"); do
      url=$(sdk_url "$v") || { echo "!!! No ZED SDK download for this machine. Set ZED_SDK_URL to the installer link"; return 1; }
      # a network problem is not the same as "not built for this machine", so stop on it
      real=$(curl -sIL --retry 2 --max-time 30 -o /dev/null -w '%{url_effective}' "$url") \
        || { echo "!!! Can't reach $url (network?)"; return 1; }
      is_installer_url "$real" && break
      echo "    ZED SDK $v isn't built for this machine ($url), trying an older one"
      real=""
    done
    [ -n "$real" ] || { echo "!!! No ZED SDK $ZED_SDK_VERSION or older for this machine. See https://www.stereolabs.com/developers/release"; return 1; }
  fi
  echo "=== Installing ZED SDK from $real"
  tmp=$(mktemp -d)
  curl -fL --retry 3 -o "$tmp/ZED_SDK.run" "$real" || { echo "!!! Download failed: $real"; rm -rf "$tmp"; return 1; }
  # Runs as you (it calls sudo itself). After "--" go the installer's own options: no prompts,
  # no AI (object detection) module, no Python API, keep the CUDA we have, and no GMSL kernel
  # drivers (those are for the ZED X; ours is USB). --nox11: never open an xterm for it.
  local opts="silent skip_od_module skip_python skip_cuda"
  if is_jetson; then opts="$opts skip_drivers"; fi
  # shellcheck disable=SC2086
  sh "$tmp/ZED_SDK.run" --nox11 -- $opts || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  [ -d "$ZED_DIR" ] || { echo "!!! The installer finished but $ZED_DIR is missing"; return 1; }
}

# Wrapper release tags as "x.y.z tag" lines: humble-vX.Y.Z (up to 5.1) and vX.Y.Z (5.2 on)
wrapper_tags() {
  sed -nE 's/^((humble-)?v([0-9]+\.[0-9]+\.[0-9]+))$/\3 \1/p'
}

# Up to n tags to try for an SDK version: releases for its major.minor (newest first), then
# older releases of the same major (newest first). A newer wrapper usually needs a newer SDK.
# It stops by itself after n, since "| head" would cut the pipe and fail under pipefail.
pick_tags() {  # sdk_version, n; "x.y.z tag" lines on stdin
  local sdk=$1 n=$2 mm=${1%.*} maj=${1%%.*} all v t count=0
  all=$(sort -rV)
  while read -r v t; do
    if [ -n "$v" ] && [ "${v%.*}" = "$mm" ]; then
      echo "$t"; count=$((count + 1))
      if [ "$count" -ge "$n" ]; then return 0; fi
    fi
  done <<< "$all"
  while read -r v t; do
    if [ -n "$v" ] && [ "${v%%.*}" = "$maj" ] && [ "${v%.*}" != "$mm" ] \
       && [ "$(printf '%s\n%s\n' "$v" "$sdk" | sort -V | head -1)" = "$v" ]; then
      echo "$t"; count=$((count + 1))
      if [ "$count" -ge "$n" ]; then return 0; fi
    fi
  done <<< "$all"
  return 0
}

build_wrapper() {  # ref
  local ref=$1 target=$1 log=$WS/logs/wrapper_${1//\//_}.log   # feature/x can't be a file name
  local repo=$WS/src/zed-ros2-wrapper
  # a branch name means upstream's latest, not the local copy from the first clone
  if ! git -C "$repo" rev-parse -q --verify "refs/tags/$ref" >/dev/null \
     && git -C "$repo" rev-parse -q --verify "refs/remotes/origin/$ref" >/dev/null; then
    target=origin/$ref
  fi
  echo "=== ZED wrapper $ref (log: $log)"
  # && on every step: set -e is off inside "if build_wrapper", so a failed checkout would
  # otherwise build the release that was there before and record the wrong one
  ( cd "$repo" \
    && git checkout -q "$target" \
    && git submodule update --init --recursive -q \
    && cd "$WS" \
    && rm -rf build install log \
    && rosdep install --from-paths src --ignore-src -r -y \
    && $BUILD --symlink-install --packages-up-to zed_wrapper --cmake-args -DCMAKE_BUILD_TYPE=Release
  ) 2>&1 | tee "$log"
}

main() {
  local sdk refs ref built
  source /opt/ros/humble/setup.bash
  if [ ! -d "$ZED_DIR" ]; then
    if [ "${ZED_SDK_INSTALL:-$(is_jetson && echo 1 || echo 0)}" = 1 ]; then
      # before the download, not after: the SDK and the wrapper both need CUDA
      [ -x "$NVCC" ] || { echo "!!! No CUDA toolkit ($NVCC): run sudo bash hw/1_jetson_sudo.sh again"; exit 1; }
      install_sdk || exit 1
    else
      echo "!!! ZED SDK not found in $ZED_DIR, skipping the ZED wrapper."
      if [ "$MACHINE" = x86_64 ]; then echo "    To install it here: ZED_SDK_INSTALL=1 bash hw/zed_setup.sh"; fi
      exit 3
    fi
  fi
  [ -x "$NVCC" ] || { echo "!!! No CUDA toolkit ($NVCC): run sudo bash hw/1_jetson_sudo.sh again"; exit 1; }
  sdk=$(sdk_version) || { echo "!!! Can't read the ZED SDK version from $ZED_HEADER"; exit 1; }
  echo "=== ZED SDK $sdk"

  # Checked before any network use, so a re-run works offline. $WS/.zed_setup marks a
  # workspace this script owns; $WS/.built says which release last built OK.
  if [ "${ZED_REBUILD:-0}" != 1 ]; then
    if [ -d "$WS/install/zed_components" ] && [ ! -f "$WS/.zed_setup" ]; then
      echo "=== $WS already has a ZED wrapper build that this script didn't make"
      echo "    ($(git -C "$WS/src/zed-ros2-wrapper" describe --tags --always 2>/dev/null || echo "unknown version")). Leaving it as is."
      echo "    To replace it with the release for SDK $sdk: ZED_REBUILD=1 bash hw/zed_setup.sh"
      exit 0
    fi
    if [ -d "$WS/install/zed_components" ] && [ -f "$WS/.built" ]; then
      built=$(cat "$WS/.built")
      if [ "$built" = "sdk=$sdk ref=${ZED_WRAPPER_REF:-${built#*ref=}}" ]; then
        echo "=== ZED wrapper ${built#*ref=} already built for SDK $sdk"
        exit 0
      fi
    fi
  fi

  mkdir -p "$WS/src" "$WS/logs"
  touch "$WS/.zed_setup"
  [ -d "$WS/src/zed-ros2-wrapper/.git" ] || git clone -q "$WRAPPER_URL" "$WS/src/zed-ros2-wrapper"
  # --force: a tag Stereolabs moved upstream would otherwise stop the fetch
  git -C "$WS/src/zed-ros2-wrapper" fetch -q --tags --force origin \
    || echo "!!! Couldn't fetch wrapper releases, using the ones already here"
  if [ -n "$ZED_WRAPPER_REF" ]; then
    refs=$ZED_WRAPPER_REF
  else
    refs=$(git -C "$WS/src/zed-ros2-wrapper" tag -l | wrapper_tags | pick_tags "$sdk" "$ZED_TRIES")
    [ -n "$refs" ] || { echo "!!! No wrapper release for SDK $sdk. Set ZED_WRAPPER_REF=<tag>"; exit 1; }
  fi

  rosdep update -q >/dev/null || true
  for ref in $refs; do
    rm -f "$WS/.built"
    if build_wrapper "$ref"; then
      echo "sdk=$sdk ref=$ref" > "$WS/.built"
      echo "=== ZED wrapper $ref built for SDK $sdk"
      exit 0
    fi
    echo "!!! ZED wrapper $ref didn't build with SDK $sdk"
  done
  echo "!!! No wrapper release built with SDK $sdk (tried: ${refs//$'\n'/ }). Logs: $WS/logs/"
  exit 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi   # not when hw/test_zed_setup.sh sources it
