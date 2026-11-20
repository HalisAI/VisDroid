// SPDX-License-Identifier: MIT
/// Confetti ăn mừng khi qua màn — hạt rơi văng màu palette game, một lần
/// chạy rồi tự dừng. Seed cố định để mỗi lần nổ giống nhau (dễ soi bug).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.pieces = 90});

  final int pieces;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..forward();

  late final List<_Piece> _pieces = _gen();

  List<_Piece> _gen() {
    final rng = math.Random(11);
    const colors = [
      Color(0xFFFBBF24),
      Color(0xFF34D399),
      Color(0xFF4F8EF7),
      Color(0xFFEF7DA0),
      Color(0xFFE8ECF8),
    ];
    return List.generate(widget.pieces, (i) {
      return _Piece(
        x: rng.nextDouble(),
        y: -0.10 - rng.nextDouble() * 0.45,
        vx: (rng.nextDouble() - 0.5) * 0.24,
        vy: 0.45 + rng.nextDouble() * 0.5,
        size: 4 + rng.nextDouble() * 6,
        color: colors[i % colors.length],
        spin: (rng.nextDouble() - 0.5) * 6,
        circle: rng.nextBool(),
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _ConfettiPainter(_pieces, _c.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.spin,
    required this.circle,
  });

  final double x;
  final double y;
  final double vx;
  final double vy;
  final double size;
  final Color color;
  final double spin;
  final bool circle;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.progress);

  final List<_Piece> pieces;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1) return;
    for (final p in pieces) {
      final px = (p.x + p.vx * progress) * size.width;
      final py =
          (p.y + p.vy * progress + 1.8 * progress * progress) * size.height;
      final alpha = (1 - progress).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = p.color.withValues(alpha: alpha);
      final rot = p.spin * progress * math.pi;
      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(rot);
      if (p.circle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawAngleRect(p.size, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.progress != progress;
}

extension on Canvas {
  // Hình chữ nhật xoay — dùng path cho góc vát nhẹ (giấy vụn).
  void drawAngleRect(double size, Paint paint) {
    final half = size / 2;
    drawRect(Rect.fromCenter(center: Offset.zero, width: size, height: half), paint);
  }
}
