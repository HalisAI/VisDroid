#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Dựng NDK stub tối thiểu cho máy build KHÔNG compile native (engine libvis_ffi.so
# đã biên dịch sẵn bằng native/build-so.sh). AGP chỉ cần:
#  - source.properties khớp ndkVersion trong build.gradle.kts
#  - llvm-strip / llvm-objcopy cho bước strip native libs (đã tắt qua
#    packaging.jniLibs.keepDebugSymbols, shim trả 0 cho chắc chắn)
# Trên máy có NDK thật thì KHÔNG chạy script này.
set -euo pipefail
NDK_DIR="${1:?dùng: make_ndk_stub.sh <ndk-dir> <revision, vd 27.0.12077973>}"
REV="${2:-27.0.12077973}"
mkdir -p "$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin"
cat > "$NDK_DIR/source.properties" <<PROP
Pkg.Desc = Android NDK
Pkg.Revision = $REV
Pkg.Url = https://developer.android.com/ndk
PROP
for tool in llvm-strip llvm-objcopy llvm-readelf; do
  printf '#!/bin/sh\n# Stub: .so đã strip sẵn (native/build-so.sh) + keepDebugSymbols trong gradle.\nexit 0\n' > "$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/$tool"
  chmod +x "$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/$tool"
done
echo "NDK stub sẵn sàng: $NDK_DIR (revision $REV)"
