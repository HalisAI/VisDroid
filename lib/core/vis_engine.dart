// SPDX-License-Identifier: MIT
/// Cầu nối FFI tới engine ViScript (`libvis_ffi.so`) — nhúng trực tiếp trong APK.
///
/// Giao thức JSON định nghĩa ở `native/ViScript/crates/vis-ffi/src/lib.rs`. Mọi
/// lệnh nặng chạy trong isolate riêng qua `Isolate.run` để UI không đơ.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// Kết quả chạy script.
class RunResult {
  RunResult({
    required this.ok,
    required this.exit,
    required this.stdout,
    required this.steps,
    required this.diags,
    this.error,
  });

  final bool ok;
  final int exit;
  final String stdout;
  final int steps;
  final List<Diag> diags;
  final String? error;

  factory RunResult.fromJson(Map<String, dynamic> j) => RunResult(
        ok: j['ok'] as bool? ?? false,
        exit: j['exit'] as int? ?? 1,
        stdout: j['stdout'] as String? ?? '',
        steps: j['steps'] as int? ?? 0,
        diags: ((j['diags'] as List?) ?? [])
            .whereType<Map>()
            .map(Diag.fromJson)
            .toList(),
        error: j['error'] as String?,
      );

  bool get clean => ok && diags.isEmpty && error == null;
}

/// Chẩn đoán biên dịch/runtime: `VSxxxx` + vị trí trong tệp.
class Diag {
  Diag({
    required this.file,
    required this.code,
    required this.line,
    required this.col,
    required this.msg,
  });

  final String file;
  final String code;
  final int line;
  final int col;
  final String msg;

  factory Diag.fromJson(Map<dynamic, dynamic> j) => Diag(
        file: j['file'] as String? ?? '',
        code: j['code'] as String? ?? 'VS0000',
        line: j['line'] as int? ?? 0,
        col: j['col'] as int? ?? 0,
        msg: j['msg'] as String? ?? '',
      );

  Map<String, dynamic> toMap() =>
      {'file': file, 'code': code, 'line': line, 'col': col, 'msg': msg};
}

/// Gọi hàm FFI trả chuỗi JSON, giải phóng cả hai phía bằng `visd_free`.
String _callJson(
  Pointer<Utf8> Function(Pointer<Utf8>) invoke,
  String request,
) {
  final req = request.toNativeUtf8();
  final out = invoke(req);
  try {
    return out.toDartString();
  } finally {
    malloc.free(out);
    malloc.free(req);
  }
}

/// Hàm mức isolate — mở thư viện trong isolate hiện tại rồi gọi.
/// Trả về JSON thô (String) để gửi về isolate chính.
String _ffiInvoke(String which, String request) {
  final lib = DynamicLibrary.open('libvis_ffi.so');
  switch (which) {
    case 'run':
      final fn = lib
          .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Utf8>)>>(
              'visd_run')
          .asFunction<Pointer<Utf8> Function(Pointer<Utf8>)>();
      return _callJson(fn, request);
    case 'check':
      final fn = lib
          .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Utf8>)>>(
              'visd_check')
          .asFunction<Pointer<Utf8> Function(Pointer<Utf8>)>();
      return _callJson(fn, request);
    case 'version':
      final fn = lib
          .lookup<NativeFunction<Pointer<Utf8> Function()>>('visd_version')
          .asFunction<Pointer<Utf8> Function()>();
      final out = fn();
      try {
        return out.toDartString();
      } finally {
        malloc.free(out);
      }
  }
  throw StateError('lệnh FFI lạ: $which');
}

class VisEngine {
  /// Mở thư viện engine một lần cho mỗi isolate khi gọi lệnh đầu tiên.
  VisEngine();

  static const String _soName = 'libvis_ffi.so';

  /// Kiểm tra thư viện nhúng có mở được không (gọi khi app khởi động).
  static bool get available {
    try {
      DynamicLibrary.open(_soName);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Chạy script: `entry` là đường dẫn tệp chính trên đĩa; `text` (nếu có)
  /// đè nội dung tệp chính để chạy buffer editor mà không cần lưu trước.
  Future<RunResult> runScript({
    required String entry,
    String? text,
    required String dir,
    List<String> args = const [],
    bool useVm = false,
    bool strictCaps = false,
    bool noExtern = false,
  }) async {
    final req = jsonEncode({
      'entry': entry,
      'text': ?text,
      'dir': dir,
      'args': args,
      'use_vm': useVm,
      'strict_caps': strictCaps,
      'no_extern': noExtern,
    });
    final raw = await Isolate.run(() => _ffiInvoke('run', req));
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j.containsKey('error') &&
        j['error'] != null &&
        (j['diags'] as List?)?.isEmpty == true) {
      throw EngineException(j['error'] as String);
    }
    return RunResult.fromJson(j);
  }

  /// Phân tích tĩnh (nạp → hạ → tyck), không chạy — dùng cho nút Kiểm tra.
  Future<List<Diag>> checkScript({
    required String entry,
    String? text,
  }) async {
    final req = jsonEncode({
      'entry': entry,
      'text': ?text,
    });
    final raw = await Isolate.run(() => _ffiInvoke('check', req));
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return ((j['diags'] as List?) ?? [])
        .whereType<Map>()
        .map((m) => Diag.fromJson(m))
        .toList();
  }

  /// Chuỗi nhận diện engine, ví dụ `ViScript 0.1.0`.
  Future<String> versionInfo() async {
    final raw = await Isolate.run(() => _ffiInvoke('version', ''));
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return '${j['engine']} ${j['version']}';
  }
}

class EngineException implements Exception {
  EngineException(this.message);
  final String message;
  @override
  String toString() => message;
}
