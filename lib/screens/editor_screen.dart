// SPDX-License-Identifier: MIT
/// Màn hình soạn thảo (kiểu Pydroid): editor full màn hình, nút ▶ chuyển sang
/// màn thực thi; tap một lỗi trên màn thực thi quay lại đây nhảy tới dòng.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:material_ui/material_ui.dart';

import '../core/highlighter.dart';
import '../core/l10n.dart';
import '../core/project.dart';
import '../core/run_history.dart';
import '../core/vis_engine.dart';
import '../widgets/code_field.dart';
import '../widgets/name_dialog.dart';
import 'run_screen.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.project,
    required this.engine,
    required this.history,
    required this.useVm,
    required this.strictCaps,
    required this.noExtern,
    required this.onFileOpened,
    this.fontSize = 15.0,
    this.autoSave = true,
    this.onWantFiles,
  });

  final VisProject project;
  final ScriptEngine engine;
  final RunHistoryStore history;
  final bool useVm;
  final bool strictCaps;
  final bool noExtern;
  final double fontSize;
  final bool autoSave;

  /// Thông báo cho shell biết tệp đang mở (đổi tiêu đề, mở lại lần sau).
  final ValueChanged<String?> onFileOpened;

  /// Người dùng muốn xem danh sách tệp (nút ví dụ mẫu ở màn hình chào mừng).
  final VoidCallback? onWantFiles;

  @override
  State<EditorScreen> createState() => EditorScreenState();
}

class EditorScreenState extends State<EditorScreen> {
  CodeController? _controller;
  String? _fileName;
  bool _dirty = false;
  List<String> _args = const [];

  /// Đang gán text bằng code (mở tệp) — không tính là người dùng sửa.
  bool _silentAssign = false;

  /// Chấm đỏ gutter: dòng 0-based → mã lỗi, từ lần chạy/kiểm tra gần nhất.
  Map<int, String> _markers = const {};

  Timer? _debounce;
  final GlobalKey<CodeFieldState> _codeFieldKey = GlobalKey<CodeFieldState>();
  final FocusNode _focus = FocusNode();
  bool _pushing = false;

  // Tìm & thay thế
  bool _showFind = false;
  bool _showReplaceRow = false;
  final _findCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  List<int> _findMatches = <int>[];
  int _findIndex = 0;

  @override
  void initState() {
    super.initState();
    _ensureController('');
  }

  void _ensureController(String text) {
    // Không dùng Theme.of ở đây (initState chưa xong) — build() sẽ gán màu đúng.
    _controller ??= CodeController(text: text, colors: HighlightColors.light);
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
      _markers = const {};
      // Tái dùng controller thay vì tạo instance mới: thay controller làm
      // CodeField mất listener _onChanged (mất dirty/auto-save/chấm đỏ)
      // và controller cũ không bao giờ được dispose (leak).
      _silentAssign = true;
      // Gán value với selection rỗng trước (listener của CodeField bỏ qua
      // auto-indent khi selection không hợp lệ), rồi mới đặt con trỏ đầu tệp.
      _controller!.value = TextEditingValue(text: text);
      _controller!.selection = TextSelection.collapsed(offset: 0);
      _silentAssign = false;
    });
    _refreshFind();
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
    if (old == null) return;
    final normalized = VisProject.normalizeName(newName);
    // Chuẩn hoá xong trùng tên cũ (chỉ thêm khoảng cách/thiếu đuôi) — không làm gì,
    // tránh báo nhầm 'Tên này đã có' (như files_screen).
    if (normalized == old) return;
    if (!VisProject.validName(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, S.invalidName))),
      );
      return;
    }
    if (widget.project.exists(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, S.nameExists))),
      );
      return;
    }
    await save();
    widget.project.rename(old, normalized);
    setState(() {
      _fileName = normalized;
      _dirty = false;
    });
    widget.onFileOpened(normalized);
  }

  Future<void> deleteCurrent() async {
    final name = _fileName;
    if (name == null) return;
    widget.project.delete(name);
    setState(() {
      _fileName = null;
      _dirty = false;
      _markers = const {};
      // Tái dùng controller như openFile — giữ listener của CodeField.
      _silentAssign = true;
      _controller!.value = TextEditingValue(text: '');
      _controller!.selection = TextSelection.collapsed(offset: 0);
      _silentAssign = false;
    });
    widget.onFileOpened(null);
  }

  // ------------------------------------------------------------------
  // Chạy / kiểm tra → màn thực thi riêng (kiểu Pydroid)
  // ------------------------------------------------------------------

  Future<void> _run({bool checkOnly = false}) async {
    final name = _fileName;
    if (name == null) {
      _showSnack(t(context, S.noFileYet));
      return;
    }
    if (_pushing) return;
    _pushing = true;
    if (mounted) setState(() {}); // khoá nút ▶/Kiểm tra ngay trong lúc chạy
    RunScreenResult? result;
    try {
      await save(silent: true);
      if (!mounted) return;
      final text = _controller!.text;
      final args = _args;
      result = await Navigator.push<RunScreenResult>(
        context,
        MaterialPageRoute<RunScreenResult>(
          builder: (_) => RunScreen(
            project: widget.project,
            engine: widget.engine,
            history: widget.history,
            fileName: name,
            text: text,
            args: args,
            useVm: widget.useVm,
            strictCaps: widget.strictCaps,
            noExtern: widget.noExtern,
            checkOnly: checkOnly,
            fontSize: widget.fontSize,
            onDiags: _setMarkers,
          ),
        ),
      );
    } finally {
      _pushing = false;
      if (mounted) setState(() {});
    }
    if (!mounted || result == null) return;
    if (result.jumpLine != null) {
      _jumpToLine(result.jumpLine!, result.jumpCol ?? 1);
    } else if (result.openAndRun != null) {
      await openFile(result.openAndRun!);
      if (mounted) await _run();
    }
  }

  /// Nhận chẩn đoán từ màn thực thi → chấm đỏ gutter.
  void _setMarkers(List<Diag> diags) {
    if (!mounted) return;
    final m = <int, String>{};
    for (final d in diags) {
      m[d.line > 0 ? d.line - 1 : 0] = d.code;
    }
    setState(() => _markers = m);
  }

  /// Nhảy tới dòng (1-based) và cột, đặt con trỏ + cuộn theo.
  void _jumpToLine(int line, int col) {
    final text = _controller!.text;
    var off = 0;
    var l = 1;
    var lineStart = 0;
    while (off < text.length && l < line) {
      if (text.codeUnitAt(off) == 0x0A) {
        l++;
        lineStart = off + 1;
      }
      off++;
    }
    final lineEnd = text.indexOf('\n', lineStart);
    final lineLen = (lineEnd < 0 ? text.length : lineEnd) - lineStart;
    final target = lineStart + (col - 1).clamp(0, lineLen < 0 ? 0 : lineLen);
    // Cuộn trước rồi mới đặt con trỏ: jumpToLine ghi đè selection về đầu
    // dòng, đặt con trỏ trước sẽ mất luôn cột `col` của lỗi.
    _codeFieldKey.currentState?.jumpToLine(line);
    _controller!.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: target.clamp(0, text.length)),
    );
    _focus.requestFocus();
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
    final ctrl = _controller;
    final sel = ctrl?.selection;
    if (ctrl == null || sel == null || !sel.isValid) return;
    final text = ctrl.text;
    var line = 0;
    for (var i = 0; i < sel.baseOffset && i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) line++;
    }
    _codeFieldKey.currentState?.jumpToLine(line + 1);
    // jumpToLine đặt con trỏ về đầu dòng — khôi phục selection của kết quả
    // tìm/thay thế, nếu không bấm Tiếp/Trước chỉ đưa con trỏ về đầu dòng.
    if (ctrl.selection != sel) {
      ctrl.value = TextEditingValue(text: text, selection: sel);
    }
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
  // Đi tới dòng / thống kê / tham số
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
            hintText: '1–$total',
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
    ctrl.dispose();
    if (ok == true && line >= 1 && line <= total) {
      _jumpToLine(line, 1);
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

  Future<void> _editArgs() async {
    final ctrl = TextEditingController(text: _args.join(' '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(ctx, S.args)),
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
    ctrl.dispose();
  }

  /// Tạo tệp mới ngay từ màn soạn thảo (màn hình chào mừng).
  Future<void> _newFile() async {
    final raw = await askFileName(
      context,
      title: t(context, S.newFile),
      hint: t(context, S.fileNameHint),
    );
    if (raw == null || !mounted) return;
    final name = VisProject.normalizeName(raw);
    if (!VisProject.validName(name)) {
      _showSnack(t(context, S.invalidName));
      return;
    }
    if (widget.project.exists(name)) {
      _showSnack(t(context, S.nameExists));
      return;
    }
    await createFile(name);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _scheduleDirty() {
    _debounce?.cancel();
    // Gán text bằng code (mở tệp/xoá tệp) cũng báo listener — bỏ qua,
    // không đánh dấu dirty cũng không hẹn giờ tự lưu. Huỷ trước để hẹn giờ
    // của phím gõ dở không bắn sau khi tệp khác đã mở.
    if (_silentAssign) return;
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      if (!_dirty) setState(() => _dirty = true);
      // Tự động lưu sau 2.5s không gõ (nếu bật trong Cài đặt).
      if (widget.autoSave && _dirty && _fileName != null) {
        save(silent: true);
      }
    });
    // Nội dung đổi → chấm đỏ cũ hết hiệu lực.
    if (_markers.isNotEmpty) setState(() => _markers = const {});
    _refreshFind();
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _controller?.colors = _colors;
    final name = _fileName;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: name == null
            ? Text(t(context, S.tabEditor))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 16),
                    ),
                  ),
                  if (_dirty) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: cs.tertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
        actions: name == null
            ? null
            : [
                IconButton(
                  tooltip: t(context, S.find),
                  icon: Icon(
                    _showFind ? Icons.search_off : Icons.search,
                    size: 22,
                  ),
                  onPressed: () {
                    setState(() {
                      _showFind = !_showFind;
                      _showReplaceRow = false;
                    });
                  },
                ),
                IconButton(
                  tooltip: t(context, S.check),
                  icon: const Icon(Icons.fact_check_outlined, size: 22),
                  onPressed:
                      _pushing ? null : () => _run(checkOnly: true),
                ),
                IconButton.filledTonal(
                  tooltip: t(context, S.run),
                  onPressed: _pushing ? null : () => _run(),
                  icon: const Icon(Icons.play_arrow, size: 26),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 22),
                  onSelected: (v) async {
                    if (v == 'save' && _dirty) await save();
                    if (v == 'goto') await _gotoLine();
                    if (v == 'stats') await _showStats();
                    if (v == 'args') await _editArgs();
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'save',
                      enabled: _dirty,
                      child: Text(t(ctx, S.save)),
                    ),
                    PopupMenuItem(value: 'goto', child: Text(t(ctx, S.goto))),
                    PopupMenuItem(value: 'stats', child: Text(t(ctx, S.stats))),
                    PopupMenuItem(
                      value: 'args',
                      child: Text('${t(ctx, S.args)} (${_args.length})'),
                    ),
                  ],
                ),
              ],
      ),
      body: name == null
          ? _welcome()
          : Column(
              children: [
                if (_showFind) _buildFindBar(),
                Expanded(
                  child: CodeField(
                    key: _codeFieldKey,
                    controller: _controller!,
                    focusNode: _focus,
                    colors: _colors,
                    fontSize: widget.fontSize,
                    markers: _markers,
                    onModified: () => _scheduleDirty(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _welcome() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/visdroid-icon.png',
              width: 96,
              height: 96,
            ),
            const SizedBox(height: 20),
            Text(
              t(context, S.welcomeTitle),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              t(context, S.noFileHint),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _newFile,
              icon: const Icon(Icons.note_add_outlined),
              label: Text(t(context, S.newFile)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: widget.onWantFiles,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(t(context, S.openExample)),
            ),
          ],
        ),
      ),
    );
  }

  /// Thanh tìm & thay thế phía trên editor.
  Widget _buildFindBar() {
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
}
