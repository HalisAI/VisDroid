// SPDX-License-Identifier: MIT
/// Tiến độ vượt ải của Mê cung ViScript — lưu cục bộ qua PrefsStore.
///
/// Mô hình: màn đầu mở sẵn, màn sau chỉ mở khi màn trước có ≥1 sao. Mỗi màn
/// lưu số sao tốt nhất (1–3), số bước tốt nhất và code cuối cùng. Toàn bộ nằm
/// trong một key JSON để dễ backup/reset.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'levels.dart';
import 'maze.dart';
import '../core/settings.dart';

class GameProgress extends ChangeNotifier {
  GameProgress(this._prefs);

  final PrefsStore _prefs;

  static const String _key = 'game_progress_v2';

  /// levelId → sao tốt nhất (1..3).
  final Map<String, int> stars = {};

  /// levelId → số bước tốt nhất.
  final Map<String, int> bestSteps = {};

  /// levelId → code cuối cùng (tự lưu khi chạy/quay về màn chọn).
  final Map<String, String> code = {};

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = _prefs.get(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final st = j['stars'] as Map<String, dynamic>? ?? {};
      final bs = j['best'] as Map<String, dynamic>? ?? {};
      final cd = j['code'] as Map<String, dynamic>? ?? {};
      stars.clear();
      stars.addEntries(
        st.entries.whereType<MapEntry<String, dynamic>>().map(
              (e) => MapEntry(e.key, (e.value as num).toInt()),
            ),
      );
      bestSteps.clear();
      bestSteps.addEntries(
        bs.entries.whereType<MapEntry<String, dynamic>>().map(
              (e) => MapEntry(e.key, (e.value as num).toInt()),
            ),
      );
      code.clear();
      code.addEntries(
        cd.entries.whereType<MapEntry<String, dynamic>>().map(
              (e) => MapEntry(e.key, e.value as String),
            ),
      );
    } catch (_) {
      // Dữ liệu hỏng thì coi như chưa chơi — không làm app chết.
    }
  }

  Future<void> _save() async {
    final raw = jsonEncode({
      'stars': stars,
      'best': bestSteps,
      'code': code,
    });
    try {
      await _prefs.set(_key, raw);
    } catch (_) {
      // Không có platform channel (test/preview) — giữ trong RAM.
    }
    notifyListeners();
  }

  int starsOf(MazeLevel lv) => stars[lv.id] ?? 0;

  int? bestOf(MazeLevel lv) => bestSteps[lv.id];

  String codeOf(MazeLevel lv) => code[lv.id] ?? lv.starterCode;

  /// Màn i mở khi là màn đầu, hoặc màn trước đã có sao.
  bool isUnlocked(int index) {
    if (index <= 0) return true;
    if (index >= kGameLevels.length) return false;
    return (stars[kGameLevels[index - 1].id] ?? 0) > 0;
  }

  /// Màn đầu tiên chưa có sao (dùng để tô sáng "chơi tiếp").
  int get currentIndex {
    for (var i = 0; i < kGameLevels.length; i++) {
      if (starsOf(kGameLevels[i]) == 0) return i;
    }
    return kGameLevels.length - 1; // phá đảo — trả màn cuối.
  }

  bool get allDone => stars.length == kGameLevels.length;

  int get totalStars => stars.values.fold(0, (a, b) => a + b);

  int get maxStars => kGameLevels.length * 3;

  /// Chấm sao theo số bước thực thi: ≤ par = 3★, ≤ par+4 = 2★, còn lại 1★.
  int starsFor(int steps, int par) {
    if (steps <= par) return 3;
    if (steps <= par + 4) return 2;
    return 1;
  }

  /// Ghi nhận thắng màn: giữ số sao/bước tốt nhất, tự notify.
  void recordWin(MazeLevel lv, int steps) {
    final s = starsFor(steps, lv.par);
    stars[lv.id] = s > starsOf(lv) ? s : starsOf(lv);
    final old = bestSteps[lv.id];
    if (old == null || steps < old) bestSteps[lv.id] = steps;
    _save();
  }

  void setCode(MazeLevel lv, String value) {
    code[lv.id] = value;
    _save();
  }

  /// Xoá sạch tiến độ (nút trong Cài đặt) — giữ nguyên code? Không: xoá cả.
  Future<void> reset() async {
    stars.clear();
    bestSteps.clear();
    code.clear();
    await _save();
  }
}
