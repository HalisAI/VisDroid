#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
# build-so.sh — biên dịch engine ViScript thành `libvis_ffi.so` cho Android và chép vào
# `android/app/src/main/jniLibs/<abi>/` của VisDroid.
#
# Dùng: ./build-so.sh [aarch64-v8a|armeabi-v7a|x86_64|all]
# Biến môi trường:
#   ANDROID_NDK  đường dẫn NDK (mặc định: tự dò $ANDROID_HOME/ndk/* bản mới nhất)
#   VIS_DIR      ViScript đã vá (mặc định: ./ViScript cạnh script)
# Yêu cầu: rustup với target aarch64-linux-android, armv7-linux-androideabi,
#          x86_64-linux-android đã cài.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VIS_DIR="${VIS_DIR:-$HERE/ViScript}"
APP_DIR="${APP_DIR:-$HERE/../android/app}"

which_target="${1:-all}"
case "$which_target" in
    aarch64-v8a) ABIS="aarch64-v8a" ;;
    armeabi-v7a) ABIS="armeabi-v7a" ;;
    x86_64) ABIS="x86_64" ;;
    all) ABIS="aarch64-v8a armeabi-v7a x86_64" ;;
    *) echo "target lạ: $which_target (dùng aarch64-v8a | armeabi-v7a | x86_64 | all)" >&2; exit 2 ;;
esac

# Dò NDK: biến môi trường thắng, sau đó $ANDROID_HOME/ndk/* bản mới nhất.
if [ -z "${ANDROID_NDK:-}" ]; then
    AH="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
    ANDROID_NDK="$(ls -d "$AH"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
fi
if [ ! -d "$ANDROID_NDK" ]; then
    echo "Không thấy NDK — đặt ANDROID_NDK=… (hiện dò: ${ANDROID_NDK:-không có; ANDROID_HOME=${ANDROID_HOME:-trống}})" >&2
    exit 2
fi
TOOLCHAIN="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
if [ ! -d "$TOOLCHAIN" ]; then
    TOOLCHAIN="$ANDROID_NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin"
fi
echo "NDK: $ANDROID_NDK"

# Ghi .cargo/config.toml với linker khớp máy đang build (API 25 = minSdk VisDroid).
mkdir -p "$VIS_DIR/.cargo"
cat > "$VIS_DIR/.cargo/config.toml" <<EOF
# Sinh tự động bởi build-so.sh — linker NDK cho từng ABI Android (API 25).
[target.aarch64-linux-android]
linker = "$TOOLCHAIN/aarch64-linux-android25-clang"

[target.armv7-linux-androideabi]
linker = "$TOOLCHAIN/armv7a-linux-androideabi25-clang"

[target.x86_64-linux-android]
linker = "$TOOLCHAIN/x86_64-linux-android25-clang"
EOF

# Crate `cc` (libsqlite3-sys của upstream mới, VD-241) biên dịch C cho target
# Android — cần CC/AR tường minh: NDK không có file "aarch64-linux-android-clang"
# (chỉ có bản gắn API-suffix), nên PATH thuần không đủ. Lưu ý: tên biến bash
# không chứa gạch ngang — cc crate nhận cả dạng underscore (CC_aarch64_linux_android).
export CC_aarch64_linux_android="$TOOLCHAIN/aarch64-linux-android25-clang"
export CC_armv7_linux_androideabi="$TOOLCHAIN/armv7a-linux-androideabi25-clang"
export CC_x86_64_linux_android="$TOOLCHAIN/x86_64-linux-android25-clang"
for T in aarch64_linux_android armv7_linux_androideabi x86_64_linux_android; do
    export "AR_${T}=$TOOLCHAIN/llvm-ar"
    export "CXX_${T}=$TOOLCHAIN/clang++"
done

CARGO="$(command -v cargo || echo "$HOME/.cargo/bin/cargo")"
mkdir -p "$APP_DIR/src/main/jniLibs"

for abi in $ABIS; do
    case "$abi" in
        aarch64-v8a)  trip="aarch64-linux-android" ;;
        armeabi-v7a)  trip="armv7-linux-androideabi" ;;
        x86_64)       trip="x86_64-linux-android" ;;
    esac
    echo "=== build $abi ($trip) ==="
    (cd "$VIS_DIR" && "$CARGO" build --release -p vis-ffi --target "$trip")
    # Tên thư mục jniLibs theo ABI Android: aarch64-v8a → arm64-v8a.
    android_abi="$abi"
    [ "$abi" = "aarch64-v8a" ] && android_abi="arm64-v8a"
    mkdir -p "$APP_DIR/src/main/jniLibs/$android_abi"
    cp "$VIS_DIR/target/$trip/release/libvis_ffi.so" "$APP_DIR/src/main/jniLibs/$android_abi/"
    ls -la "$APP_DIR/src/main/jniLibs/$android_abi/libvis_ffi.so"
done
echo "Xong — libvis_ffi.so đã nằm trong jniLibs."
