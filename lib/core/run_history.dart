// SPDX-License-Identifier: MIT
/// Kết quả chạy và lịch sử chạy dùng chung giữa màn Editor và màn Thực thi.
/// Store lịch sử nằm ở Shell nên lịch sử sống suốt phiên làm việc.
library;

import 'package:material_ui/material_ui.dart';

/// Một lần chạy/kiểm tra trong phiên làm việc.
class RunHistoryItem {
  RunHistoryItem({
    required this.time,
    required this.file,
    required this.checkOnly,
    required this.ok,
    required this.exit,
    required this.steps,
    required this.preview,
    required this.durationMs,
  });

  final DateTime time;
  final String file;

  /// `true` = lần chạy Kiểm tra tĩnh (không thực thi).
  final bool checkOnly;
  final bool ok;
  final int exit;
  final int steps;
  final String preview;
  final int durationMs;
}

/// Lịch sử chạy trong phiên — Shell giữ một instance duy nhất.
class RunHistoryStore extends ChangeNotifier {
  final List<RunHistoryItem> items = <RunHistoryItem>[];

  void add(RunHistoryItem item) {
    items.insert(0, item);
    if (items.length > 30) items.removeLast();
    notifyListeners();
  }

  void clear() {
    items.clear();
    notifyListeners();
  }
}
