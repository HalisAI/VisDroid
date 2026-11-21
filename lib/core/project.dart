// SPDX-License-Identifier: MIT
/// Dịch vụ tệp dự án: mọi tệp `.vis`/`.vish` của người dùng nằm trong thư mục
/// `Documents/vis/` (tách khỏi cache để backup/restore hệ thống vẫn giữ được).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel, rootBundle;

class VisProject {
  VisProject._(this.root);

  /// Tạo dự án tại thư mục bất kỳ — dùng cho test/preview.
  factory VisProject.at(Directory dir) {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return VisProject._(dir);
  }

  /// Thư mục gốc dự án.
  final Directory root;

  static VisProject? _instance;

  static Future<VisProject> instance() async {
    final cached = _instance;
    if (cached != null) return cached;
    const channel = MethodChannel('visdroid/filesDir');
    final filesDir = await channel.invokeMethod<String>('get');
    final docs = Directory(filesDir!);
    final dir = Directory('${docs.path}${Platform.pathSeparator}vis');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _instance = VisProject._(dir);
  }

  String pathFor(String name) {
    // Phòng thủ sâu: mọi lối UI đã lọc qua validName, nhưng pathFor là API
    // công khai (run_screen gọi trực tiếp) — chặn luôn ký tự đi đường trước
    // khi nối vào đường dẫn, không cho tệp rơi ra ngoài thư mục dự án.
    if (name.isEmpty ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('..')) {
      throw ArgumentError('tên tệp không hợp lệ: "$name"');
    }
    return '${root.path}${Platform.pathSeparator}$name';
  }

  /// Danh sách tệp `.vis`/`.vish` sắp theo tên.
  List<FileSystemEntity> listFiles() {
    final items = root
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.vis') || f.path.endsWith('.vish'))
        .toList();
    items.sort((a, b) => a.path.compareTo(b.path));
    return items;
  }

  bool exists(String name) => File(pathFor(name)).existsSync();

  File create(String name, {String content = ''}) {
    final f = File(pathFor(name));
    f.writeAsStringSync(content);
    return f;
  }

  String read(String name) {
    // allowMalformed: tệp hỏng (UTF-8 gãy, byte lạ) hiện ký tự thay thế thay
    // vì ném FormatException — màn soạn thảo mở được, không sập vì một tệp.
    return utf8.decode(
      File(pathFor(name)).readAsBytesSync(),
      allowMalformed: true,
    );
  }

  void write(String name, String content) {
    final f = File(pathFor(name));
    // Ghi nguyên tử: tệp tạm CÙNG thư mục (flush xuống đĩa) rồi rename đè —
    // hụt điện giữa chừng chỉ để lại .tmp, nội dung cũ của tệp .vis còn nguyên.
    final tmp = File('${f.path}.tmp');
    try {
      tmp.writeAsStringSync(content, flush: true);
      tmp.renameSync(f.path);
    } catch (_) {
      if (tmp.existsSync()) tmp.deleteSync();
      rethrow;
    }
  }

  void rename(String oldName, String newName) {
    File(pathFor(oldName)).renameSync(pathFor(newName));
  }

  void delete(String name) {
    final f = File(pathFor(name));
    if (f.existsSync()) f.deleteSync();
  }

  /// Tên tệp hợp lệ: không rỗng, không chứa '/' '\' '..', đuôi .vis/.vish.
  static bool validName(String name) {
    if (name.isEmpty || name.length > 100) return false;
    if (name.contains('/') || name.contains('\\')) return false;
    if (name.startsWith('.') || name.contains('..')) return false;
    final lower = name.toLowerCase();
    return lower.endsWith('.vis') || lower.endsWith('.vish');
  }

  /// Chuẩn hoá tên: thêm đuôi `.vis` nếu thiếu.
  static String normalizeName(String raw) {
    final n = raw.trim();
    if (n.toLowerCase().endsWith('.vis') || n.toLowerCase().endsWith('.vish')) {
      return n;
    }
    return '$n.vis';
  }

  /// Gieo các ví dụ mẫu đi kèm lần đầu mở app (không ghi đè tệp đã có).
  Future<List<String>> seedExamplesIfNeeded() async {
    final created = <String>[];
    const examples = [
      'xin-chao.vis',
      'ham.vis',
      'danh-sach.vis',
      'don-vi.vis',
    ];
    for (final name in examples) {
      if (exists(name)) continue;
      try {
        final text =
            await rootBundle.loadString('assets/examples/$name');
        create(name, content: text);
        created.add(name);
      } catch (_) {
        // Thiếu asset nào đó thì bỏ qua — không chặn việc dùng app.
      }
    }
    return created;
  }
}
