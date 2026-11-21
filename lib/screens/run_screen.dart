// SPDX-License-Identifier: MIT
/// Màn hình thực thi (kiểu Pydroid): bấm ▶ ở màn soạn thảo → sang đây chạy,
/// bấm Back (hoặc tap vào một lỗi) → quay lại soạn thảo tiếp.
library;

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';

import '../core/l10n.dart';
import '../core/project.dart';
import '../core/run_history.dart';
import '../core/vis_engine.dart';

/// Kết quả màn thực thi trả về màn soạn thảo khi pop.
class RunScreenResult {
  RunScreenResult({this.jumpLine, this.jumpCol, this.openAndRun});

  /// Tap vào một lỗi → quay lại editor và nhảy tới dòng (1-based).
  final int? jumpLine;
  final int? jumpCol;

  /// Tap "chạy lại" một mục lịch sử của tệp khác → editor mở tệp rồi chạy.
  final String? openAndRun;
}

class RunScreen extends StatefulWidget {
  const RunScreen({
    super.key,
    required this.project,
    required this.engine,
    required this.history,
    required this.fileName,
    required this.text,
    required this.useVm,
    required this.strictCaps,
    required this.noExtern,
    this.args = const [],
    this.checkOnly = false,
    this.fontSize = 13.0,
    this.onDiags,
  });

  final VisProject project;
  final ScriptEngine engine;
  final RunHistoryStore history;
  final String fileName;
  final String text;
  final List<String> args;
  final bool useVm;
  final bool strictCaps;
  final bool noExtern;
  final bool checkOnly;
  final double fontSize;

  /// Báo lại chẩn đoán cho editor (chấm đỏ gutter).
  final ValueChanged<List<Diag>>? onDiags;

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  bool _running = false;
  String _output = '';
  List<Diag> _diags = const [];
  String? _errorText;
  int? _exit;
  int? _steps;
  int _durationMs = 0;

  @override
  void initState() {
    super.initState();
    _execute();
  }

  Future<void> _execute() async {
    if (_running) return;
    setState(() => _running = true);
    await Future<void>.delayed(Duration.zero); // cho UI kịp vẽ spinner
    final started = DateTime.now();
    var ok = false;
    var exit = -1;
    var steps = 0;
    var preview = '';
    try {
      if (widget.checkOnly) {
        final diags = await widget.engine.checkScript(
          entry: widget.project.pathFor(widget.fileName),
          text: widget.text,
        );
        if (!mounted) return;
        setState(() {
          _diags = diags;
          _output = '';
          _errorText = null;
          _exit = null;
          _steps = null;
        });
        widget.onDiags?.call(diags);
        ok = diags.isEmpty;
        preview = diags.isEmpty
            ? t(context, S.noDiagnostics)
            : diags.first.msg;
      } else {
        final res = await widget.engine.runScript(
          entry: widget.project.pathFor(widget.fileName),
          text: widget.text,
          dir: widget.project.root.path,
          args: widget.args,
          useVm: widget.useVm,
          strictCaps: widget.strictCaps,
          noExtern: widget.noExtern,
        );
        if (!mounted) return;
        setState(() {
          _output = res.stdout;
          _diags = res.diags;
          _errorText = res.error;
          _exit = res.exit;
          _steps = res.steps;
        });
        widget.onDiags?.call(res.diags);
        ok = res.clean;
        exit = res.exit;
        steps = res.steps;
        final lines = res.stdout.trim();
        preview = lines.isEmpty
            ? (res.diags.isNotEmpty
                ? res.diags.first.msg
                : t(context, S.previewEmpty))
            : lines.split('\n').first;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.toString();
        _output = '';
        _diags = const [];
        _exit = null;
        _steps = null;
      });
      widget.onDiags?.call(const []);
      ok = false;
      preview = e.toString();
    } finally {
      _durationMs = DateTime.now().difference(started).inMilliseconds;
      if (mounted) {
        setState(() => _running = false);
        widget.history.add(RunHistoryItem(
          time: started,
          file: widget.fileName,
          checkOnly: widget.checkOnly,
          ok: ok,
          exit: exit,
          steps: steps,
          preview: preview,
          durationMs: _durationMs,
        ));
      }
    }
  }

  void _copyOutput() {
    final data = _errorText != null ? _errorText! : _output;
    if (data.isEmpty) return;
    Clipboard.setData(ClipboardData(text: data));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t(context, S.copied)), duration: const Duration(seconds: 1)),
    );
  }

  /// Tap một lỗi: quay lại editor, nhảy tới dòng.
  void _jumpTo(Diag d) {
    Navigator.pop(
      context,
      RunScreenResult(jumpLine: d.line, jumpCol: d.col),
    );
  }

  /// Tap chạy lại một mục lịch sử: tệp khác thì nhờ editor mở rồi chạy.
  void _rerunFile(String file) {
    if (file == widget.fileName) {
      _execute();
    } else if (widget.project.exists(file)) {
      Navigator.pop(context, RunScreenResult(openAndRun: file));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.checkOnly
              ? '${widget.fileName} · ${t(context, S.check)}'
              : widget.fileName,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: widget.checkOnly ? t(context, S.check) : t(context, S.rerun),
            icon: const Icon(Icons.refresh),
            onPressed: _running ? null : _execute,
          ),
          IconButton(
            tooltip: t(context, S.copyOutput),
            icon: const Icon(Icons.copy_outlined, size: 20),
            onPressed: _running ? null : _copyOutput,
          ),
          IconButton(
            tooltip: t(context, S.clear),
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            onPressed: _running
                ? null
                : () => setState(() {
                      _output = '';
                      _diags = const [];
                      _errorText = null;
                      _exit = null;
                      _steps = null;
                    }),
          ),
        ],
      ),
      body: _running
          ? _building()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
              children: [
                _statusCard(cs),
                if (widget.args.isNotEmpty && !widget.checkOnly) ...[
                  const SizedBox(height: 8),
                  _argsRow(cs),
                ],
                // Có lỗi engine (FFI/EngineException) cũng phải hiện khung
                // output — trước đây chỉ có chip 'LỖI', người dùng không bao
                // giờ đọc được thông điệp lỗi khi stdout trống và không có diag.
                if (_output.isNotEmpty ||
                    _errorText != null ||
                    _diags.isEmpty) ...[
                  const SizedBox(height: 10),
                  _outputBox(cs),
                ],
                if (_diags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _diagList(cs),
                ],
                const SizedBox(height: 10),
                _historyCard(cs),
              ],
            ),
    );
  }

  Widget _building() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            widget.checkOnly ? t(context, S.checking) : t(context, S.running),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Các khối nội dung
  // ------------------------------------------------------------------

  Widget _statusCard(ColorScheme cs) {
    final failed = _errorText != null ||
        (_diags.isNotEmpty) ||
        (_exit != null && _exit != 0);
    final chips = <Widget>[];
    if (widget.checkOnly) {
      chips.add(_chip(
        _diags.isEmpty ? t(context, S.okShort) : '${_diags.length} ${t(context, S.diagnostics)}',
        _diags.isEmpty ? Colors.green : cs.error,
      ));
    } else if (_exit != null) {
      chips.add(_chip(
        failed ? t(context, S.errorShort) : t(context, S.okShort),
        failed ? cs.error : Colors.green,
      ));
      chips.add(_monoChip('exit $_exit', cs));
    }
    if (_steps != null) {
      chips.add(_monoChip('${t(context, S.steps)} $_steps', cs));
    }
    chips.add(_monoChip('${t(context, S.duration)} ${_durationMs}ms', cs));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Wrap(spacing: 8, runSpacing: 6, children: chips),
    );
  }

  Widget _argsRow(ColorScheme cs) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(Icons.terminal, size: 14, color: cs.outline),
        for (final a in widget.args)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.secondaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              a,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: cs.onSecondaryContainer,
              ),
            ),
          ),
      ],
    );
  }

  Widget _outputBox(ColorScheme cs) {
    final hasError = _errorText != null;
    final text = hasError ? _errorText! : _output;
    final empty = text.trim().isEmpty && _diags.isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF101418)
            : const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError
              ? cs.error.withValues(alpha: 0.4)
              : cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      constraints: const BoxConstraints(minHeight: 120),
      child: empty
          ? Text(
              _diags.isEmpty ? t(context, S.outputEmpty) : '',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                color: cs.outline,
              ),
            )
          : SelectableText(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: widget.fontSize,
                height: 1.5,
                color: hasError ? cs.error : cs.onSurface,
              ),
            ),
    );
  }

  Widget _diagList(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final d in _diags)
            InkWell(
              onTap: () => _jumpTo(d),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      d.code.startsWith('VS05') ? Icons.bolt : Icons.rule,
                      size: 16,
                      color: cs.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${d.code} · ${t(context, S.line)} ${d.line}:${d.col}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: cs.error,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            d.msg,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: cs.outline),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _historyCard(ColorScheme cs) {
    return AnimatedBuilder(
      animation: widget.history,
      builder: (context, _) {
        final items = widget.history.items;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Icon(Icons.history, size: 15, color: cs.outline),
                    const SizedBox(width: 6),
                    Text(
                      t(context, S.history),
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: cs.outline),
                    ),
                    const Spacer(),
                    if (items.isNotEmpty)
                      InkWell(
                        onTap: widget.history.clear,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(
                            t(context, S.clear),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: cs.primary),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Text(
                    t(context, S.historyEmpty),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.outline),
                  ),
                )
              else
                for (final h in items)
                  InkWell(
                    onTap: () => _rerunFile(h.file),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            h.ok
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            size: 16,
                            color: h.ok ? Colors.green : cs.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${h.file}  ·  '
                                  '${h.time.hour.toString().padLeft(2, '0')}:'
                                  '${h.time.minute.toString().padLeft(2, '0')}:'
                                  '${h.time.second.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: cs.onSurface,
                                  ),
                                ),
                                if (h.preview.isNotEmpty)
                                  Text(
                                    h.preview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: cs.outline),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            h.checkOnly
                                ? t(context, S.check)
                                : '${h.durationMs}ms',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: cs.outline),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.play_circle_outline,
                              size: 18, color: cs.primary),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // Chips nhỏ
  // ------------------------------------------------------------------

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
  Widget _monoChip(String text, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11.5,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
