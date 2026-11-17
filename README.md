# VisDroid

**IDE ViScript cho Android** — viết, lưu và chạy ViScript ngay trên điện thoại, không cần mạng, không cần máy chủ.

VisDroid nhúng engine ViScript (biên dịch Rust thành `libvis_ffi.so`) thẳng vào APK và gọi qua Dart FFI: bấm nút **▶** là script chạy tức thì, stdout và chẩn đoán lỗi (mã `VSxxxx`, dòng:cột) hiện ngay trong bảng kết quả.

## Tính năng

- **Chạy tức thì** — nút tam giác ▶ tự lưu rồi chạy; đường interp mặc định, tuỳ chọn đường VM (bytecode) trong Cài đặt.
- **Tô màu cú pháp ViScript** — từ khoá, chuỗi có nội suy, số có đơn vị (`5mb`, `250ms`), chú thích `#`, doc-comment `##`; số dòng, thụt lề tự động, thanh phím nhanh (`⇥`, `{}`, `()`, `->`…).
- **Quản lý tệp** — tạo/mở/đổi tên/xoá tệp `.vis`/`.vish` trong thư mục dự án riêng của app; gieo sẵn ví dụ mẫu lần đầu mở.
- **Chẩn đoán thật từ engine** — nút Kiểm tra chạy phân tích tĩnh (nạp module → hạ HIR → tyck) **không chạy chương trình**; tap vào lỗi để nhảy tới dòng.
- **Tìm & thay thế** trong editor (đếm kết quả, next/prev, replace all), **đi tới dòng**, **thống kê tệp** (dòng/ký tự/kích thước).
- **Chấm đỏ gutter** báo dòng có lỗi từ lần chạy/kiểm tra gần nhất — tap vào lỗi để nhảy tới dòng.
- **Lịch sử chạy** trong bảng kết quả — xem lại exit code, số bước, thời gian; tap để chạy lại.
- **Cheat sheet ViScript** — tra cứu nhanh cú pháp ngay trong app (11 mục kèm code mẫu).
- **Cỡ chữ editor** điều chỉnh được, **tự động lưu** khi soạn (2.5s không gõ).
- **Giao diện Sáng/Tối**, hoặc theo hệ thống; **tiếng Việt mặc định**, đổi sang English trong Cài đặt.
- **Quyền `cap` của ViScript** — tuỳ chọn `--strict-caps`, `--no-extern` ngay trong app.

## Yêu cầu thiết bị

Android **7.1.1+** (API 25). ABI: `arm64-v8a`, `armeabi-v7a`, `x86_64`.

## Cấu trúc repo

```
lib/                    Ứng dụng Dart/Flutter (Dart 3.14)
  core/vis_engine.dart  Cầu FFI tới libvis_ffi.so (giao thức JSON)
  core/highlighter.dart Tokenizer tô màu ViScript
  core/project.dart     Quản lý tệp dự án + ví dụ mẫu
  screens/              Editor, Tệp, Cài đặt
android/app/src/main/jniLibs/<abi>/libvis_ffi.so   Engine nhúng (3 ABI)
native/ViScript         Fork ViScript + crate vis-ffi (lớp C-ABI)
native/build-so.sh      Biên dịch lại .so cho Android
assets/examples/        Ví dụ `.vis` đi kèm app
```

## Build từ đầu

1. Cài [Flutter 3.50](https://docs.flutter.dev/get-started/install) (Dart 3.14), Android SDK + NDK 27, [Rust](https://rustup.rs) với target `aarch64-linux-android`, `armeabi-v7a` → `armv7-linux-androideabi`, `x86_64-linux-android`.

2. Biên dịch engine (mất vài phút lần đầu):

   ```sh
   cd native && ./build-so.sh all
   ```

   Script tự dò NDK (`ANDROID_NDK=…` để ghi đè) và chép `.so` vào `jniLibs/`.

3. Build APK:

   ```sh
   flutter build apk --release
   ```

## Engine ViScript

ViScript là ngôn ngữ lập trình dễ học cho người Việt — cú pháp gọn như Python, kiểm tra kiểu như Rust: [vifast-oss/ViScript](https://github.com/vifast-oss/ViScript). Thư mục `native/ViScript` giữ fork với crate mới `vis-ffi` (hàm `visd_run` / `visd_check` / `visd_version`) và `vis-cli` tách phần thư viện để app dùng lại **nguyên** pipeline của `vis run` — cùng bảng chẩn đoán, cùng ngữ nghĩa quyền `cap`, cùng host fs/net.

License engine: MIT OR Apache-2.0 (giữ nguyên SPDX trong `native/ViScript`).

## Releases (GitHub Action)

Workflow [`.github/workflows/release.yml`](.github/workflows/release.yml) tự chạy khi một
release được publish: cài Flutter 3.50 + Rust (3 target Android) + NDK 27 trên
`ubuntu-latest`, biên dịch lại engine ViScript cho 3 ABI (`native/build-so.sh all`),
build APK release rồi **đính kèm APK vào chính bản phát hành đó**
(`VisDroid-<tag>.apk`). Cũng chạy được thủ công bằng nút *Run workflow* (APK ra
artifact thay vì attach).

Máy local không cần NDK thật khi chỉ build APK (engine `.so` đã committed):
`scripts/make_ndk_stub.sh <ndk-dir> 27.0.12077973` dựng stub đủ cho AGP.
