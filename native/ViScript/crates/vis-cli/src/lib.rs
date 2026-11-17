// SPDX-License-Identifier: MIT OR Apache-2.0
//! Thư viện của crate `vis-cli`: tách các module dùng chung khỏi `main.rs` để cả bin `vis`
//! và crate nhúng `vis-ffi` (FFI cho VisDroid) dùng lại **cùng một** pipeline chạy — không
//! phải viết lại logic host (`FsHost`, `NetHost`, quyền `cap`, nạp module).
//!
//! Mọi module dưới đây giữ nguyên mã từ `main.rs` cũ; `main.rs` chỉ còn phần điều hướng lệnh
//! con và import lại từ đây.

pub mod cache;
pub mod cli;
pub mod fsmock;
pub mod json_esc;
pub mod lsp;
pub mod modules;
pub mod net;
pub mod ngoai;
pub mod pkg;
pub mod quyen;
pub mod vistest;

// Re-export các crate ngôn ngữ để module trong lib viết `use crate::*` hay đường `vis_types::…`
// vẫn hoạt động như khi chúng nằm trong `main.rs`.
pub use vis_bytecode;
pub use vis_diag;
pub use vis_fmt;
pub use vis_interp;
pub use vis_syntax;
pub use vis_types;
pub use vis_vm;

pub use crate::cli::run::{in_sandbox_check, ma_thoat_khi_loi, run_dry};

// main.rs cũ có `use vis_syntax::Mode;` ở crate root; các module `cli/*` dùng `use crate::*`
// nên cần tên `Mode` tại đây để dịch ở ngữ cảnh lib.
pub use vis_syntax::Mode;

/// Ghi ra stdout **một lần**; `BrokenPipe` (vd `vis fmt … | head`) ⇒ im lặng thoát 0, không panic.
/// Lỗi I/O khác ⇒ báo stderr và trả `false` (caller thoát 2).
pub fn xuat_stdout(s: &str) -> bool {
    use std::io::Write;
    let stdout = std::io::stdout();
    let mut w = stdout.lock();
    match w.write_all(s.as_bytes()).and_then(|()| w.flush()) {
        Ok(()) => true,
        Err(e) if e.kind() == std::io::ErrorKind::BrokenPipe => std::process::exit(0),
        Err(e) => {
            eprintln!("# không ghi được stdout: {e}");
            false
        }
    }
}

/// Escape ký tự điều khiển để chẩn đoán nằm gọn trên **một** dòng (TAP/stderr).
pub fn dong_chan_doan(code: &str, line: u32, col: u32, message: &str) -> String {
    format!(
        "{code} {line}:{col} {}",
        message
            .replace('\n', "\\n")
            .replace('\r', "\\r")
            .replace('\t', "\\t")
    )
}
