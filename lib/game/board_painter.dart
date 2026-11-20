// SPDX-License-Identifier: MIT
/// Painter bàn chơi Mê cung — vẽ bằng sprite PNG (không emoji): sàn checker
/// 2 variant, tường đá, cờ, ngọc, robot xoay theo hướng + tween mượt giữa
/// 2 frame (vị trí nội suy, góc quay cộng dồn theo chiều rẽ).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'maze.dart';
import 'sprites.dart';

/// Vẽ toàn bộ bàn chơi. [from]/[to] là hai frame liên tiếp của simulator,
/// [t] ∈ [0,1] là tiến trình tween giữa chúng (0 = đứng ở [from]).
class BoardPainter extends CustomPainter {
  BoardPainter({
    required this.level,
    required this.from,
    required this.to,
    required this.t,
    required this.sprites,
  });

  final MazeLevel level;
  final SimFrame from;
  final SimFrame to;
  final double t;
  final SpriteSet sprites;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / level.cols;
    final paint = Paint()..filterQuality = FilterQuality.medium;

    // Sàn + tường
    for (var y = 0; y < level.rows; y++) {
      for (var x = 0; x < level.cols; x++) {
        final img = level.grid[y][x] == '#'
            ? sprites.wall
            : ((x + y) % 2 == 0 ? sprites.floorA : sprites.floorB);
        _drawImage(canvas, img, Offset(x * cell, y * cell), cell, cell, paint);
      }
    }

    // Cờ (mục tiêu)
    _drawImage(canvas, sprites.flag,
        Offset(level.goal.x * cell, level.goal.y * cell), cell, cell, paint);

    // Ngọc: còn lại vẽ thường; vừa nhặt (có trong `to`, không có trong `from`)
    // mờ dần theo t.
    final justPicked = to.picked.length > from.picked.length;
    for (final it in level.items) {
      if (to.picked.contains(it)) {
        if (justPicked && !from.picked.contains(it)) {
          final a = (1.0 - t).clamp(0.0, 1.0);
          _drawImage(canvas, sprites.gem, Offset(it.x * cell, it.y * cell),
              cell, cell, Paint()..color = Color.fromRGBO(0, 0, 0, a));
        }
        continue;
      }
      _drawImage(canvas, sprites.gem, Offset(it.x * cell, it.y * cell), cell,
          cell, paint);
    }

    _paintRobot(canvas, size, cell, paint);
  }

  void _paintRobot(Canvas canvas, Size size, double cell, Paint paint) {
    // Nội suy vị trí (ô → pixel tâm) và góc quay cộng dồn.
    final fx = from.at.x + (to.at.x - from.at.x) * t;
    final fy = from.at.y + (to.at.y - from.at.y) * t;
    final cx = (fx + 0.5) * cell;
    final cy = (fy + 0.5) * cell;

    final angle = (from.q + (to.q - from.q) * t) * (math.pi / 2);

    // Đâm tường: robot giật lùi nhẹ theo hướng (rung sin tắt dần).
    var dx = 0.0;
    var dy = 0.0;
    if (to.bump) {
      final d = to.facing.delta;
      final amp = cell * 0.10 * math.sin(t * math.pi) * (1 - t);
      dx = d.x * amp;
      dy = d.y * amp;
      // Vòng đỏ cảnh báo quanh ô đâm.
      final bumpPaint = Paint()
        ..color = Color.fromRGBO(239, 68, 68, (0.55 * (1 - t)).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.06;
      canvas.drawCircle(
          Offset((to.at.x + 0.5) * cell, (to.at.y + 0.5) * cell), cell * 0.42,
          bumpPaint);
    }

    final s = cell * 1.5; // robot hơi to hơn ô — có "khí chất" như preview.
    canvas.save();
    canvas.translate(cx + dx, cy + dy);
    canvas.rotate(angle);
    _drawImage(
        canvas,
        sprites.robot,
        Offset(-s / 2, -s / 2),
        s,
        s,
        paint,
      );
    canvas.restore();
  }

  void _drawImage(Canvas canvas, ui.Image img, Offset at, double w, double h,
      Paint paint) {
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(at.dx, at.dy, w, h),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) =>
      old.from != from ||
      old.to != to ||
      old.t != t ||
      old.level != level ||
      !identical(old.sprites, sprites);
}
