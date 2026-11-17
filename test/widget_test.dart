// SPDX-License-Identifier: MIT
// Smoke test highlighter: span phủ đủ toàn văn bản + nhận đúng loại token.
import 'package:flutter/widgets.dart' show TextSpan;
import 'package:flutter_test/flutter_test.dart';
import 'package:visdroid/core/highlighter.dart';

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
}
