// SPDX-License-Identifier: MIT
/// Smoke test widget: highlighter + màn chọn Mê cung pumpWidget thật.
///
/// Màn chọn được pump TRỰC TIẾP (không qua Shell để không cần I/O dự án)
/// với kênh `visdroid/prefs` giả — cùng kỹ thuật mock của golden_test nhưng
/// KHÔNG cần font/golden nên CI chạy được. Thiếu plugin (SoundFx) hoặc ảnh
/// decode xong muộn (SpriteSet) chỉ là treo im lặng — như golden đã chạy,
/// không làm test chết.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show TextSpan;
import 'package:flutter_test/flutter_test.dart';
import 'package:visdroid/core/highlighter.dart';
import 'package:visdroid/core/settings.dart';
import 'package:visdroid/core/vis_engine.dart';
import 'package:visdroid/game/levels.dart';
import 'package:visdroid/game/progress.dart';
import 'package:visdroid/screens/level_select_screen.dart';

/// Engine giả — màn chọn chỉ giữ tham chiếu, không gọi FFI trong smoke test.
class FakeEngine implements ScriptEngine {
  @override
  Future<RunResult> runScript({
    required String entry,
    String? text,
    required String dir,
    List<String> args = const [],
    bool useVm = false,
    bool strictCaps = false,
    bool noExtern = false,
  }) async =>
      RunResult(ok: true, exit: 0, stdout: '', steps: 0, diags: const []);

  @override
  Future<List<Diag>> checkScript({
    required String entry,
    String? text,
  }) async =>
      const [];

  @override
  Future<String> versionInfo() async => 'ViScript 0 (fake)';
}

/// Mock kênh `visdroid/prefs` trả map prefs `raw` (định dạng MainActivity trả)
/// rồi nạp AppState + GameProgress từ đó — như app đọc SharedPreferences thật.
Future<(AppState, GameProgress)> _bootPrefs(Map<String, String> raw) async {
  const ch = MethodChannel('visdroid/prefs');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(ch, (m) async {
    if (m.method != 'get') return null;
    return jsonEncode(raw);
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(ch, null));
  final store = await PrefsStore.load();
  final progress = GameProgress(store);
  await progress.load();
  return (AppState(store), progress);
}

/// Viewport cao bất thường để ListView dựng HẾT 15 thẻ — assert đếm được
/// chính xác số thẻ khoá/mở mà không cần kéo cuộn.
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Giới hạn chờ settle: treo thì bỏ qua chứ không treo cả suite (mẫu golden).
Future<void> settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 15));
  } catch (_) {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
}

void main() {
  test('highlighter phủ đủ văn bản và nhận từ khoá/chuỗi/chú thích', () {
    const src = 'let ten = "Minh"  # chú thích\nprint("{ten}")';
    final span = buildHighlightTextSpan(src, HighlightColors.light);
    final covered = span.children!.whereType<TextSpan>().fold<int>(
        0, (acc, c) => acc + (c.text?.length ?? 0));
    expect(covered, src.length, reason: 'span phải phủ hết văn bản');
    // Có ít nhất một span từ khoá (màu keyword) và một span chuỗi.
    expect(span.children!.any((c) => c.style?.color == HighlightColors.light.keyword),
        isTrue);
    expect(span.children!.any((c) => c.style?.color == HighlightColors.light.string),
        isTrue);
    expect(span.children!.any((c) => c.style?.color == HighlightColors.light.comment),
        isTrue);
  });

  test('highlighter không RangeError với UTF-16 gãy (surrogate đơn)', () {
    // Cả hai chuỗi dưới đây từng làm scanner trôi QUÁ cuối văn bản (nhảy 2
    // khi không còn đủ cặp surrogate) → substring khi dựng TextSpan ném
    // RangeError ngay lúc người chơi gõ.
    const cases = ["let a = 'x\uD83D", 'let \uD800\uD800'];
    for (final src in cases) {
      final span = buildHighlightTextSpan(src, HighlightColors.light);
      final covered = span.children!.whereType<TextSpan>().fold<int>(
          0, (acc, c) => acc + (c.text?.length ?? 0));
      expect(covered, src.length, reason: 'span phải phủ hết "$src"');
    }
  });

  testWidgets('AppState: themeMode index lạ về hệ thống thay vì RangeError',
      (tester) async {
    // Prefs file hỏng / ghi từ bản app khác — '7' vượt ThemeMode.values.
    final (state, _) = await _bootPrefs({'themeMode': '7', 'fontSize': '99'});
    // So tên thay vì class: app dùng ThemeMode của material_ui, test dùng của
    // flutter/material — hai enum khác class nhưng in giống nhau.
    expect(state.themeMode.name, 'system');
    expect(state.fontSize, 24.0); // kẹp đúng mốc slider cỡ chữ (max 24).
  });

  testWidgets('AppState: cỡ chữ dưới mốc → kẹp 10', (tester) async {
    final (state, _) = await _bootPrefs({'fontSize': '0.5'});
    expect(state.fontSize, 10.0);
  });

  testWidgets('màn chọn Mê cung: tổng sao, thẻ mở/khoá hiển thị đúng',
      (tester) async {
    _tallView(tester);
    final (state, progress) =
        await _bootPrefs({'game_progress_v2': jsonEncode({'stars': {'1': 3}})});
    await tester.pumpWidget(MaterialApp(
      home: LevelSelectScreen(
        engine: FakeEngine(),
        appState: state,
        progress: progress,
      ),
    ));
    await settle(tester);
    // Header: 3 sao màn 1 / 3 sao mỗi màn.
    expect(find.text('3/${kGameLevels.length * 3}'), findsOneWidget);
    // Thẻ màn 1 đã mở — tên màn hiện lên.
    expect(find.text(kGameLevels[0].title), findsWidgets);
    // Màn 1 có sao → màn 1 và 2 mở, còn lại đúng số thẻ bị khoá.
    expect(find.byIcon(Icons.lock_outline),
        findsNWidgets(kGameLevels.length - 2));
    // Chưa phá đảo → không có nhãn chúc mừng.
    expect(find.text('Phá đảo! Bạn đã hoàn thành mọi màn — coder ViScript chính thức 🏆'),
        findsNothing);
  });

  testWidgets('màn chọn Mê cung: phá đảo hiện nhãn chúc mừng, hết khoá',
      (tester) async {
    _tallView(tester);
    final (state, progress) = await _bootPrefs({
      'game_progress_v2':
          jsonEncode({'stars': {for (final l in kGameLevels) l.id: 3}}),
    });
    await tester.pumpWidget(MaterialApp(
      home: LevelSelectScreen(
        engine: FakeEngine(),
        appState: state,
        progress: progress,
      ),
    ));
    await settle(tester);
    expect(find.text('${kGameLevels.length * 3}/${kGameLevels.length * 3}'),
        findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(find.text('Phá đảo! Bạn đã hoàn thành mọi màn — coder ViScript chính thức 🏆'),
        findsOneWidget);
  });
}
