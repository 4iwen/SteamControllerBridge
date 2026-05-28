#!/usr/bin/env bash
set -euo pipefail

cc="${MINGW_CC:-x86_64-w64-mingw32-gcc}"
out_dir="${1:-.}"
mkdir -p "$out_dir"

"$cc" -shared -O2 -Wall -Wextra -o "$out_dir/xinput1_3.dll" xinput_bridge.c -lws2_32
cp "$out_dir/xinput1_3.dll" "$out_dir/xinput1_4.dll"
cp "$out_dir/xinput1_3.dll" "$out_dir/xinput9_1_0.dll"

