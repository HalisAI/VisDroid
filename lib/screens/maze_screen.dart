// SPDX-License-Identifier: MIT
/// Màn chơi Mê cung ViScript — HUD kiểu game: thanh trên tùy chỉnh (quay về /
/// tên màn / gợi ý / reset), bàn chơi sprite + tween mượt, editor code, nút
/// CHẠY to màu amber, chọn tốc độ 1×/2×/4×, overlay chiến thắng 3 sao +
/// confetti, rung + banner khi thất bại. Không dùng AppBar Material.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Chỉ lấy CodeController từ material_ui — package này mirror toàn bộ
// material API nên import nguyên thư sẽ xung đột tên (Theme, Icons, …).
import 'package:material_ui/material_ui.dart' show CodeController;

import '../core/highlighter.dart' show HighlightColors;
import '../core/l10n.dart';
import '../core/settings.dart';
import '../core/vis_engine.dart';
import '../game/board_painter.dart';
import '../game/confetti.dart';
import '../game/game_theme.dart';
import '../game/levels.dart';
import '../game/maze.dart';
import '../game/progress.dart';
import '../game/sprites.dart';
import '../widgets/code_field.dart';

class MazeScreen extends StatefulWidget {
  const MazeScreen({
    super.key,
    required this.engine,
    required this.appState,
    required this.progress,
    required this.levelIndex,
  });

  final ScriptEngine engine;
  final AppState appState;
  final GameProgress progress;
  final int levelIndex;

  @override
  State<MazeScreen> createState() => _MazeScreenState();
}

class _MazeScreenState extends State<MazeScreen> with TickerProviderStateMixin {
  int _levelIndex = 0;
  CodeController? _controller;
  final _focusNode = FocusNode();

  /// Giữ các controller đã thay thế tới khi rời màn — tránh dispose trùng
  /// với TextField đang tham chiếu trong frame chuyển tiếp.
  final List<CodeController> _oldControllers = [];

  late final AnimationController _step = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final AnimationController _winAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  SimOutcome? _outcome;
  int _frameIdx = 0;
  SimFrame? _prevFrame;
  bool _running = false;
  bool _showWin = false;
  int _starsEarned = 0;
  int _stepsTaken = 0;
  int _speed = 1;
  String? _banner;

  MazeLevel get _level => kGameLevels[_levelIndex];

  @override
  void initState() {
    super.initState();
    _levelIndex = widget.levelIndex.clamp(0, kGameLevels.length - 1);
    _reloadController();
    _step.addStatusListener(_onStepStatus);
  }

  void _reloadController() {
    final old = _controller;
    if (old != null) _oldControllers.add(old);
    _controller = CodeController(
      text: widget.progress.codeOf(_level),
      colors: HighlightColors.dark,
    );
    _resetBoard();
  }

  void _resetBoard() {
    _step.stop();
    _shake.stop();
    _winAnim.stop();
    _outcome = null;
    _prevFrame = null;
    _frameIdx = 0;
    _running = false;
    _showWin = false;
    _banner = null;
  }

  @override
  void dispose() {
    _step.removeStatusListener(_onStepStatus);
    _step.dispose();
    _shake.dispose();
    _winAnim.dispose();
    _focusNode.dispose();
    for (final c in _oldControllers) {
      c.dispose();
    }
    _controller?.dispose();
    super.dispose();
  }

  void _saveCode() {
    final c = _controller;
    if (c != null) widget.progress.setCode(_level, c.text);
  }

  void _back() {
    _saveCode();
    Navigator.of(context).maybePop();
  }

  // ------------------------------------------------------------------
  // Chạy script → mô phỏng → hoạt ảnh từng bước
  // ------------------------------------------------------------------

  Future<void> _run() async {
    if (_running) {
      // Đang chạy → nút thành DỪNG (đóng băng tại frame hiện tại).
      _step.stop();
      setState(() => _running = false);
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    final code = controller.text;
    _saveCode();
    setState(() {
      _banner = null;
      _outcome = null;
      _prevFrame = null;
      _frameIdx = 0;
      _showWin = false;
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
        _fail('${t(context, S.gameErrCompile)}: '
            '${t(context, S.gameAtLine).replaceFirst('{n}', '${d.line}')} '
            '${d.code} — ${d.msg}');
        return;
      }
      if (res.error != null && res.exit != 0) {
        _fail('${t(context, S.gameErrCompile)}: ${res.error}');
        return;
      }
    } catch (e) {
      _fail('$e');
      return;
    } finally {
      if (mounted && _banner != null) setState(() => _running = false);
    }

    final pr = parseCommands(stdoutText);
    if (!pr.ok) {
      final lineInfo = (pr.errorLine ?? 0) > 0
          ? '${t(context, S.gameAtLine).replaceFirst('{n}', '${pr.errorLine}')} — '
          : '';
      _fail('${t(context, S.gameErrParse)}: $lineInfo${pr.error}');
      return;
    }
    final oc = simulate(_level, pr.cmds);
    setState(() {
      _outcome = oc;
      _prevFrame = oc.frames.first;
      _frameIdx = 0;
    });
    _playNext();
  }

  void _playNext() {
    final oc = _outcome;
    if (oc == null || !_running) return;
    if (_frameIdx >= oc.frames.length - 1) {
      _finish();
      return;
    }
    setState(() {
      _prevFrame = oc.frames[_frameIdx];
      _frameIdx++;
    });
    _step.duration = Duration(milliseconds: 360 ~/ _speed);
    _step.forward(from: 0);
  }

  void _onStepStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_running) return;
    _playNext();
  }

  void _finish() {
    final oc = _outcome!;
    setState(() => _running = false);
    if (oc.win) {
      _stepsTaken = oc.frames.length - 1;
      _starsEarned = widget.progress.starsFor(_stepsTaken, _level.par);
      widget.progress.recordWin(_level, _stepsTaken);
      _saveCode();
      HapticFeedback.mediumImpact();
      _winAnim.forward(from: 0);
      setState(() => _showWin = true);
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    setState(() {
      _banner = msg;
      _outcome = null;
      _prevFrame = null;
      _frameIdx = 0;
      _running = false;
    });
  }

  Future<void> _showHint() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: kGamePanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lightbulb, color: kGameAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${t(ctx, S.gameHint)} — ${_level.title}',
                      style: const TextStyle(
                        color: kGameText,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SelectableText(_level.hint, style: gameDimStyle(14)),
              const SizedBox(height: 8),
              Text(
                t(ctx, S.gamePar).replaceFirst('{n}', '${_level.par}'),
                style: gameStateStyle(kGameAccent),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmResetCode() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _gameDialog(
        ctx,
        title: t(ctx, S.gameReset),
        body: t(ctx, S.gameResetCodeConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t(ctx, S.cancel)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              t(ctx, S.confirm),
              style: const TextStyle(color: kGameDanger),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final old = _controller;
      if (old != null) _oldControllers.add(old);
      setState(() {
        _controller = CodeController(
          text: _level.starterCode,
          colors: HighlightColors.dark,
        );
        _resetBoard();
      });
    }
  }

  void _nextLevel() {
    if (_levelIndex + 1 >= kGameLevels.length) {
      _back();
      return;
    }
    _saveCode();
    setState(() {
      _levelIndex++;
      _reloadController();
    });
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final oc = _outcome;
    final curFrame = oc == null
        ? SimFrame(at: _level.start, facing: _level.startFacing, picked: {})
        : oc.frames[_frameIdx];
    final prevFrame = _prevFrame ?? curFrame;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _saveCode();
      },
      child: Scaffold(
        backgroundColor: kGameBgTop,
        body: Container(
          decoration: const BoxDecoration(gradient: kGameBgGradient),
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    _hud(context),
                    Expanded(
                      child: _board(context, prevFrame, curFrame),
                    ),
                    _statusStrip(context, oc),
                    _editor(context),
                    _controls(context),
                  ],
                ),
                if (_showWin) _winOverlay(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hud(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: kGameText, size: 26),
            onPressed: _back,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '${t(context, S.gameWorld)} ${_level.world} · '
                  '${t(context, S.gameLevel).toUpperCase()} ${_level.id}',
                  style: const TextStyle(
                    color: kGameTextDim,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
                Text(
                  _level.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kGameText,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.lightbulb_outline,
                color: kGameAccent, size: 22),
            onPressed: _showHint,
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt, color: kGameTextDim, size: 22),
            onPressed: _confirmResetCode,
          ),
        ],
      ),
    );
  }

  Widget _board(BuildContext context, SimFrame prevFrame, SimFrame curFrame) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Center(
        child: AspectRatio(
          aspectRatio: _level.cols / _level.rows,
          child: AnimatedBuilder(
            animation: Listenable.merge([_step, _shake]),
            builder: (context, _) {
              final shake = _shake.value;
              final dx = shake > 0
                  ? math.sin(shake * math.pi * 4) * 7 * (1 - shake)
                  : 0.0;
              return Transform.translate(
                offset: Offset(dx, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    decoration: BoxDecoration(
                      color: kGamePanel,
                      border: Border.all(color: kGamePanelBorder, width: 2),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: CustomPaint(
                      painter: BoardPainter(
                        level: _level,
                        from: prevFrame,
                        to: curFrame,
                        t: _step.value,
                        sprites: SpriteSet.instance,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _statusStrip(BuildContext context, SimOutcome? oc) {
    Widget text;
    if (_banner != null) {
      text = Text(_banner!, style: gameStateStyle(kGameDanger));
    } else if (_running) {
      text = Text(
        '${t(context, S.gameStep)
            .replaceFirst('{i}', '$_frameIdx')
            .replaceFirst('{n}', '${oc!.frames.length - 1}')}…',
        style: gameStateStyle(kGameAccent),
      );
    } else if (oc != null && !oc.win && oc.failMsg != null) {
      text = Text(
        '${t(context, S.gameFail)}: ${oc.failMsg}',
        style: gameStateStyle(kGameDanger),
      );
    } else {
      text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${t(context, S.gameTask)}: ${_level.task}',
            style: gameDimStyle(12),
          ),
          const SizedBox(height: 2),
          Text(
            t(context, S.gamePar).replaceFirst('{n}', '${_level.par}'),
            style: gameStateStyle(kGameAccent),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: SizedBox(width: double.infinity, child: text),
    );
  }

  Widget _editor(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: SizedBox(
        height: 168,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: kGamePanel.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kGamePanelBorder),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CodeField(
              controller: controller,
              focusNode: _focusNode,
              colors: HighlightColors.dark,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: kRunButtonGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: kGameAccent.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: FilledButton.icon(
              style: runButtonStyle(),
              onPressed: _run,
              icon: Icon(
                _running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: const Color(0xFF3D2B00),
                size: 26,
              ),
              label: Text(
                _running
                    ? t(context, S.gameStop).toUpperCase()
                    : t(context, S.run).toUpperCase(),
              ),
            ),
          ),
          const Spacer(),
          _speedChip(context, 1),
          const SizedBox(width: 6),
          _speedChip(context, 2),
          const SizedBox(width: 6),
          _speedChip(context, 4),
        ],
      ),
    );
  }

  Widget _speedChip(BuildContext context, int speed) {
    final selected = _speed == speed;
    return GestureDetector(
      onTap: () => setState(() => _speed = speed),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? kGameAccent.withValues(alpha: 0.18) : kGamePanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? kGameAccent : kGamePanelBorder,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Text(
          '$speed×',
          style: TextStyle(
            color: selected ? kGameAccent : kGameTextDim,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Overlay chiến thắng + dialog kiểu game
  // ------------------------------------------------------------------

  Widget _winOverlay(BuildContext context) {
    final hasNext = _levelIndex + 1 < kGameLevels.length;
    return Positioned.fill(
      child: Stack(
        children: [
          ModalBarrier(
            dismissible: false,
            color: Colors.black.withValues(alpha: 0.72),
          ),
          const ConfettiBurst(),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: kGamePanel,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: kGameAccent, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: kGameAccent.withValues(alpha: 0.22),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t(context, S.gameWinTitle),
                      textAlign: TextAlign.center,
                      style: gameTitleStyle(26),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var s = 0; s < 3; s++) _popStar(s),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      t(context, S.gameWinDetail)
                          .replaceFirst('{n}', '$_stepsTaken')
                          .replaceFirst('{m}', '${_level.par}'),
                      textAlign: TextAlign.center,
                      style: gameDimStyle(13.5),
                    ),
                    if (_levelIndex == kGameLevels.length - 1) ...[
                      const SizedBox(height: 6),
                      Text(
                        t(context, S.gameAllDone),
                        textAlign: TextAlign.center,
                        style: gameStateStyle(kGameSuccess),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kGameText,
                            side: const BorderSide(color: kGamePanelBorder),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 12),
                          ),
                          onPressed: () {
                            setState(() => _resetBoard());
                          },
                          child: Text(t(context, S.gameReplay)),
                        ),
                        const SizedBox(width: 12),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: kRunButtonGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: FilledButton(
                            style: runButtonStyle(),
                            onPressed: () {
                              setState(() => _showWin = false);
                              if (hasNext) {
                                _nextLevel();
                              } else {
                                _back();
                              }
                            },
                            child: Text(
                              hasNext
                                  ? t(context, S.gameNext)
                                  : t(context, S.gameSelectLevels),
                              style: const TextStyle(color: Color(0xFF3D2B00)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _popStar(int index) {
    final earned = _starsEarned >= index + 1;
    // Sao đạt được pop lần lượt; sao chưa đạt hiện mờ luôn.
    final begin = (index * 0.22).clamp(0.0, 0.9);
    final end = (begin + 0.45).clamp(begin, 1.0);
    return AnimatedBuilder(
      animation: _winAnim,
      builder: (context, _) {
        final raw = ((_winAnim.value - begin) / (end - begin)).clamp(0.0, 1.0);
        final scale = earned ? _popCurve(raw) : 1.0;
        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: earned ? 1.0 : 0.35,
            child: Image.asset(
              earned ? 'assets/game/star.png' : 'assets/game/star_off.png',
              width: 62,
              height: 62,
            ),
          ),
        );
      },
    );
  }

  /// Spring ngắn: leo lên 1.25 rồi hạ về 1.
  double _popCurve(double x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    return x < 0.7 ? (x / 0.7) * 1.25 : 1.25 - ((x - 0.7) / 0.3) * 0.25;
  }
}

AlertDialog _gameDialog(
  BuildContext ctx, {
  required String title,
  required String body,
  required List<Widget> actions,
}) {
  return AlertDialog(
    backgroundColor: kGamePanel,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: kGamePanelBorder),
    ),
    title: Text(title, style: const TextStyle(color: kGameText)),
    content: Text(body, style: gameDimStyle(13.5)),
    actions: actions,
  );
}
