// SPDX-License-Identifier: MIT
/// Nạp bộ sprite game từ assets (một lần, cache toàn app) cho CustomPainter.
///
/// Sprite do `scripts/gen_game_sprites.py` sinh (PIL, supersample 4×): robot
/// nhìn SANG PHẢI — painter xoay theo hướng bằng canvas.rotate.
library;

import 'dart:ui' as ui;

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

  Future<void> load() async {
    if (_loaded) return;
    robot = await _load('robot.png');
    floorA = await _load('tile_floor_a.png');
    floorB = await _load('tile_floor_b.png');
    wall = await _load('tile_wall.png');
    flag = await _load('flag.png');
    gem = await _load('gem.png');
    star = await _load('star.png');
    starOff = await _load('star_off.png');
    _loaded = true;
  }

  Future<ui.Image> _load(String name) async {
    final data = await rootBundle.load('assets/game/$name');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
