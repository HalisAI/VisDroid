// SPDX-License-Identifier: MIT OR Apache-2.0
//! **vis-ffi** — cầu nối C-ABI giữa VisDroid (Dart/Flutter) và engine ViScript.
//!
//! Hàm công khai trên biên FFI:
//! - `visd_version() -> *mut c_char` — chuỗi JSON nhận diện engine
//! - `visd_run(request_json: *const c_char) -> *mut c_char` — chạy chương trình
//! - `visd_check(request_json: *const c_char) -> *mut c_char` — phân tích tĩnh, không chạy
//! - `visd_free(ptr: *mut c_char)` — giải phóng chuỗi do các hàm trên cấp phát
//!
//! Mọi chuỗi trả về là UTF-8 do bên này cấp phát (`CString::into_raw`); bên gọi bắt buộc
//! `visd_free` sau khi dùng. Không panic vượt biên FFI: thân hàm bọc `catch_unwind`, panic
//! chuyển thành JSON `"ok": false`.
//!
//! Yêu cầu JSON (tất cả tùy chọn trừ `entry`):
//! - `entry` (bắt buộc): đường dẫn tệp chính `.vis`/`.vish` trên đĩa
//! - `text`: nội dung buffer editor **đè lên** nội dung trên đĩa (tệp phụ vẫn đọc đĩa)
//! - `dir`: thư mục làm việc (đặt cwd cho đường dẫn tương đối của `std.fs`)
//! - `args`: đối số chương trình cho `main`
//! - `use_vm`: chạy đường VM (bytecode) thay vì interp
//! - `no_extern`: tắt chương trình ngoài (mặc định `false`, khớp `vis run`)
//! - `strict_caps`: siết mọi truy cập fs/net theo `cap` đã khai (mặc định `false`)
//! - `explain_perms`: in nhật ký quyền ra stderr
//!
//! Kết quả JSON: `{ ok, exit, stdout, steps, diags: [{file,code,line,col,msg}], error }`

use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;

use vis_cli::modules;
use vis_cli::net::Net;
use vis_cli::ngoai::Runner;
use vis_cli::quyen::{self, FsGuard, NetGuard};

// ---------------------------------------------------------------------------
// Biên FFI
// ---------------------------------------------------------------------------

/// Trả chuỗi JSON ra biên FFI (người gọi chịu trách nhiệm `visd_free`).
fn tra_json(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        // Không thể xảy ra với serde_json (escape `\u0000`), vẫn chặn để khỏi UB.
        Err(_) => CString::new("{\"ok\":false,\"error\":\"json có \\u0000\"}")
            .expect("hằng số")
            .into_raw(),
    }
}

/// Đọc chuỗi JSON từ con trỏ C (null ⇒ chuỗi rỗng).
fn doc_json(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned()
}

fn doc_yeu_cau(ptr: *const c_char) -> Result<serde_json::Value, String> {
    let s = doc_json(ptr);
    if s.trim().is_empty() {
        return Err("yêu cầu rỗng (cần JSON có `entry`)".into());
    }
    serde_json::from_str(&s).map_err(|e| format!("JSON yêu cầu sai: {e}"))
}

fn truong(v: &serde_json::Value, ten: &str) -> Option<String> {
    v.get(ten).and_then(|x| x.as_str()).map(str::to_owned)
}

/// # Safety
/// `ptr` phải là chuỗi do `visd_version`/`visd_run`/`visd_check` trả về, chưa được free.
#[no_mangle]
pub unsafe extern "C" fn visd_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

/// Chuỗi nhận diện engine (JSON); người gọi `visd_free` sau khi dùng.
#[no_mangle]
pub extern "C" fn visd_version() -> *mut c_char {
    let version = env!("CARGO_PKG_VERSION");
    tra_json(format!("{{\"engine\":\"ViScript\",\"version\":\"{version}\"}}"))
}

/// Chạy chương trình ViScript.
#[no_mangle]
pub extern "C" fn visd_run(ptr: *const c_char) -> *mut c_char {
    let ket_qua = catch_unwind(AssertUnwindSafe(|| {
        let req = match doc_yeu_cau(ptr) {
            Ok(r) => r,
            Err(e) => return loi_json(&e),
        };
        let Some(tep) = truong(&req, "entry") else {
            return loi_json("thiếu trường `entry` (đường dẫn tệp chính)");
        };
        let args: Vec<String> = req
            .get("args")
            .and_then(|a| a.as_array())
            .map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_owned)).collect())
            .unwrap_or_default();
        let dung_vm = req.get("use_vm").and_then(|b| b.as_bool()).unwrap_or(false);
        let co_no_extern = req.get("no_extern").and_then(|b| b.as_bool()).unwrap_or(false);
        let strict_caps = req.get("strict_caps").and_then(|b| b.as_bool()).unwrap_or(false);
        let giai_thich = req.get("explain_perms").and_then(|b| b.as_bool()).unwrap_or(false);
        let text_de = truong(&req, "text");
        let goc: Option<PathBuf> = truong(&req, "dir").map(PathBuf::from);

        if let Some(d) = &goc {
            if let Err(e) = std::env::set_current_dir(d) {
                return loi_json(&format!("không đặt được thư mục làm việc `{d:?}`: {e}"));
            }
        }

        chay(
            &tep,
            text_de.as_deref(),
            &args,
            dung_vm,
            co_no_extern,
            strict_caps,
            giai_thich,
        )
    }));
    match ket_qua {
        Ok(s) => tra_json(s),
        Err(_) => tra_json(loi_json("engine gặp panic nội bộ — chương trình đã dừng")),
    }
}

/// Phân tích tĩnh (nạp module → hạ HIR → tyck), không chạy chương trình.
/// Kết quả: `{ ok, diags: [...], error? }` — dùng cho nút "Kiểm tra" trong editor.
#[no_mangle]
pub extern "C" fn visd_check(ptr: *const c_char) -> *mut c_char {
    let ket_qua = catch_unwind(AssertUnwindSafe(|| {
        let req = match doc_yeu_cau(ptr) {
            Ok(r) => r,
            Err(e) => return loi_json(&e),
        };
        let Some(tep) = truong(&req, "entry") else {
            return loi_json("thiếu trường `entry` (đường dẫn tệp chính)");
        };
        let text_de = truong(&req, "text");
        // Trên app lệnh ngoài không chạy được ý nghĩa gì ⇒ kiểm tra với `--no-extern`.
        match phan_tich(&tep, text_de.as_deref(), true) {
            Ok((_, _, _, chan_doan)) => {
                let arr: Vec<serde_json::Value> =
                    chan_doan.iter().map(|(rel, d)| diag_json(rel, d)).collect();
                format!("{}", serde_json::json!({ "ok": arr.is_empty(), "diags": arr }))
            }
            Err(KetQuaPhanTich::Diags(chan_doan)) => {
                let arr: Vec<serde_json::Value> =
                    chan_doan.iter().map(|(rel, d)| diag_json(rel, d)).collect();
                format!(
                    "{}",
                    serde_json::json!({
                        "ok": false,
                        "error": "chương trình có lỗi biên dịch",
                        "diags": arr,
                    })
                )
            }
            Err(KetQuaPhanTich::API(e)) => loi_json(&e),
        }
    }));
    match ket_qua {
        Ok(s) => tra_json(s),
        Err(_) => tra_json(loi_json("engine gặp panic nội bộ khi kiểm tra")),
    }
}

// ---------------------------------------------------------------------------
// Pipeline dùng chung
// ---------------------------------------------------------------------------

/// Kết quả phân tích tĩnh: lỗi biên dịch (diags) hay lỗi cấp API.
enum KetQuaPhanTich {
    Diags(Vec<(String, vis_syntax::Diagnostic)>),
    API(String),
}

type PhanTichOk = (
    Vec<vis_cli::modules::FileUnit>,
    String,
    vis_types::HirOutput,
    Vec<(String, vis_syntax::Diagnostic)>,
);

fn diag_json(rel: &str, d: &vis_syntax::Diagnostic) -> serde_json::Value {
    serde_json::json!({
        "file": rel,
        "code": d.code.short,
        "line": d.line,
        "col": d.col,
        "msg": d.message,
    })
}

fn diags_json(ma: u8, diags: &[(String, vis_syntax::Diagnostic)]) -> String {
    let arr: Vec<serde_json::Value> = diags.iter().map(|(rel, d)| diag_json(rel, d)).collect();
    format!(
        "{}",
        serde_json::json!({
            "ok": false,
            "exit": ma,
            "stdout": "",
            "steps": 0,
            "diags": arr,
        })
    )
}

fn loi_json(e: &str) -> String {
    format!(
        "{}",
        serde_json::json!({ "ok": false, "error": e, "stdout": "", "steps": 0, "diags": [] })
    )
}

/// Nạp module + hạ HIR + tyck — phần dùng chung cho `chay` và `visd_check`.
/// Trả `(files, text_tệp_chính, HirOutput, chan_doan)`.
fn phan_tich(
    tep: &str,
    text_de: Option<&str>,
    co_no_extern: bool,
) -> Result<PhanTichOk, KetQuaPhanTich> {
    let loaded = match text_de {
        Some(t) => modules::load_full_voi_text(tep, t, !co_no_extern, true),
        None => modules::load_with(tep, !co_no_extern),
    }
    .map_err(|e| KetQuaPhanTich::API(format!("không nạp được `{tep}`: {e:?}")))?;
    if !loaded.diags.is_empty() {
        return Err(KetQuaPhanTich::Diags(loaded.diags.clone()));
    }
    let text = text_cua_chinh(&loaded, tep, text_de);
    let files = loaded.files;
    let h = vis_types::HirOutput {
        hir: loaded.hir,
        diagnostics: Vec::new(),
        symbols: loaded.symbols,
        types: loaded.types,
        error: None,
    };
    let chan_doan: Vec<(String, vis_syntax::Diagnostic)> =
        loaded.diags.iter().map(|(rel, d)| (rel.clone(), d.clone())).collect();
    Ok((files, text, h, chan_doan))
}

/// Văn bản tệp chính: buffer editor nếu có, đĩa nếu không.
fn text_cua_chinh(loaded: &modules::Loaded, tep: &str, text_de: Option<&str>) -> String {
    if let Some(t) = text_de {
        return t.to_string();
    }
    loaded
        .tep_chinh()
        .map(|f| f.text.clone())
        .unwrap_or_else(|| std::fs::read_to_string(tep).unwrap_or_default())
}

/// Vòng chạy chính — trùng pipeline `vis run` của CLI: nạp module → quyền `cap` → interp/VM.
#[allow(clippy::too_many_arguments)]
fn chay(
    tep: &str,
    text_de: Option<&str>,
    args: &[String],
    dung_vm: bool,
    co_no_extern: bool,
    strict_caps: bool,
    giai_thich: bool,
) -> String {
    let (files, text, mut h, chan_doan) = match phan_tich(tep, text_de, co_no_extern) {
        Ok(k) => k,
        Err(KetQuaPhanTich::Diags(d)) => return diags_json(2, &d),
        Err(KetQuaPhanTich::API(e)) => return loi_json(&e),
    };
    let che_do = if tep.ends_with(".vish") {
        vis_syntax::Mode::Command
    } else {
        vis_syntax::Mode::Script
    };
    // ST-93 (VD-111): trong `.vish`, pipeline cấp tệp là chương trình; `fn main` chỉ khai `cap`.
    if che_do == vis_syntax::Mode::Command
        && !h.hir.stmts.is_empty()
        && h.hir
            .items
            .iter()
            .any(|it| matches!(it, vis_types::HItem::Fn(f) if f.name == "main"))
    {
        h.hir
            .items
            .retain(|it| !matches!(it, vis_types::HItem::Fn(f) if f.name == "main"));
    }
    // VD-124: chương trình dùng gói (`use pkg.*`) ⇒ siết quyền mặc định, khớp `vis run`.
    let co_pkg = files.iter().any(|f| f.rel.starts_with("pkg/"));
    if co_pkg && !strict_caps {
        eprintln!("visd: cảnh báo: chương trình dùng gói — KHÔNG siết quyền");
    }
    let ds_cap = quyen::ds_cap(&text, che_do);
    let goc = std::env::current_dir().unwrap_or_default();
    let quyen = match quyen::tao(&ds_cap, &[], &goc, strict_caps || co_pkg) {
        Ok(q) => q,
        Err(e) => return loi_json(&format!("quyền sai: {e}")),
    };
    let co_ngoai = che_do == vis_syntax::Mode::Command && !co_no_extern;

    // Chạy trong luồng stack lớn (ST-15: cap đệ quy 10^4 khung × ~8 KiB ⇒ cần 256 MiB).
    let args_vec = args.to_vec();
    let text_ref = &text;
    let hir_ref = &h.hir;
    let symbols_ref = &h.symbols;
    let types_ref = &h.types;
    let chan_doan_ref: Vec<vis_syntax::Diagnostic> =
        chan_doan.iter().map(|(_, d)| d.clone()).collect();
    let ket_qua: Result<
        (String, Vec<serde_json::Value>, usize, bool, Option<String>),
        String,
    > = std::thread::scope(|scope| {
        let handle = std::thread::Builder::new()
            .name("visd-run".into())
            .stack_size(256 * 1024 * 1024)
            .spawn_scoped(scope, move || {
                // Như CLI: runner **chương trình ngoài** và host **hệ tệp** là hai đối tượng
                // riêng (host fs là `Runner` đóng vai FsHost, không mượn chung một runner).
                let mut runner = Runner {
                    giai_thich,
                    cho_phep_proc: quyen.cho_phep_proc(),
                    allow_proc: quyen.allow_proc(),
                    ..Runner::default()
                };
                let mut fs_tho = Runner {
                    giai_thich,
                    ..Runner::default()
                };
                let mut net_tho = Net::moi(giai_thich);
                let mut fs = FsGuard {
                    trong: &mut fs_tho,
                    quyen: &quyen,
                };
                let mut net = NetGuard {
                    trong: &mut net_tho,
                    quyen: &quyen,
                };
                let ngoai_host: Option<&mut dyn vis_interp::builtin::Ngoai> =
                    if co_ngoai { Some(&mut runner) } else { None };
                let ra = if dung_vm {
                    match vis_bytecode::compile_kiem(
                        hir_ref,
                        symbols_ref,
                        text_ref,
                        &chan_doan_ref,
                    ) {
                        Ok(m) => vis_vm::run_with_full_hosts_caps(
                            &m,
                            text_ref,
                            &args_vec,
                            ngoai_host,
                            Some(&mut fs),
                            Some(&mut net),
                            // VD-241 (Gate 1): VisDroid không gắn host CSDL —
                            // `None` ⇒ std.sqlite.* ⇒ VS0604 theo cap.
                            None,
                            &quyen.gia_tri(),
                        ),
                        Err(e) => {
                            // ST-56b (VD-97 (5)): lỗi codegen ⇒ exit ≠ 0, kèm chẩn đoán.
                            return (
                                String::new(),
                                vec![],
                                0usize,
                                true,
                                Some(format!("vis run --vm: codegen lỗi: {e}")),
                            );
                        }
                    }
                } else {
                    vis_interp::run_with_hosts_caps(
                        text_ref,
                        hir_ref,
                        symbols_ref,
                        types_ref,
                        &args_vec,
                        ngoai_host,
                        Some(&mut fs),
                        Some(&mut net),
                        // VD-241 (Gate 1): VisDroid không gắn host CSDL —
                        // `None` ⇒ std.sqlite.* ⇒ VS0604 theo cap.
                        None,
                        &quyen.gia_tri(),
                    )
                };
                let diags: Vec<serde_json::Value> = ra
                    .diagnostics
                    .iter()
                    .map(|d| diag_json("", d))
                    .collect();
                (ra.stdout, diags, ra.steps, false, None::<String>)
            })
            .map_err(|e| format!("không tạo được luồng chạy: {e}"))?;
        handle
            .join()
            .map_err(|_| "luồng chạy lỗi (panic)".to_string())
    });
    let (stdout, diags, steps, loi_codegen, loi_msg) = match ket_qua {
        Ok(t) => t,
        Err(e) => return loi_json(&e),
    };
    let mut root = serde_json::json!({
        "ok": !loi_codegen && diags.is_empty(),
        "exit": if loi_codegen || !diags.is_empty() { 1 } else { 0 },
        "stdout": stdout,
        "steps": steps,
        "diags": diags,
    });
    if let Some(m) = loi_msg {
        root["error"] = serde_json::Value::String(m);
    }
    root.to_string()
}
