#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# sync-viscript.sh — đồng bộ fork ViScript nhúng trong `native/ViScript` với upstream
# https://github.com/vifast-oss/ViScript (mặc định nhánh chính).
#
# Fork này = upstream + 3 lớp vá VisDroid (giữ nguyên qua mỗi lần đồng bộ):
#   1. crate `crates/vis-ffi` (lớp C-ABI `visd_run`/`visd_check`/`visd_version` cho FFI Dart)
#   2. `crates/vis-cli/src/lib.rs` — tách module dùng chung khỏi `main.rs` thành thư viện
#      để bin `vis` và `vis-ffi` dùng chung một pipeline chạy (main.rs chuyển sang `use vis_cli::…`)
#   3. nới `pub(crate)` → `pub` trong vis-cli để vis-ffi gọi được
#   (kèm vài fixture `test/doc-examples` do fork thêm)
#
# Cách dùng:
#   scripts/sync-viscript.sh [thư-mục-clone-upstream]
#     — nếu bỏ trống: clone mới (depth 1) vào /tmp/vifast-oss-ViScript
# Sau khi chạy: `git status native/ViScript` cho thấy thay đổi; gate `cargo check`
# (nếu có cargo) phải pass trước khi commit.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VENDORED="$HERE/../native/ViScript"
UP="${1:-}"

if [ -z "$UP" ]; then
    UP="/tmp/vifast-oss-ViScript"
    rm -rf "$UP"
    echo "==> Clone upstream (depth 1) vào $UP"
    git clone --depth 1 https://github.com/vifast-oss/ViScript.git "$UP"
fi
UP="$(cd "$UP" && pwd)"
UP_SHA="$(git -C "$UP" rev-parse HEAD)"
echo "==> Upstream HEAD: $UP_SHA"

if [ ! -d "$VENDORED/crates" ]; then
    echo "Không thấy $VENDORED/crates — chạy từ gốc repo VisDroid." >&2
    exit 2
fi

# ---------------------------------------------------------------------
# 1. Lưu lớp vá của fork trước khi ghi đè
# ---------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/overlay/crates" "$TMP/overlay/doc-examples"
cp -r "$VENDORED/crates/vis-ffi" "$TMP/overlay/crates/vis-ffi"
cp "$VENDORED/crates/vis-cli/src/lib.rs" "$TMP/overlay/crates/vis-cli-lib.rs"
# fixture do fork thêm (không có ở upstream) — chép cả thư mục, bước 4 khôi phục dạng union
if [ -d "$VENDORED/test/doc-examples" ]; then
    cp -r "$VENDORED/test/doc-examples/." "$TMP/overlay/doc-examples/" 2>/dev/null || true
fi

# ---------------------------------------------------------------------
# 2. Ghi đè bằng upstream (trừ .git / agent ~19MB / artifact build)
# ---------------------------------------------------------------------
echo "==> Ghi đè native/ViScript bằng upstream"
RS="rsync"
command -v rsync >/dev/null 2>&1 || RS=""
if [ -n "$RS" ]; then
    mkdir -p "$VENDORED"
    rsync -a --delete \
        --exclude='.git' --exclude='agent' --exclude='target' \
        --exclude='.cargo' --exclude='.github' \
        "$UP/" "$VENDORED/"
else
    echo "  (không có rsync — dùng cp/find)"
    find "$VENDORED" -mindepth 1 -maxdepth 1 \
        ! -name '.git' ! -name 'agent' ! -name 'target' ! -name '.cargo' \
        -exec rm -rf {} +
    cp -r "$UP/." "$VENDORED/"
    rm -rf "$VENDORED/.git" "$VENDORED/agent" "$VENDORED/.github"
fi

# ---------------------------------------------------------------------
# 3. Khôi phục lớp vá VisDroid
# ---------------------------------------------------------------------
echo "==> Khôi phục lớp vá VisDroid (vis-ffi, lib.rs, doc-examples)"
rm -rf "$VENDORED/crates/vis-ffi"
cp -r "$TMP/overlay/crates/vis-ffi" "$VENDORED/crates/vis-ffi"
cp "$TMP/overlay/crates/vis-cli-lib.rs" "$VENDORED/crates/vis-cli/src/lib.rs"
mkdir -p "$VENDORED/test/doc-examples"
cp -r "$TMP/overlay/doc-examples/." "$VENDORED/test/doc-examples/" 2>/dev/null || true

# ---------------------------------------------------------------------
# 4. Patch cơ học: lib split + pub + workspace member
# ---------------------------------------------------------------------
echo "==> Patch main.rs / visibility / Cargo.toml"
python3 "$HERE/sync-viscript-patch.py" "$VENDORED"

# ---------------------------------------------------------------------
# 5. Gate: cargo check (nếu có cargo) — bản fork phải dịch được với upstream mới
# ---------------------------------------------------------------------
CARGO="${CARGO:-$(command -v cargo || true)}"
[ -z "$CARGO" ] && [ -x "$HOME/.cargo/bin/cargo" ] && CARGO="$HOME/.cargo/bin/cargo"
if [ -n "$CARGO" ]; then
    echo "==> Gate cargo check -p vis-cli -p vis-ffi"
    (cd "$VENDORED" && "$CARGO" check --quiet -p vis-cli -p vis-ffi)
    echo "    OK — fork dịch sạch với upstream $UP_SHA"
else
    echo "  (không thấy cargo — bỏ qua gate; CHẠY cargo check trước khi commit!)"
fi

# ---------------------------------------------------------------------
# 6. Tổng kết
# ---------------------------------------------------------------------
echo
echo "==> Xong. Upstream: $UP_SHA"
[ -d "$VENDORED/../.." ] && git -C "$HERE/.." status --short -- native/ViScript | head -20
echo "Kiểm lại bằng: cargo check -p vis-cli -p vis-ffi (tại native/ViScript)"
echo "Build .so:     ./native/build-so.sh all   (cần NDK)"
