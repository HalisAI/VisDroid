#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""sync-viscript-patch.py — áp lớp vá VisDroid lên cây ViScript vừa đồng bộ.

Ba việc (bám đúng những gì fork VisDroid đã làm):
  1. `crates/vis-cli/src/main.rs`: bỏ khai báo module dùng chung (đã chuyển sang
     lib.rs), bỏ 2 hàm helper đã dời vào lib.rs, thêm `use vis_cli::…`.
  2. Nới `pub(crate)` → `pub` trong toàn bộ src của vis-cli (vis-ffi gọi được).
  3. Root `Cargo.toml`: thêm `crates/vis-ffi` vào workspace members.

Mọi bước đều idempotent — chạy lại không sinh thay đổi giả.
"""
import pathlib
import re
import sys

VENDOR = pathlib.Path(sys.argv[1]).resolve()

# ---------------------------------------------------------------------
# 1. main.rs
# ---------------------------------------------------------------------
MAIN = VENDOR / 'crates/vis-cli/src/main.rs'
SHARED_MODS = ['cache', 'cli', 'fsmock', 'json_esc', 'lsp',
               'modules', 'net', 'ngoai', 'pkg', 'quyen', 'vistest']

def drop_fn(src: str, name: str) -> str:
    """Xoá hàm `fn <name>` cùng doc-comment liền trên và thân {} cân bằng."""
    m = re.search(r'((?:^///[^\n]*\n)*)^fn ' + name + r'\(', src, re.M)
    if not m:
        print(f'  ! không thấy fn {name} trong main.rs (có thể upstream đã đổi) — bỏ qua')
        return src
    start = m.start()
    i = src.index('{', m.end() - 1)
    depth = 0
    while i < len(src):
        if src[i] == '{':
            depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0:
                break
        i += 1
    end = i + 1
    if end < len(src) and src[end] == '\n':
        end += 1
    return src[:start] + src[end:]

text = MAIN.read_text(encoding='utf-8')
orig = text

# 1a. bỏ khai báo module dùng chung (giữ `mod audit_span;`/`mod quyen_st174;` — chỉ dùng cho bin)
for mod in SHARED_MODS:
    text = re.sub(rf'^mod {mod};\n', '', text, flags=re.M)

# 1b. bỏ 2 helper đã dời sang lib.rs
text = drop_fn(text, 'xuat_stdout')
text = drop_fn(text, 'dong_chan_doan')

# 1c. thêm use vis_cli ngay sau khai báo mod còn lại (idempotent)
if 'use vis_cli::{' not in text:
    mods = list(re.finditer(r'^mod [a-z_0-9]+;\n', text, flags=re.M))
    if mods:
        pos = mods[-1].end()
    else:
        print('  ! main.rs không còn `mod …;` nào — chèn use vào đầu file')
        pos = 0

    # Chỉ import cái main.rs thực sự dùng (upstream có thể đã bỏ bớt — tránh warning)
    body = re.sub(r'^use vis_cli::\{[^\n]*\};\n', '', text, flags=re.M)
    mods_list = [m for m in ['cache', 'cli', 'fsmock', 'json_esc', 'lsp', 'modules',
                             'ngoai', 'pkg', 'quyen', 'vistest']
                 if re.search(rf'\b{m}::|\b{m}\b', body)]
    helpers = [h for h in ['dong_chan_doan', 'xuat_stdout']
               if re.search(rf'\b{h}\(', body)]
    insert = ('\n// Các module dùng chung nằm trong lib (`lib.rs`) — bin và `vis-ffi` dùng chung một pipeline.\n')
    if mods_list:
        insert += 'use vis_cli::{%s};\n' % ', '.join(mods_list)
    if helpers:
        insert += 'use vis_cli::{%s};\n' % ', '.join(helpers)
    text = text[:pos] + insert + text[pos:]

# 1d. đường dẫn net::Net
text = text.replace('use net::Net as HostNet;', 'use vis_cli::net::Net as HostNet;')

if text != orig:
    MAIN.write_text(text, encoding='utf-8')
    print('  ✓ main.rs: mod dùng chung → vis_cli, helper → lib.rs')
else:
    print('  • main.rs: đã ở trạng thái fork — không đổi')

# ---------------------------------------------------------------------
# 2. pub(crate) → pub trong vis-cli/src (trừ lib.rs đã pub sẵn)
# ---------------------------------------------------------------------
count = 0
for p in (VENDOR / 'crates/vis-cli/src').rglob('*.rs'):
    t = p.read_text(encoding='utf-8')
    n = t.count('pub(crate)')
    if n:
        p.write_text(t.replace('pub(crate)', 'pub'), encoding='utf-8')
        count += n
print(f'  ✓ nới visibility: {count} chỗ pub(crate) → pub')

# ---------------------------------------------------------------------
# 3. Cargo.toml: members += crates/vis-ffi
# ---------------------------------------------------------------------
TOML = VENDOR / 'Cargo.toml'
t = TOML.read_text(encoding='utf-8')
if 'crates/vis-ffi' not in t:
    t = t.replace('"crates/vis-vm",', '"crates/vis-vm",\n    "crates/vis-ffi",')
    if 'crates/vis-ffi' not in t:
        sys.exit('!! không chèn được crates/vis-ffi vào Cargo.toml members')
    TOML.write_text(t, encoding='utf-8')
    print('  ✓ Cargo.toml: thêm crates/vis-ffi vào workspace')
else:
    print('  • Cargo.toml: đã có crates/vis-ffi')
