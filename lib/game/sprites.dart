// SPDX-License-Identifier: MIT
/// Nạp bộ sprite game từ assets (một lần, cache toàn app) cho CustomPainter.
///
/// Sprite do `scripts/gen_game_sprites.py` sinh (PIL, supersample 4×): robot
/// nhìn SANG PHẢI — painter xoay theo hướng bằng canvas.rotate.
///
/// An toàn khi thiếu asset: từng file nạp trong try/catch, lỗi (file thiếu,
/// decode hỏng) được thay bằng ảnh màu đặc 8×8 tối giản — `ready` vẫn trở
/// thành true, painter luôn có ảnh để vẽ, không crash LateInitializationError.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

class SpriteSet {
  SpriteSet._();

  static final SpriteSet instance = SpriteSet._();

  late ui.Image robot;
  late ui.Image floorA;
  late ui.Image floorB;
  late ui.Image wall;
  late ui.Image flag;
  late ui.Image gem;
  late ui.Image star;
  late ui.Image starOff;

  bool get ready => _loaded;
  bool _loaded = false;

  /// Future của lần nạp đang chạy — màn chọn và màn chơi cùng gọi load()
  /// gần nhau thì chia sẻ một lần decode thay vì nạp trùng.
  Future<void>? _loading;

  Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _loadAll();
  }

  Future<void> _loadAll() async {
    robot = await _loadSafe('robot.png', const ui.Color(0xFF4F8EF7));
    floorA = await _loadSafe('tile_floor_a.png', const ui.Color(0xFF232B4D));
    floorB = await _loadSafe('tile_floor_b.png', const ui.Color(0xFF1C2438));
    wall = await _loadSafe('tile_wall.png', const ui.Color(0xFF3A4668));
    flag = await _loadSafe('flag.png', const ui.Color(0xFFFBBF24));
    gem = await _loadSafe('gem.png', const ui.Color(0xFF34D399));
    star = await _loadSafe('star.png', const ui.Color(0xFFFBBF24));
    starOff = await _loadSafe('star_off.png', const ui.Color(0xFF64748B));
    _loaded = true;
  }

  Future<ui.Image> _loadSafe(String name, ui.Color fallback) async {
    try {
      return await _load(name);
    } catch (e) {
      debugPrint('Sprite $name nạp lỗi, dùng màu thay thế: $e');
      return _solidImage(fallback);
    }
  }

  Future<ui.Image> _load(String name) async {
    final data = await rootBundle.load('assets/game/$name');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Ảnh màu đặc 8×8 vẽ bằng PictureRecorder — fallback không phụ thuộc asset.
  Future<ui.Image> _solidImage(ui.Color color) async {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, 8, 8), ui.Paint()..color = color);
    final pic = rec.endRecording();
    final img = await pic.toImage(8, 8);
    pic.dispose();
    return img;
  }
}
