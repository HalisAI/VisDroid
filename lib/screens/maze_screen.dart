// SPDX-License-Identifier: MIT
/// Màn chơi Mê cung ViScript (issue #1) — board + editor + hoạt ảnh robot.
///
/// Bấm Chạy: script chạy qua engine FFI trong sandbox như mọi script khác,
/// stdout được phân tích thành hàng lệnh (`lib/game/maze.dart`), robot thực
/// hiện lần lượt từng bước. Code của mỗi màn tự lưu vào PrefsStore.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart';

import '../core/l10n.dart';
import '../core/settings.dart';
import '../core/vis_engine.dart';
import '../game/maze.dart';
import '../widgets/code_field.dart';

class MazeScreen extends StatefulWidget {
  const MazeScreen({
    super.key,
    required this.engine,
    required this.prefs,
    required this.appState,
  });

  final ScriptEngine engine;
  final PrefsStore prefs;
  final AppState appState;

  @override
  State<MazeScreen> createState() => _MazeScreenState();
}

class _MazeScreenState extends State<MazeScreen> {
  int _levelIdx = 0;
  CodeController? _controller;
  final _focusNode = FocusNode();
  Timer? _timer;

  SimOutcome? _outcome;
  int _frameIdx = 0;
  bool _running = false;
  String? _banner; // thông báo lỗi biên dịch / phân tích / mô phỏng.
  Set<String> _done = {};

  MazeLevel get _level => kMazeLevels[_levelIdx];

  @override
  void initState() {
    super.initState();
    _done = (widget.prefs.get('game_done') ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .toSet();
    _loadLevel(0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  HighlightColors get _colors => Theme.of(context).brightness == Brightness.dark
      ? HighlightColors.dark
      : HighlightColors.light;

  void _loadLevel(int idx, {String? code}) {
    _timer?.cancel();
    final level = kMazeLevels[idx];
    final saved = code ??
        widget.prefs.get('game_code_${level.id}') ??
        level.starterCode;
    setState(() {
      _levelIdx = idx;
      _controller = CodeController(text: saved, colors: HighlightColors.light);
      _outcome = null;
      _frameIdx = 0;
      _banner = null;
      _running = false;
    });
  }

  void _switchLevel(int idx) {
    if (idx == _levelIdx) return;
    widget.prefs.set('game_code_${_level.id}', _controller?.text ?? '');
    _loadLevel(idx);
  }

  void _resetCode() {
    _timer?.cancel();
    setState(() {
      _controller = CodeController(text: _level.starterCode, colors: HighlightColors.light);
      _outcome = null;
      _frameIdx = 0;
      _banner = null;
    });
  }

  void _showHint() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t(ctx, S.gameHint),
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              SelectableText(_level.hint),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Chạy script → phân tích lệnh → mô phỏng → hoạt ảnh
  // ------------------------------------------------------------------

  Future<void> _run() async {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    final code = controller.text;
    await widget.prefs.set('game_code_${_level.id}', code);
    setState(() {
      _banner = null;
      _outcome = null;
      _frameIdx = 0;
      _running = true;
    });

    String stdoutText = '';
    try {
      // Mê cung không cần extern — chặn hẳn để game giữ sandbox hẹp nhất.
      final tmp = File('${Directory.systemTemp.path}${Platform.pathSeparator}'
          'vis_game_mecung.vis');
      await tmp.writeAsString(code);
      final res = await widget.engine.runScript(
        entry: tmp.path,
        dir: Directory.systemTemp.path,
        args: const [],
        useVm: widget.appState.useVm,
        strictCaps: widget.appState.strictCaps,
        noExtern: true,
      );
      stdoutText = res.stdout;
      if (res.diags.isNotEmpty) {
        final d = res.diags.first;
        _failBanner('${t(context, S.gameErrCompile)}: '
            '${t(context, S.gameAtLine).replaceFirst('{n}', '${d.line}')} '
            '${d.code} — ${d.msg}');
        return;
      }
      if (res.error != null && res.exit != 0) {
        _failBanner('${t(context, S.gameErrCompile)}: ${res.error}');
        return;
      }
    } catch (e) {
      _failBanner('$e');
      return;
    } finally {
      if (mounted) setState(() => _running = false);
    }

    final pr = parseCommands(stdoutText);
    if (!pr.ok) {
      final lineInfo = (pr.errorLine ?? 0) > 0
          ? '${t(context, S.gameAtLine).replaceFirst('{n}', '${pr.errorLine}')} — '
          : '';
      _failBanner('${t(context, S.gameErrParse)}: $lineInfo${pr.error}');
      return;
    }
    final oc = simulate(_level, pr.cmds);
    setState(() {
      _outcome = oc;
      _frameIdx = 0;
    });
    _animate();
  }

  void _failBanner(String msg) {
    if (!mounted) return;
    setState(() {
      _banner = msg;
      _outcome = null;
      _frameIdx = 0;
    });
  }

  void _animate() {
    final oc = _outcome;
    if (oc == null) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 400), (t) {
      if (_frameIdx >= oc.lastFrame) {
        t.cancel();
        if (oc.win && _frameIdx >= oc.frames.length - 1) _onWin();
        return;
      }
      setState(() => _frameIdx++);
      if (_frameIdx >= oc.lastFrame) {
        t.cancel();
        if (oc.win) _onWin();
      }
    });
  }

  Future<void> _onWin() async {
    final id = _level.id;
    _done.add(id);
    await widget.prefs.set('game_done', _done.join(','));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(ctx, S.gameWinTitle)),
        content: Text(t(ctx, S.gameWinBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t(ctx, S.cancel)),
          ),
          if (_levelIdx + 1 < kMazeLevels.length)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _switchLevel(_levelIdx + 1);
              },
              child: Text(t(ctx, S.gameNext)),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final oc = _outcome;
    final frame = oc == null
        ? SimFrame(at: _level.start, facing: _level.startFacing, picked: {})
        : oc.frames[_frameIdx];
    final bright = Theme.of(context).brightness;

    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, S.gameTitle)),
        actions: [
          IconButton(
            icon: const Icon(Icons.lightbulb_outline),
            tooltip: t(context, S.gameHint),
            onPressed: _showHint,
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: t(context, S.gameReset),
            onPressed: _resetCode,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Chọn màn
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (var i = 0; i < kMazeLevels.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          '${t(context, S.gameLevel)} ${kMazeLevels[i].id} · '
                          '${kMazeLevels[i].title}${_done.contains(kMazeLevels[i].id) ? ' ✓' : ''}',
                        ),
                        selected: i == _levelIdx,
                        onSelected: (_) => _switchLevel(i),
                      ),
                    ),
                ],
              ),
            ),
            // Nhiệm vụ
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${t(context, S.gameTask)}: ${_level.task}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            // Bàn chơi
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _level.cols / _level.rows,
                    child: CustomPaint(
                      painter: _MazePainter(
                        level: _level,
                        frame: frame,
                        bright: bright,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Banner trạng thái
            if (_banner != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _banner!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else if (oc != null && oc.win && _frameIdx >= oc.frames.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t(context, S.gameWinTitle),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            else if (oc != null && oc.failMsg != null && _frameIdx >= oc.failFrame)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${t(context, S.gameFail)}: ${oc.failMsg}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else if (oc != null && _running == false)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t(context, S.gameStep)
                        .replaceFirst('{i}', '${_frameIdx + 1}')
                        .replaceFirst('{n}', '${oc.frames.length}'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            // Editor
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: SizedBox(
                height: 190,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CodeField(
                      controller: _controller!,
                      focusNode: _focusNode,
                      colors: _colors,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
            // Nút chạy
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _run,
                    icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                    label: Text(_running ? t(context, S.gameStop) : t(context, S.run)),
                  ),
                  const SizedBox(width: 12),
                  if (oc != null && oc.stepCount > 0 && _banner == null)
                    Text(
                      t(context, S.gameStep)
                          .replaceFirst('{i}', '${_frameIdx + 1}')
                          .replaceFirst('{n}', '${oc.frames.length}'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vẽ bàn chơi: tường, sàn, món đồ, cờ, robot (vòng tròn + mũi hướng).
class _MazePainter extends CustomPainter {
  _MazePainter({
    required this.level,
    required this.frame,
    required this.bright,
  });

  final MazeLevel level;
  final SimFrame frame;
  final Brightness bright;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / level.cols;
    final floorPaint = Paint()
      ..color = bright == Brightness.dark
          ? const Color(0xFF1E2430)
          : const Color(0xFFEFF3F8);
    final wallPaint = Paint()
      ..color = bright == Brightness.dark
          ? const Color(0xFF39424F)
          : const Color(0xFF8CA0B3);
    final robotPaint = Paint()..color = const Color(0xFF2563EB);
    final bumpPaint = Paint()
      ..color = const Color(0xB3EF4444)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    for (var y = 0; y < level.rows; y++) {
      for (var x = 0; x < level.cols; x++) {
        final rect = Rect.fromLTWH(x * cell, y * cell, cell, cell);
        if (level.grid[y][x] == '#') {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect.deflate(1), Radius.circular(cell * 0.15)),
            wallPaint,
          );
        } else {
          canvas.drawRect(rect, floorPaint);
        }
      }
    }

    // Cờ
    _emoji(canvas, '🏁', level.goal, cell, scale: 0.62);
    // Món đồ còn lại
    for (final it in level.items) {
      if (!frame.picked.contains(it)) _emoji(canvas, '🎁', it, cell, scale: 0.52);
    }
    // Robot
    final cx = (frame.at.x + 0.5) * cell;
    final cy = (frame.at.y + 0.5) * cell;
    final r = cell * 0.30;
    canvas.drawCircle(Offset(cx, cy), r, robotPaint);
    // Mũi chỉ hướng
    final dir = frame.facing.delta;
    final tip = Offset(cx + dir.x * r * 1.45, cy + dir.y * r * 1.45);
    final left = Offset(
      cx + dir.x * r * 0.8 - dir.y * r * 0.5,
      cy + dir.y * r * 0.8 + dir.x * r * 0.5,
    );
    final right = Offset(
      cx + dir.x * r * 0.8 + dir.y * r * 0.5,
      cy + dir.y * r * 0.8 - dir.x * r * 0.5,
    );
    final nosePaint = Paint()..color = const Color(0xFFFBBF24);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close(),
      nosePaint,
    );
    if (frame.bump) {
      canvas.drawCircle(Offset(cx, cy), r * 1.6, bumpPaint);
    }
  }

  void _emoji(Canvas canvas, String glyph, Cell c, double cell, {required double scale}) {
    final tp = TextPainter(
      text: TextSpan(text: glyph, style: TextStyle(fontSize: cell * scale)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((c.x + 0.5) * cell - tp.width / 2, (c.y + 0.5) * cell - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _MazePainter old) =>
      old.frame.at != frame.at ||
      old.frame.facing != frame.facing ||
      old.frame.bump != frame.bump ||
      !setEquals(old.frame.picked, frame.picked) ||
      old.level != level;
}
