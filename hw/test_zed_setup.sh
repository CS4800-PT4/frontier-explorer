#!/usr/bin/env bash
# Tests for the version picking in hw/zed_setup.sh. No network, no SDK needed.
# Run: bash hw/test_zed_setup.sh
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/zed_setup.sh"
set +e   # zed_setup.sh turns on set -e, but these tests check failures on purpose
fails=0
check() {  # name, expected, actual
  if [ "$2" = "$3" ]; then echo "ok   $1"
  else echo "FAIL $1"; echo "     want: $2"; echo "     got:  $3"; fails=$((fails + 1)); fi
}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# The wrapper's real tags (Nov 2026), in the order git prints them
TAGS="crystal crystal-0.1 eloquent-v3.5 foxy-humble-v3.8 foxy-humble-v3.8.2 foxy-humble-v4.0.5
foxy-v3.5 foxy-v3.5.1 foxy-v3.6 foxy-v3.7 humble-v4.0.8 humble-v4.1.4 humble-v4.2.x humble-v4.2.5
humble-v5.0.0 humble-v5.1.0 v5.2.0 v5.2.2 v5.3.1 v5.4.0 v5.4.1 v5.5.0"
picks() { echo $TAGS | tr ' ' '\n' | wrapper_tags | pick_tags "$1" 3 | xargs; }

check "SDK 5.5.1 -> v5.5.0 first"            "v5.5.0 v5.4.1 v5.4.0"                       "$(picks 5.5.1)"
check "SDK 5.4.0 -> newest 5.4 patch first"  "v5.4.1 v5.4.0 v5.3.1"                       "$(picks 5.4.0)"
check "SDK 5.2.3 -> v5.2.x, then 5.1"        "v5.2.2 v5.2.0 humble-v5.1.0"                "$(picks 5.2.3)"
check "SDK 5.1.2 -> humble-v5.1.0"           "humble-v5.1.0 humble-v5.0.0"                "$(picks 5.1.2)"
check "SDK 4.2.5 -> humble-v4.2.5, no 4.2.x" "humble-v4.2.5 humble-v4.1.4 humble-v4.0.8"  "$(picks 4.2.5)"
check "SDK 5.6.0 (no release yet) -> v5.5.0" "v5.5.0 v5.4.1 v5.4.0"                       "$(picks 5.6.0)"
check "SDK 3.8.2 -> nothing"                 ""                                           "$(picks 3.8.2)"
check "never picks master or a foxy tag"     "0" "$(echo $TAGS master | tr ' ' '\n' | wrapper_tags | grep -c -E 'master|foxy|crystal|eloquent')"
check "ZED_TRIES=1 -> one tag"               "v5.5.0"                                     "$(echo $TAGS | tr ' ' '\n' | wrapper_tags | pick_tags 5.5.1 1 | xargs)"
# The line main runs, under main's own set -eo pipefail (a "| head" there used to exit 141)
check "pick line is ok under pipefail" "0 v5.5.0 v5.4.1 v5.4.0" \
  "$(bash -c 'set -eo pipefail; source "$1"; refs=$(echo "$2" | tr " " "\n" | wrapper_tags | pick_tags 5.5.1 3); echo 0 $refs' _ "$HERE/zed_setup.sh" "$TAGS" 2>&1 | xargs)"

# SDK version from the header (same #define lines the SDK ships)
printf '#define ZED_SDK_MAJOR_VERSION 5\n#define ZED_SDK_MINOR_VERSION 5\n#define ZED_SDK_PATCH_VERSION 1\n#define ZED_SDK_BUILD_ID "x"\n' > "$tmp/Camera.hpp"
check "SDK version from header" "5.5.1" "$(ZED_HEADER=$tmp/Camera.hpp sdk_version)"
check "no header -> fails" "1" "$(ZED_HEADER=$tmp/none.hpp sdk_version >/dev/null; echo $?)"

# Installer links
echo "# R36 (release), REVISION: 4.3, GCID: 38968081, BOARD: generic, EABI: aarch64, DATE: Wed Jan  8" > "$tmp/tegra"
check "Jetson R36.4.3 link" "https://download.stereolabs.com/zedsdk/5.5/l4t36.4/jetsons" "$(TEGRA=$tmp/tegra sdk_url 5.5)"
check "x86 link"            "https://download.stereolabs.com/zedsdk/5.4/cu12/ubuntu22"   "$(TEGRA=$tmp/none MACHINE=x86_64 sdk_url 5.4)"
check "ARM, not a Jetson -> no link" "1" "$(TEGRA=$tmp/none MACHINE=aarch64 sdk_url 5.5 >/dev/null; echo $?)"
check "ZED_SDK_URL wins"    "https://example.com/sdk.run"                               "$(ZED_SDK_URL=https://example.com/sdk.run TEGRA=$tmp/tegra sdk_url 5.5)"
echo "garbage" > "$tmp/tegra_bad"
check "unreadable L4T -> fails" "1" "$(TEGRA=$tmp/tegra_bad sdk_url 5.5 >/dev/null; echo $?)"

# SDK versions to try when the asked one isn't offered for this JetPack
check "SDK fallback from 5.5" "5.5 5.4 5.3 5.2 5.1 5.0" "$(sdk_versions 5.5 | xargs)"
check "SDK fallback from 4.2" "4.2 4.1 4.0"             "$(sdk_versions 4.2 | xargs)"

# A link that answers with a web page (not offered for this JetPack) isn't an installer
check "installer link ok"       "0" "$(is_installer_url https://cdn.example.com/zedsdk/5.5/ZED_SDK_Tegra_L4T36.4_v5.5.1.zstd.run; echo $?)"
check "homepage redirect -> no" "1" "$(is_installer_url https://www.stereolabs.com/; echo $?)"

# main's early exits, run as the real script with fake paths (no network, nothing built)
if [ -f /opt/ros/humble/setup.bash ]; then
  run() {  # extra env assignments...; prints "<exit code> <last line>"
    local out rc
    out=$(env TEGRA="$tmp/none" MACHINE=x86_64 ZED_WS="$tmp/ws" "$@" bash "$HERE/zed_setup.sh" 2>&1); rc=$?
    echo "$rc $(echo "$out" | tail -1 | xargs)"
  }
  check "no SDK, not a Jetson -> skip (3)" "3 To install it here: ZED_SDK_INSTALL=1 bash hw/zed_setup.sh" \
    "$(run ZED_DIR="$tmp/nosdk")"
  check "no SDK, ARM board -> skip, no x86 hint" "3 !!! ZED SDK not found in $tmp/nosdk, skipping the ZED wrapper." \
    "$(run ZED_DIR="$tmp/nosdk" MACHINE=aarch64)"
  check "install asked, no CUDA -> fail (1) before any download" "1 !!! No CUDA toolkit ($tmp/nonvcc): run sudo bash hw/1_jetson_sudo.sh again" \
    "$(run ZED_DIR="$tmp/nosdk" ZED_SDK_INSTALL=1 NVCC="$tmp/nonvcc")"
  mkdir -p "$tmp/sdk"; printf '#!/bin/sh\n' > "$tmp/nvcc"; chmod +x "$tmp/nvcc"
  SDK=(ZED_DIR="$tmp/sdk" ZED_HEADER="$tmp/Camera.hpp" NVCC="$tmp/nvcc")
  check "no CUDA -> fail (1)" "1 !!! No CUDA toolkit ($tmp/nonvcc): run sudo bash hw/1_jetson_sudo.sh again" \
    "$(run ZED_DIR="$tmp/sdk" ZED_HEADER="$tmp/Camera.hpp" NVCC="$tmp/nonvcc")"
  # someone else's build: install/zed_components but no .zed_setup -> left alone
  mkdir -p "$tmp/ws/install/zed_components"
  check "someone else's ~/zed_ws -> left alone (0)" "0 To replace it with the release for SDK 5.5.1: ZED_REBUILD=1 bash hw/zed_setup.sh" \
    "$(run "${SDK[@]}")"
  check "...and it isn't claimed or cloned into" "untouched" \
    "$([ -e "$tmp/ws/.zed_setup" ] || [ -e "$tmp/ws/src" ] && echo changed || echo untouched)"
  # ours, built OK for this SDK -> nothing to do, no network
  touch "$tmp/ws/.zed_setup"; echo "sdk=5.5.1 ref=v5.5.0" > "$tmp/ws/.built"
  check "ours, already built -> 0" "0 === ZED wrapper v5.5.0 already built for SDK 5.5.1" "$(run "${SDK[@]}")"
  check "same, asking for that ref -> 0" "0 === ZED wrapper v5.5.0 already built for SDK 5.5.1" "$(run "${SDK[@]}" ZED_WRAPPER_REF=v5.5.0)"
else
  echo "skip main tests (no /opt/ros/humble)"
fi

echo; [ $fails = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
