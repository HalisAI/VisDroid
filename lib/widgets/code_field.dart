// SPDX-License-Identifier: MIT
/// Editor mã nguồn ViScript: tô màu cú pháp, số dòng, thụt lề tự động
/// và thanh phím nhanh cho bàn phím mềm.
library;

import 'package:material_ui/material_ui.dart';


import '../core/highlighter.dart';

/// Controller tô màu cú pháp — override `buildTextSpan`.
class CodeController extends TextEditingController {
  CodeController({super.text, required this.colors});

  HighlightColors colors;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final span = buildHighlightTextSpan(text, colors);
    return TextSpan(style: style, children: span.children);
  }
}

/// Vẽ cột số dòng đồng bộ cuộn dọc với TextField.
class GutterPainter extends CustomPainter {
  GutterPainter({
    required this.lineCount,
    required this.lineHeight,
    required this.topPad,
    required this.scrollOffset,
    required this.cursorLine,
    required this.color,
    required this.activeColor,
    required this.fontSize,
  });

  final int lineCount;
  final double lineHeight;
  final double topPad;
  final double scrollOffset;
  final int cursorLine;
  final Color color;
  final Color activeColor;
  final double fontSize;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(textDirection: TextDirection.ltr);
    final first = (scrollOffset / lineHeight).floor().clamp(0, lineCount);
    final visible = (size.height / lineHeight).ceil() + 1;
    for (var k = 0; k < visible; k++) {
      final line = first + k;
      if (line >= lineCount) break;
      final num = '${line + 1}';
      final isCursor = line == cursorLine;
      painter.text = TextSpan(
        text: num,
        style: TextStyle(
          color: isCursor ? activeColor : color,
          fontSize: fontSize,
          fontWeight: isCursor ? FontWeight.w700 : FontWeight.w400,
          fontFamily: 'monospace',
        ),
      );
      painter.textAlign = TextAlign.right;
      painter.layout(maxWidth: size.width);
      final y = topPad + line * lineHeight - scrollOffset;
      if (y + lineHeight < 0 || y > size.height + lineHeight) continue;
      painter.paint(canvas, Offset(size.width - painter.width, y));
    }
  }

  @override
  bool shouldRepaint(GutterPainter old) =>
      old.lineCount != lineCount ||
      old.scrollOffset != scrollOffset ||
      old.cursorLine != cursorLine ||
      old.color != color ||
      old.activeColor != activeColor;
}

/// Editor chính.
class CodeField extends StatefulWidget {
  const CodeField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.colors,
    this.fontSize = 15,
    this.onModified,
  });

  final CodeController controller;
  final FocusNode focusNode;
  final HighlightColors colors;
  final double fontSize;

  /// Gọi mỗi khi nội dung đổi (cho trạng thái "chưa lưu").
  final VoidCallback? onModified;

  @override
  State<CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState extends State<CodeField> {
  final ScrollController _scroll = ScrollController();
  String _prev = '';

  double get _lineHeight => widget.fontSize * 1.45;

  @override
  void initState() {
    super.initState();
    _prev = widget.controller.text;
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    final cur = widget.controller.text;
    if (cur != _prev) {
      _autoIndent(cur);
      _prev = widget.controller.text;
      widget.onModified?.call();
    }
  }

  /// Thụt lề tự động: Enter sau dòng có thụt lề (và kết thúc `:`) giữ nguyên
  /// hoặc tăng 4 dấu cách — khớp ngữ pháp thụt lề của ViScript.
  void _autoIndent(String after) {
    final sel = widget.controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    if (after.length <= _prev.length) return;
    final inserted =
        after.substring(sel.start - (after.length - _prev.length), sel.start);
    if (!inserted.endsWith('\n')) return;
    // Dòng trước vị trí chèn.
    final before = after.substring(0, sel.start - inserted.length);
    final lineStart = before.lastIndexOf('\n') + 1;
    final prevLine = before.substring(lineStart);
    final trimmed = prevLine.trimRight();
    final m = RegExp(r'^[ \t]*').firstMatch(prevLine);
    var indent = m?.group(0) ?? '';
    if (trimmed.endsWith(':')) indent += '    ';
    if (indent.isEmpty) return;
    final pos = sel.start;
    final insert = indent;
    final newText = after.substring(0, pos) + insert + after.substring(pos);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + insert.length),
    );
  }

  /// Chèn văn bản tại vị trí con trỏ (thanh phím nhanh).
  void insert(String s) {
    final sel = widget.controller.selection;
    final text = widget.controller.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid && !sel.isCollapsed ? sel.end : start;
    final newText = text.replaceRange(start, end, s);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + s.length),
    );
    widget.focusNode.requestFocus();
  }

  int get _cursorLine {
    final sel = widget.controller.selection;
    final off = sel.isValid ? sel.baseOffset : 0;
    final text = widget.controller.text;
    var line = 0;
    for (var i = 0; i < off && i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) line++;
    }
    return line;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fontSize = widget.fontSize;
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      height: 1.45,
      color: widget.colors.plain,
    );
    final gutter = AnimatedBuilder(
      animation: Listenable.merge([widget.controller, _scroll]),
      builder: (context, _) {
        return CustomPaint(
          painter: GutterPainter(
            lineCount: widget.controller.text.split('\n').length,
            lineHeight: _lineHeight,
            topPad: 14,
            scrollOffset: _scroll.hasClients ? _scroll.offset : 0,
            cursorLine: _cursorLine,
            color: cs.onSurface.withValues(alpha: 0.35),
            activeColor: cs.primary,
            fontSize: fontSize * 0.85,
          ),
          child: const SizedBox(width: 46),
        );
      },
    );

    final field = Expanded(
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        scrollController: _scroll,
        style: style,
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.top,
        cursorColor: cs.primary,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.fromLTRB(8, 14, 12, 24),
        ),
      ),
    );

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 50,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: Border(
                    right: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                ),
                child: gutter,
              ),
              field,
            ],
          ),
        ),
        _CodeBar(onKey: insert, colors: widget.colors),
      ],
    );
  }
}

/// Thanh phím nhanh: Tab (4 dấu cách), dấu ngoặc, chuỗi…
class _CodeBar extends StatelessWidget {
  const _CodeBar({required this.onKey, required this.colors});

  final ValueChanged<String> onKey;
  final HighlightColors colors;

  @override
  Widget build(BuildContext context) {
    final keys = [
      ('⇥', '    '),
      ('{', '{}'),
      ('}', '}'),
      ('(', '()'),
      (')', ')'),
      ('[', '[]'),
      (']', ']'),
      ('"', '"'),
      (':', ':'),
      ('->', ' -> '),
      ('..', '..'),
      ('?', '?'),
    ];
    return Container(
      height: 42,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        itemCount: keys.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final (label, ins) = keys[i];
          return InkWell(
            onTap: () => onKey(ins),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
