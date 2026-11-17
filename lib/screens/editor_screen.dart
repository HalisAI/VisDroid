// SPDX-License-Identifier: MIT
/// Màn hình soạn thảo: editor + bảng kết quả chạy + nút ▶ chạy tức thì.
library;

import 'dart:async';
import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:material_ui/material_ui.dart';

import '../core/highlighter.dart';
import '../core/l10n.dart';
import '../core/project.dart';
import '../core/vis_engine.dart';
import '../widgets/code_field.dart';

/// Trạng thái bảng kết quả.
class ConsoleData {
  ConsoleData({
    this.output = '',
    this.diags = const [],
    this.running = false,
    this.exit,
    this.steps,
    this.errorText,
    this.checkedOnly = false,
  });

  String output;
  List<Diag> diags;
  bool running;
  int? exit;
  int? steps;
  String? errorText;
  bool checkedOnly;

  ConsoleData copyWith({
    String? output,
    List<Diag>? diags,
    bool? running,
    int? exit,
    int? steps,
    String? errorText,
    bool? checkedOnly,
  }) =>
      ConsoleData(
        output: output ?? this.output,
        diags: diags ?? this.diags,
        running: running ?? this.running,
        exit: exit ?? this.exit,
        steps: steps ?? this.steps,
        errorText: errorText,
        checkedOnly: checkedOnly ?? this.checkedOnly,
      );
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.project,
    required this.engine,
    required this.useVm,
    required this.strictCaps,
    required this.noExtern,
    required this.onFileOpened,
    this.fontSize = 15.0,
    this.autoSave = true,
  });

  final VisProject project;
  final VisEngine engine;
  final bool useVm;
  final bool strictCaps;
  final bool noExtern;
  final double fontSize;
  final bool autoSave;

  /// Thông báo cho shell biết tệp đang mở (đổi tiêu đề, mở lại lần sau).
  final ValueChanged<String?> onFileOpened;

  @override
  State<EditorScreen> createState() => EditorScreenState();
}

/// Một lần chạy trong phiên làm việc (lịch sử).
class _RunHistory {
  _RunHistory({
    required this.time,
    required this.file,
    required this.ok,
    required this.exit,
    required this.steps,
    required this.preview,
    required this.durationMs,
  });
  final DateTime time;
  final String file;
  final bool ok;
  final int exit;
  final int steps;
  final String preview;
  final int durationMs;
}

class EditorScreenState extends State<EditorScreen> {
  CodeController? _controller;
  String? _fileName;
  bool _dirty = false;
  List<String> _args = const [];
  double _consoleHeight = 220;

  ConsoleData _console = ConsoleData();

  Timer? _debounce;
  final GlobalKey<CodeFieldState> _codeFieldKey = GlobalKey<CodeFieldState>();

  // Tìm & thay thế
  bool _showFind = false;
  bool _showReplaceRow = false;
  final _findCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  List<int> _findMatches = <int>[];
  int _findIndex = 0;

  // Lịch sử chạy (phiên làm việc)
  final List<_RunHistory> _history = <_RunHistory>[];
  int _consoleTab = 0; // 0 = kết quả, 1 = lịch sử
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ensureController('');
  }

  void _ensureController(String text) {
    _controller ??= CodeController(text: text, colors: _colors);
    if (_controller!.text != text && _controller!.text.isEmpty) {
      _controller!.text = text;
    }
  }

  HighlightColors get _colors =>
      Theme.of(context).brightness == Brightness.dark
          ? HighlightColors.dark
          : HighlightColors.light;

  bool get hasFile => _fileName != null;

  /// Mở tệp theo tên trong dự án.
  Future<void> openFile(String name) async {
    final text = widget.project.read(name);
    setState(() {
      _fileName = name;
      _dirty = false;
      _console = ConsoleData();
      _controller = CodeController(text: text, colors: _colors);
    });
    widget.onFileOpened(name);
  }

  /// Tạo tệp mới và mở.
  Future<void> createFile(String name) async {
    widget.project.create(name, content: '');
    await openFile(name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t(context, S.fileCreated)}: $name')),
      );
    }
  }

  /// Lưu tệp hiện tại xuống đĩa. `silent` = không snackbar (dùng cho auto-save).
  Future<void> save({bool silent = false}) async {
    final name = _fileName;
    if (name == null) return;
    widget.project.write(name, _controller!.text);
    if (!mounted) return;
    setState(() => _dirty = false);
    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t(context, S.fileSaved)}: $name')),
      );
    }
  }

  Future<void> renameFile(String newName) async {
    final old = _fileName;
    if (old == null || newName == old) return;
    await save();
    widget.project.rename(old, newName);
    setState(() {
      _fileName = newName;
      _dirty = false;
    });
    widget.onFileOpened(newName);
  }

  Future<void> deleteCurrent() async {
    final name = _fileName;
    if (name == null) return;
    widget.project.delete(name);
    setState(() {
      _fileName = null;
      _dirty = false;
      _console = ConsoleData();
      _controller = CodeController(text: '', colors: _colors);
    });
    widget.onFileOpened(null);
  }

  void setConsoleHeight(double h) {
    setState(() => _consoleHeight = h.clamp(80, 600));
  }

  /// Chạy tức thì: tự lưu trước, gọi engine trong isolate.
  Future<void> run() async {
    if (_console.running) return;
    final name = _fileName;
    if (name == null) {
      _showSnack(t(context, S.newFile));
      return;
    }
    await save();
    setState(() => _console = ConsoleData(running: true));
    final text = _controller!.text;
    final entry = widget.project.pathFor(name);
    final dir = widget.project.root.path;
    final started = DateTime.now();
    try {
      final res = await widget.engine.runScript(
        entry: entry,
        text: text,
        dir: dir,
        args: _args,
        useVm: widget.useVm,
        strictCaps: widget.strictCaps,
        noExtern: widget.noExtern,
      );
      if (!mounted) return;
      setState(() {
        _console = ConsoleData(
          output: res.stdout,
          diags: res.diags,
          exit: res.exit,
          steps: res.steps,
          checkedOnly: false,
        );
      });
      _pushHistory(name, started, res.clean, res.exit, res.steps, res.stdout);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _console = ConsoleData(errorText: e.toString(), checkedOnly: false);
      });
      _pushHistory(name, started, false, -1, 0, e.toString());
    }
  }

  void _pushHistory(
      String file, DateTime started, bool ok, int exit, int steps, String out) {
    final firstLine =
        out.trim().isEmpty ? '' : out.trim().split('\n').first;
    setState(() {
      _history.insert(
        0,
        _RunHistory(
          time: started,
          file: file,
          ok: ok,
          exit: exit,
          steps: steps,
          preview: firstLine.isEmpty ? '(trống)' : firstLine,
          durationMs: DateTime.now().difference(started).inMilliseconds,
        ),
      );
      if (_history.length > 30) _history.removeLast();
      _consoleTab = 0;
    });
  }

  /// Kiểm tra tĩnh (không chạy chương trình).
  Future<void> check() async {
    final name = _fileName;
    if (name == null) return;
    setState(() => _console = ConsoleData(running: true));
    try {
      final diags = await widget.engine.checkScript(
        entry: widget.project.pathFor(name),
        text: _controller!.text,
      );
      if (!mounted) return;
      setState(() => _console = ConsoleData(diags: diags, checkedOnly: true));
    } catch (e) {
      if (!mounted) return;
      setState(() => _console = ConsoleData(errorText: e.toString()));
    }
  }

  /// Chấm đỏ gutter: dòng có chẩn đoán (0-based) → mã lỗi.
  Map<int, String> get _errorMarkers {
    final m = <int, String>{};
    for (final d in _console.diags) {
      m[d.line > 0 ? d.line - 1 : 0] = d.code;
    }
    return m;
  }

  // ------------------------------------------------------------------
  // Tìm & thay thế
  // ------------------------------------------------------------------

  void _refreshFind() {
    final q = _findCtrl.text;
    if (q.isEmpty) {
      _findMatches = <int>[];
      _findIndex = 0;
    } else {
      final text = _controller?.text ?? '';
      final matches = <int>[];
      var start = 0;
      while (true) {
        final i = text.indexOf(q, start);
        if (i < 0) break;
        matches.add(i);
        start = i + q.length;
      }
      _findMatches = matches;
      if (_findIndex >= matches.length) _findIndex = 0;
    }
    if (mounted) setState(() {});
  }

  void _gotoMatch(int index) {
    if (_findMatches.isEmpty) return;
    _findIndex = index % _findMatches.length;
    final pos = _findMatches[_findIndex];
    final text = _controller!.text;
    _controller!.value = TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: pos,
        extentOffset: pos + _findCtrl.text.length,
      ),
    );
    _followSelection();
    if (mounted) setState(() {});
  }

  /// Cuộn editor tới vị trí con trỏ đang chọn.
  void _followSelection() {
    final sel = _controller?.selection;
    if (sel == null || !sel.isValid) return;
    final text = _controller!.text;
    var line = 0;
    for (var i = 0; i < sel.baseOffset && i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) line++;
    }
    _codeFieldKey.currentState?.jumpToLine(line + 1);
  }

  void _replaceCurrent() {
    if (_findMatches.isEmpty || _findIndex >= _findMatches.length) return;
    final pos = _findMatches[_findIndex];
    final text = _controller!.text;
    final newText = text.replaceRange(
        pos, pos + _findCtrl.text.length, _replaceCtrl.text);
    _controller!.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
          offset: pos + _replaceCtrl.text.length),
    );
    _refreshFind();
    _followSelection();
  }

  void _replaceAllMatches() {
    final q = _findCtrl.text;
    if (q.isEmpty) return;
    final text = _controller!.text;
    final newText = text.replaceAll(q, _replaceCtrl.text);
    _controller!.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    _refreshFind();
  }

  // ------------------------------------------------------------------
  // Đi tới dòng / thống kê
  // ------------------------------------------------------------------

  Future<void> _gotoLine() async {
    final text = _controller?.text ?? '';
    final total = text.split('\n').length;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(ctx, S.goto)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: t(ctx, S.gotoHint).replaceFirst('1', '1').replaceFirst('tổng số dòng', '1–$total'),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t(ctx, S.cancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t(ctx, S.confirm)),
          ),
        ],
      ),
    );
    final line = int.tryParse(ctrl.text) ?? 0;
    if (ok == true && line >= 1 && line <= total) {
      _codeFieldKey.currentState?.jumpToLine(line);
    }
  }

  Future<void> _showStats() async {
    final text = _controller?.text ?? '';
    final lines = text.split('\n').length;
    final chars = text.characters.length;
    final bytes = utf8.encode(text).length;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(ctx, S.stats)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statRow(ctx, t(ctx, S.statsLines), '$lines'),
            _statRow(ctx, t(ctx, S.statsChars), '$chars'),
            _statRow(ctx, t(ctx, S.statsBytes),
                bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(1)} KB'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t(ctx, S.close)),
          ),
        ],
      ),
    );
  }

  Widget _statRow(BuildContext ctx, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Nhảy tới dòng trong editor (tap vào chẩn đoán).
  void _jumpToLine(int line, int col) {
    final text = _controller!.text;
    var off = 0;
    var l = 1;
    while (off < text.length && l < line) {
      if (text.codeUnitAt(off) == 0x0A) l++;
      off++;
    }
    off += (col - 1).clamp(0, 0); // giữ cột 0 để đơn giản, im lặng nếu lệch
    _controller!.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: off.clamp(0, text.length)),
    );
    _focus.requestFocus();
  }

  Future<void> _editArgs() async {
    final ctrl = TextEditingController(text: _args.join(' '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(ctx, S.run)),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: t(ctx, S.argsHint)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t(ctx, S.cancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t(ctx, S.confirm)),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _args =
          ctrl.text.trim().isEmpty ? [] : ctrl.text.trim().split(RegExp(r'\s+')));
    }
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _controller?.colors = _colors;
    final name = _fileName;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: name == null
          ? _welcome()
          : Column(
              children: [
                _fileHeader(name),
                Expanded(
                  child: Column(
                    children: [
                      if (_showFind) _buildFindBar(name),
                      Expanded(
                        child: CodeField(
                          key: _codeFieldKey,
                          controller: _controller!,
                          focusNode: _focus,
                          colors: _colors,
                          fontSize: widget.fontSize,
                          markers: _errorMarkers,
                          onModified: () => _scheduleDirty(),
                        ),
                      ),
                    ],
                  ),
                ),
                _DragHandle(
                  height: _consoleHeight,
                  onDrag: setConsoleHeight,
                  child: _consolePanel(),
                ),
              ],
            ),
      floatingActionButton: name != null
          ? FloatingActionButton.large(
              heroTag: 'run',
              tooltip: t(context, S.run),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              onPressed: _console.running ? null : run,
              child: _console.running
                  ? SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : Icon(
                      Icons.play_arrow,
                      size: 44,
                      color: Theme.of(context).colorScheme.primary,
                    ),
            )
          : null,
    );
  }

  void _scheduleDirty() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      if (!_dirty) setState(() => _dirty = true);
      // Tự động lưu sau 2.5s không gõ (nếu bật trong Cài đặt).
      if (widget.autoSave && _dirty && _fileName != null) {
        save(silent: true);
      }
    });
    _refreshFind();
  }

  Widget _welcome() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.code_rounded, size: 72, color: cs.primary),
            const SizedBox(height: 16),
            Text(
              t(context, S.welcomeTitle),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              t(context, S.welcomeBody),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileHeader(String name) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            size: 18,
            color: _dirty ? cs.tertiary : cs.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _dirty ? '$name •' : name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            tooltip: t(context, S.save),
            icon: const Icon(Icons.save_outlined, size: 22),
            onPressed: _dirty ? save : null,
          ),
          IconButton(
            tooltip: t(context, S.check),
            icon: const Icon(Icons.fact_check_outlined, size: 22),
            onPressed: check,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 22),
            onSelected: (v) async {
              if (v == 'args') await _editArgs();
              if (v == 'clear') {
                setState(() {
                  _console = ConsoleData();
                  _consoleTab = 0;
                });
              }
              if (v == 'find') {
                setState(() {
                  _showFind = true;
                  _showReplaceRow = false;
                });
              }
              if (v == 'goto') await _gotoLine();
              if (v == 'stats') await _showStats();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'find',
                child: Text('${t(ctx, S.find)} & ${t(ctx, S.replace)}'),
              ),
              PopupMenuItem(value: 'goto', child: Text(t(ctx, S.goto))),
              PopupMenuItem(value: 'stats', child: Text(t(ctx, S.stats))),
              PopupMenuItem(
                value: 'args',
                child: Text('${t(ctx, S.run)} — args'),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Text(t(ctx, S.clearConsole)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _consolePanel() {
    final cs = Theme.of(context).colorScheme;
    final c = _console;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 1)),
      ),
      child: Column(
        children: [
          // Thanh tiêu đề bảng chạy + tab Kết quả / Lịch sử.
          SizedBox(
            height: 34,
            child: Row(
              children: [
                const SizedBox(width: 8),
                _consoleTabBtn(0, Icons.terminal_outlined,
                    c.checkedOnly ? t(context, S.diagnostics) : t(context, S.output)),
                const SizedBox(width: 6),
                _consoleTabBtn(1, Icons.history, t(context, S.history)),
                if (_consoleTab == 0 && c.exit != null) ...[
                  const SizedBox(width: 8),
                  _chip(
                    c.exit == 0 ? t(context, S.okShort) : t(context, S.errorShort),
                    c.exit == 0 ? Colors.green : cs.error,
                  ),
                ],
                const Spacer(),
                if (c.steps != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '${t(context, S.steps)}: ${c.steps}',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: cs.outline),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: c.running && _consoleTab == 0
                ? const Center(child: CircularProgressIndicator())
                : _consoleTab == 0
                    ? _consoleBody(c)
                    : _historyView(),
          ),
        ],
      ),
    );
  }

  Widget _consoleTabBtn(int tab, IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    final active = _consoleTab == tab;
    return InkWell(
      onTap: () => setState(() => _consoleTab = tab),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? cs.primary.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? cs.primary : cs.outline),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: active ? cs.primary : cs.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bảng lịch sử chạy trong phiên làm việc — tap để chạy lại tệp.
  Widget _historyView() {
    if (_history.isEmpty) {
      return Center(
        child: Text(
          t(context, S.historyEmpty),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      itemCount: _history.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final h = _history[i];
        final t2 = h.time;
        final hh =
            '${t2.hour.toString().padLeft(2, '0')}:${t2.minute.toString().padLeft(2, '0')}:${t2.second.toString().padLeft(2, '0')}';
        return ListTile(
          dense: true,
          leading: Icon(
            h.ok == true ? Icons.check_circle_outline : Icons.error_outline,
            size: 18,
            color: h.ok == true ? Colors.green : cs.error,
          ),
          title: Text(
            '${h.file} · $hh · exit ${h.exit} · ${h.durationMs}ms',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              color: cs.onSurface,
            ),
          ),
          subtitle: Text(
            h.preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: const Icon(Icons.play_circle_outline, size: 20),
          onTap: () async {
            if (!widget.project.exists(h.file)) return;
            if (_fileName != h.file) await openFile(h.file);
            await run();
          },
        );
      },
    );
  }

  /// Thanh tìm & thay thế phía trên editor.
  Widget _buildFindBar(String fileName) {
    final cs = Theme.of(context).colorScheme;
    final count = _findCtrl.text.isEmpty
        ? ''
        : ' ${_findMatches.length} ${t(context, S.matches)}'
            ' · ${_findMatches.isEmpty ? 0 : _findIndex + 1}/${_findMatches.length}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _findCtrl,
                  autofocus: true,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixText: count.trim(),
                    suffixStyle: TextStyle(
                        fontSize: 11, color: cs.outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  onChanged: (_) => _refreshFind(),
                ),
              ),
              IconButton(
                tooltip: t(context, S.prev),
                icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                onPressed: _findMatches.isEmpty
                    ? null
                    : () => _gotoMatch(_findIndex - 1),
              ),
              IconButton(
                tooltip: t(context, S.next),
                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                onPressed: _findMatches.isEmpty
                    ? null
                    : () => _gotoMatch(_findIndex + 1),
              ),
              IconButton(
                tooltip: t(context, S.replace),
                icon: Icon(
                  _showReplaceRow ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _showReplaceRow = !_showReplaceRow),
              ),
              IconButton(
                tooltip: t(context, S.close),
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() => _showFind = false);
                  _focus.requestFocus();
                },
              ),
            ],
          ),
          if (_showReplaceRow)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replaceCtrl,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: t(context, S.replaceWith),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _findMatches.isEmpty ? null : _replaceCurrent,
                  child: Text(t(context, S.replace)),
                ),
                TextButton(
                  onPressed: _findMatches.isEmpty ? null : _replaceAllMatches,
                  child: Text(t(context, S.replaceAll)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _consoleBody(ConsoleData c) {
    final hasDiags = c.diags.isNotEmpty || c.errorText != null;
    final empty = c.output.isEmpty && !hasDiags;
    if (empty) {
      return Center(
        child: Text(
          c.checkedOnly ? t(context, S.noDiagnostics) : '—',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.45,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final items = <Widget>[];
    if (c.errorText != null) {
      items.add(_consoleLine(c.errorText!,
          color: Theme.of(context).colorScheme.error));
    }
    if (c.output.isNotEmpty) {
      items.add(
        Padding(
          padding: const EdgeInsets.all(10),
          child: SelectableText(c.output, style: mono),
        ),
      );
    }
    for (final d in c.diags) {
      items.add(_diagTile(d));
    }
    return ListView(children: items);
  }

  Widget _consoleLine(String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: color ?? Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _diagTile(Diag d) {
    final cs = Theme.of(context).colorScheme;
    final isRuntime = d.code.startsWith('VS05');
    return InkWell(
      onTap: () => _jumpToLine(d.line, d.col),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isRuntime ? Icons.bolt : Icons.rule,
              size: 16,
              color: cs.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${d.code} · ${d.line}:${d.col}'
                    '${d.file.isEmpty ? '' : ' · ${d.file}'}',
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
          ],
        ),
      ),
    );
  }
}

/// Tay cầm kéo đổi chiều cao bảng kết quả.
class _DragHandle extends StatelessWidget {
  const _DragHandle({
    required this.height,
    required this.onDrag,
    required this.child,
  });

  final double height;
  final ValueChanged<double> onDrag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => onDrag(height - d.delta.dy),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 14,
            width: double.infinity,
            child: Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          SizedBox(height: height, child: child),
        ],
      ),
    );
  }
}
