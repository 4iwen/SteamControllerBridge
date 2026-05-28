#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:-.}"
mkdir -p "$out_dir/win64" "$out_dir/win32"
rm -f "$out_dir"/xinput*.dll

build_arch() {
  cc="$1"
  arch_out="$2"
  entry="$3"

  "$cc" -shared -nostdlib -Wl,-e,"$entry" -O2 -Wall -Wextra \
    -o "$arch_out/xinput1_3.dll" xinput_bridge.c xinput_bridge.def -lws2_32 -lkernel32
  cp "$arch_out/xinput1_3.dll" "$arch_out/xinput1_1.dll"
  cp "$arch_out/xinput1_3.dll" "$arch_out/xinput1_2.dll"
  cp "$arch_out/xinput1_3.dll" "$arch_out/xinput1_4.dll"
  cp "$arch_out/xinput1_3.dll" "$arch_out/xinput9_1_0.dll"
  cp "$arch_out/xinput1_3.dll" "$arch_out/xinputuap.dll"
}

build_arch "${MINGW64_CC:-x86_64-w64-mingw32-gcc}" "$out_dir/win64" "DllMain"
build_arch "${MINGW32_CC:-i686-w64-mingw32-gcc}" "$out_dir/win32" "_DllMain@12"
