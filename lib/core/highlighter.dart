// SPDX-License-Identifier: MIT
/// Tô màu cú pháp ViScript cho editor.
///
/// Tokenizer nhẹ một lượt qua văn bản, khớp đặc tả lex của engine
/// (`native/ViScript/docs/SPEC-lex.md`):
/// - chú thích `# …` tới cuối dòng (không có block comment)
/// - chuỗi `"…"` có nội suy `{{name}}`, chuỗi thô `r"…"`, byte `b"…"`
/// - số có gạch dưới `1_000`, hex `0xff`, nhị phân `0b1010`, đơn vị `5mb`, `250ms`
/// - 40 từ khoá (bảng `KEYWORDS` của vis-syntax) + kiểu dựng sẵn
/// - định danh Unicode (tên tiếng Việt được)
library;

import 'package:material_ui/material_ui.dart';

const List<String> visKeywords = [
  'alias', 'and', 'async', 'await', 'break', 'cmd', 'const', 'continue',
  'derives', 'dyn', 'elif', 'else', 'enum', 'extern', 'false', 'fn', 'for',
  'has', 'if', 'impl', 'in', 'let', 'loop', 'match', 'newtype', 'none',
  'not', 'or', 'pub', 'ref', 'return', 'scope', 'self', 'trait', 'true',
  'type', 'use', 'var', 'while', 'with',
];

/// Kiểu dựng sẵn + giá trị chuẩn — tô cùng nhóm "kiểu".
const List<String> visTypes = [
  'int', 'float', 'str', 'bool', 'list', 'map', 'set', 'size', 'duration',
  'Result', 'Ok', 'Err', 'Some', 'None', 'self',
];

/// Hàm chuẩn hay gặp — tô nhóm "hàm" (chỉ để gợi ý màu, sai lệch nhẹ chấp nhận được).
const List<String> visBuiltins = [
  'print', 'main',
];

/// Bảng màu highlight, phân biệt light/dark.
class HighlightColors {
  const HighlightColors({
    required this.keyword,
    required this.type,
    required this.string,
    required this.number,
    required this.comment,
    required this.builtin,
    required this.punct,
    required this.plain,
  });

  final Color keyword, type, string, number, comment, builtin, punct, plain;

  static const light = HighlightColors(
    keyword: Color(0xFF7C3AED), // tím
    type: Color(0xFF0E7490), // teal đậm
    string: Color(0xFF15803D), // xanh lá
    number: Color(0xFFB45309), // cam đất
    comment: Color(0xFF6B7280), // xám
    builtin: Color(0xFF2563EB), // xanh dương
    punct: Color(0xFF4B5563),
    plain: Color(0xFF111827),
  );

  static const dark = HighlightColors(
    keyword: Color(0xFFC792EA),
    type: Color(0xFF66D9EF),
    string: Color(0xFFC3E88D),
    number: Color(0xFFF78C6C),
    comment: Color(0xFF7F8C98),
    builtin: Color(0xFF82AAFF),
    punct: Color(0xFFB0BEC5),
    plain: Color(0xFFD6DEEB),
  );
}

bool _isIdentStart(int c) {
  // UAX #31: chữ cái Unicode + '_' ; chữ số không đứng đầu (khỏi xét ở đây).
  return c == 0x5F ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c >= 0x80;
}

bool _isIdentPart(int c) => _isIdentStart(c) || (c >= 0x30 && c <= 0x39);

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isHexDigit(int c) =>
    _isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66);

/// Đơn vị đo — bám sau số (`5mb`, `1kib`, `250ms`, `2h30m`).
const List<String> _sizeUnits = [
  'b', 'kb', 'kib', 'mb', 'mib', 'gb', 'gib', 'tb', 'tib', 'pb', 'pib'
];
const List<String> _timeUnits = ['ms', 's', 'm', 'h', 'd'];

/// Cấu trúc một đoạn đã tô.
class HlSpan {
  HlSpan(this.start, this.end, this.style);
  final int start;
  final int end;
  final TextStyle style;
}

/// Quét cả văn bản thành danh sách span màu.
List<HlSpan> highlight(String text, HighlightColors c) {
  final spans = <HlSpan>[];
  final n = text.length;
  var i = 0;
  var lineStart = true; // để nhận `##` doc-comment sau thụt lề

  while (i < n) {
    final ch = text.codeUnitAt(i);
    if (ch == 0x0A) {
      spans.add(HlSpan(i, i + 1, TextStyle(color: c.punct)));
      i++;
      lineStart = true;
      continue;
    }
    if (ch == 0x20 || ch == 0x09) {
      i++;
      continue;
    }
    // Chú thích: `##` (doc) hoặc `#` tới cuối dòng.
    if (ch == 0x23) {
      final start = i;
      i++;
      final doc = lineStart && i < n && text.codeUnitAt(i) == 0x23;
      if (doc) i++;
      while (i < n && text.codeUnitAt(i) != 0x0A) {
        i++;
      }
      final st = doc
          ? TextStyle(color: c.comment, fontStyle: FontStyle.italic)
          : TextStyle(color: c.comment);
      spans.add(HlSpan(start, i, st));
      continue;
    }
    // Chuỗi thô r"…" / byte b"…" / chuỗi thường "…"
    if ((ch == 0x72 || ch == 0x62 || ch == 0x52 || ch == 0x42) &&
        i + 1 < n &&
        text.codeUnitAt(i + 1) == 0x22) {
      i = _scanString(text, i + 1, spans, c, prefixStart: i, raw: true);
      lineStart = false;
      continue;
    }
    if (ch == 0x22) {
      i = _scanString(text, i, spans, c);
      lineStart = false;
      continue;
    }
    // Ký tự đơn 'x'
    if (ch == 0x27) {
      final start = i;
      i++;
      while (i < n && text.codeUnitAt(i) != 0x27 && text.codeUnitAt(i) != 0x0A) {
        // Cặp surrogate phải còn đủ 2 đơn vị mới nhảy 2: UTF-16 gãy (surrogate
        // đơn nằm cuối văn bản) tiến 1 thôi, không thì i vượt quá n và
        // substring khi dựng TextSpan ném RangeError ngay lúc gõ.
        i += (i + 1 < n &&
                text.codeUnitAt(i) >= 0xD800 &&
                text.codeUnitAt(i) < 0xDC00)
            ? 2
            : 1;
      }
      if (i < n && text.codeUnitAt(i) == 0x27) i++;
      spans.add(HlSpan(start, i, TextStyle(color: c.string)));
      lineStart = false;
      continue;
    }
    // Số (kể cả đơn vị)
    if (_isDigit(ch)) {
      final start = i;
      if (ch == 0x30 && i + 1 < n) {
        final nx = text.codeUnitAt(i + 1) | 0x20; // x/X, b/B
        if (nx == 0x78) {
          i += 2;
          while (i < n && _isHexDigit(text.codeUnitAt(i))) {
            i++;
          }
        } else if (nx == 0x62) {
          i += 2;
          while (i < n && (text.codeUnitAt(i) == 0x30 || text.codeUnitAt(i) == 0x31)) {
            i++;
          }
        } else {
          i = _scanDec(text, i);
        }
      } else {
        i = _scanDec(text, i);
      }
      // Đơn vị cỡ/thời gian: 5mb, 1kib, 250ms, 2h30m…
      i = _scanUnits(text, i);
      spans.add(HlSpan(start, i, TextStyle(color: c.number)));
      lineStart = false;
      continue;
    }
    // Định danh / từ khoá
    if (_isIdentStart(ch)) {
      final start = i;
      i++;
      while (i < n && _isIdentPart(text.codeUnitAt(i))) {
        // Như khối ký tự đơn ở trên: chỉ nhảy 2 khi cặp surrogate còn nguyên.
        i += (i + 1 < n &&
                text.codeUnitAt(i) >= 0xD800 &&
                text.codeUnitAt(i) < 0xDC00)
            ? 2
            : 1;
      }
      final word = text.substring(start, i);
      TextStyle st;
      if (visKeywords.contains(word)) {
        st = TextStyle(color: c.keyword, fontWeight: FontWeight.w600);
      } else if (visTypes.contains(word)) {
        st = TextStyle(color: c.type);
      } else if (visBuiltins.contains(word)) {
        st = TextStyle(color: c.builtin);
      } else if (i < n && text.codeUnitAt(i) == 0x28) {
        // gọi hàm — tô xanh nhạt
        st = TextStyle(color: c.builtin);
      } else {
        st = TextStyle(color: c.plain);
      }
      spans.add(HlSpan(start, i, st));
      lineStart = false;
      continue;
    }
    // Dấu câu
    spans.add(HlSpan(i, i + 1, TextStyle(color: c.punct)));
    i++;
    lineStart = false;
  }
  return spans;
}

int _scanDec(String text, int i) {
  final n = text.length;
  while (i < n) {
    final ch = text.codeUnitAt(i);
    if (_isDigit(ch) || ch == 0x5F) {
      i++;
    } else if (ch == 0x2E /* . */ &&
        i + 1 < n &&
        _isDigit(text.codeUnitAt(i + 1))) {
      i += 2;
    } else {
      break;
    }
  }
  return i;
}

/// Nhận các đơn vị sau số: `kb kib mb mib gb gib tb tib pb pib b ms s m h d`.
int _scanUnits(String text, int i) {
  var j = i;
  while (true) {
    if (j >= text.length) break;
    final ch = text.codeUnitAt(j);
    if (!_isIdentStart(ch)) break;
    var k = j + 1;
    while (k < text.length && _isIdentPart(text.codeUnitAt(k))) {
      k++;
    }
    final word = text.substring(j, k).toLowerCase();
    if (_sizeUnits.contains(word) || _timeUnits.contains(word)) {
      j = k;
      // `2h30m` — tiếp nối bởi chữ số khác thì quét số + đơn vị tiếp.
      if (k < text.length && _isDigit(text.codeUnitAt(k))) {
        k = _scanDec(text, k);
        var m = k;
        while (m < text.length && _isIdentPart(text.codeUnitAt(m))) {
          m++;
        }
        final w2 = text.substring(k, m).toLowerCase();
        if (_sizeUnits.contains(w2) || _timeUnits.contains(w2)) {
          j = m;
          continue;
        }
        break;
      }
      continue;
    }
    break;
  }
  return j;
}

/// Quét chuỗi bắt đầu tại `quotePos` (vị trí ký tự `"`); trả vị trí mới.
int _scanString(
  String text,
  int quotePos,
  List<HlSpan> spans,
  HighlightColors c, {
  int? prefixStart,
  bool raw = false,
}) {
  final start = prefixStart ?? quotePos;
  final n = text.length;
  var i = quotePos + 1;
  while (i < n) {
    final ch = text.codeUnitAt(i);
    if (ch == 0x5C && !raw && i + 1 < n) {
      i += 2;
      continue;
    }
    if (ch == 0x22) {
      i++;
      break;
    }
    if (ch == 0x0A) break; // chuỗi một dòng — dừng tại newline
    i++;
  }
  spans.add(HlSpan(start, i, TextStyle(color: c.string)));
  return i;
}

/// Chuyển span thành `TextSpan` cho TextField.
TextSpan buildHighlightTextSpan(String text, HighlightColors c) {
  final spans = highlight(text, c);
  if (spans.isEmpty) {
    return TextSpan(text: text, style: TextStyle(color: c.plain));
  }
  final children = <TextSpan>[];
  var pos = 0;
  for (final s in spans) {
    if (s.start > pos) {
      children.add(TextSpan(
          text: text.substring(pos, s.start),
          style: TextStyle(color: c.plain)));
    }
    children.add(
        TextSpan(text: text.substring(s.start, s.end), style: s.style));
    pos = s.end;
  }
  if (pos < text.length) {
    children.add(
        TextSpan(text: text.substring(pos), style: TextStyle(color: c.plain)));
  }
  return TextSpan(
    style: TextStyle(color: c.plain),
    children: children,
  );
}
