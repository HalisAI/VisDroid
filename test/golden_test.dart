// SPDX-License-Identifier: MIT
/// Chụp golden từng màn hình của app (engine giả + font thật) — dùng để
/// xem lại giao diện: flutter test --update-goldens test/golden_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visdroid/core/run_history.dart';
import 'package:visdroid/core/settings.dart';
import 'package:visdroid/core/vis_engine.dart';
import 'package:visdroid/main.dart';
import 'package:visdroid/screens/run_screen.dart';

/// Cảnh mở rộng (màn chạy, find bar...) — bật sau khi smoke pass.
const bool full = bool.fromEnvironment('GOLDEN_FULL', defaultValue: false);

/// Engine giả — trả kết quả có nội dung thực tế để ảnh gần như thật.
class MockEngine implements ScriptEngine {
  MockEngine({this.diags = const [], this.stdoutText = '', this.exit = 0});

  final List<Diag> diags;
  final String stdoutText;
  final int exit;

  @override
  Future<RunResult> runScript({
    required String entry,
    String? text,
    required String dir,
    List<String> args = const [],
    bool useVm = false,
    bool strictCaps = false,
    bool noExtern = false,
  }) async {
    return RunResult(
      ok: exit == 0 && diags.isEmpty,
      exit: exit,
      stdout: stdoutText,
      steps: 42,
      diags: diags,
    );
  }

  @override
  Future<List<Diag>> checkScript({
    required String entry,
    String? text,
  }) async =>
      diags;

  @override
  Future<String> versionInfo() async => 'ViScript 0.4.2 (mock)';
}

const _fontDir =
    '/home/z/my-project/tools/flutter/bin/cache/artifacts/material_fonts';

Future<void> _reg(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final data = await File('$_fontDir/$f').readAsBytes();
    loader.addFont(Future.value(ByteData.view(data.buffer)));
  }
  await loader.load();
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _reg(
      'Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await _reg('monospace', ['Roboto-Regular.ttf']);
  await _reg('MaterialIcons', ['MaterialIcons-Regular.otf']);

  // Giới hạn chờ settle: treo thì bỏ qua chứ không treo cả suite.
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

  Directory dir;

  /// Nạp app với engine giả; `lastFile` cho Shell tự mở tệp sau khi boot.
  Future<void> boot(
    WidgetTester tester, {
    Map<String, String> prefs = const {},
    MockEngine? engine,
    RunHistoryStore? history,
  }) async {
    dir = Directory(
        '/tmp/visdroid_golden_${DateTime.now().millisecondsSinceEpoch}');
    dir.createSync(recursive: true);
    const files = MethodChannel('visdroid/filesDir');
    const prefsCh = MethodChannel('visdroid/prefs');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(files, (m) async => dir.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(prefsCh,
            (m) async => m.method == 'get' ? jsonEncode(prefs) : null);
    final store = await PrefsStore.load();
    await tester.pumpWidget(VisDroidApp(
      state: AppState(store),
      engine: engine ?? MockEngine(stdoutText: 'Xin chào, ViScript!'),
      history: history ?? RunHistoryStore(),
    ));
    await settle(tester);
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(824, 1784);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('01 welcome', (tester) async {
    phone(tester);
    await boot(tester);
    await expectLater(
        find.byType(VisDroidApp), matchesGoldenFile('goldens/01-welcome.png'));
  });

  testWidgets('02 editor light', (tester) async {
    phone(tester);
    await boot(tester, prefs: {'lastFile': 'xin-chao.vis'});
    await expectLater(find.byType(VisDroidApp),
        matchesGoldenFile('goldens/02-editor-light.png'));
  });

  testWidgets('03 editor dark', (tester) async {
    phone(tester);
    await boot(tester, prefs: {'themeMode': '2', 'lastFile': 'ham.vis'});
    await expectLater(find.byType(VisDroidApp),
        matchesGoldenFile('goldens/03-editor-dark.png'));
  });

  testWidgets('04 editor find bar', (tester) async {
    if (!full) return;
    phone(tester);
    await boot(tester, prefs: {'lastFile': 'xin-chao.vis'});
    await tester.tap(find.byIcon(Icons.search));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'print');
    await settle(tester);
    await expectLater(find.byType(VisDroidApp),
        matchesGoldenFile('goldens/04-editor-find.png'));
  });

  testWidgets('05 run screen success (light)', (tester) async {
    if (!full) return;
    phone(tester);
    await boot(tester,
        prefs: {'lastFile': 'xin-chao.vis'},
        engine: MockEngine(
            stdoutText:
                'Xin chào, ViScript!\n1kb + 1kib = 2048b\n2h + 30m = 9000000ms'));
    await tester.tap(find.byIcon(Icons.play_arrow));
    await settle(tester);
    await expectLater(find.byType(RunScreen),
        matchesGoldenFile('goldens/05-run-success.png'));
  });

  testWidgets('06 run screen success (dark)', (tester) async {
    if (!full) return;
    phone(tester);
    await boot(tester,
        prefs: {'themeMode': '2', 'lastFile': 'don-vi.vis'},
        engine:
            MockEngine(stdoutText: '1kb + 1kib = 2048b\n500mb = 524288000b'));
    await tester.tap(find.byIcon(Icons.play_arrow));
    await settle(tester);
    await expectLater(find.byType(RunScreen),
        matchesGoldenFile('goldens/06-run-dark.png'));
  });

  testWidgets('07 run screen có lỗi', (tester) async {
    if (!full) return;
    phone(tester);
    await boot(tester,
        prefs: {'lastFile': 'xin-chao.vis'},
        engine: MockEngine(
          diags: [
            Diag(
              file: 'xin-chao.vis',
              code: 'VS0103',
              line: 2,
              col: 5,
              msg: 'Kiểu không khớp: mong đợi `str`, nhận được `int`.',
            ),
            Diag(
              file: 'xin-chao.vis',
              code: 'VS0501',
              line: 4,
              col: 1,
              msg: 'Chưa khai báo cap `fs` mà truy cập tệp.',
            ),
          ],
          exit: 1,
        ));
    await tester.tap(find.byIcon(Icons.play_arrow));
    await settle(tester);
    await expectLater(find.byType(RunScreen),
        matchesGoldenFile('goldens/07-run-diags.png'));
  });

  testWidgets('08 run screen lịch sử', (tester) async {
    if (!full) return;
    phone(tester);
    final history = RunHistoryStore();
    history.add(RunHistoryItem(
      time: DateTime(2026, 11, 18, 9, 12, 33),
      file: 'don-vi.vis',
      checkOnly: false,
      ok: true,
      exit: 0,
      steps: 42,
      preview: '1kb + 1kib = 2048b',
      durationMs: 12,
    ));
    history.add(RunHistoryItem(
      time: DateTime(2026, 11, 18, 9, 10, 2),
      file: 'xin-chao.vis',
      checkOnly: false,
      ok: false,
      exit: 1,
      steps: 7,
      preview: 'VS0103 Kiểu không khớp: mong đợi `str`, nhận được `int`.',
      durationMs: 8,
    ));
    history.add(RunHistoryItem(
      time: DateTime(2026, 11, 18, 9, 8, 41),
      file: 'ham.vis',
      checkOnly: true,
      ok: true,
      exit: 0,
      steps: 0,
      preview: 'Không có lỗi — chương trình sạch!',
      durationMs: 5,
    ));
    await boot(tester,
        prefs: {'lastFile': 'xin-chao.vis'},
        engine: MockEngine(stdoutText: 'Xin chào, ViScript!'),
        history: history);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await settle(tester);
    await expectLater(find.byType(RunScreen),
        matchesGoldenFile('goldens/08-run-history.png'));
  });

  testWidgets('09 files list', (tester) async {
    if (!full) return;
    phone(tester);
    await boot(tester, prefs: {'lastFile': 'xin-chao.vis'});
    await tester.tap(find.text('Tệp'));
    await settle(tester);
    await expectLater(find.byType(VisDroidApp),
        matchesGoldenFile('goldens/09-files.png'));
  });

  testWidgets('10 settings', (tester) async {
    phone(tester);
    await boot(tester);
    await tester.tap(find.text('Cài đặt'));
    await settle(tester);
    await expectLater(find.byType(VisDroidApp),
        matchesGoldenFile('goldens/10-settings.png'));
  });

  testWidgets('11 cheat sheet', (tester) async {
    phone(tester);
    await boot(tester);
    await tester.tap(find.text('Cài đặt'));
    await settle(tester);
    await tester.tap(find.text('Cheat sheet ViScript'));
    await settle(tester);
    await expectLater(find.byType(VisDroidApp),
        matchesGoldenFile('goldens/11-cheatsheet.png'));
  });
}
