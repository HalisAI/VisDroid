// SPDX-License-Identifier: MIT
/// Hiệu ứng âm thanh của Mê cung — Soundpool cho SFX ngắn latency thấp.
///
/// Thiết kế an toàn: thiếu plugin/thiết bị không âm thanh thì chơi im lặng,
/// không bao giờ làm app chết (mọi lỗi nuốt trong try/catch). WAV do
/// `scripts/gen_sfx.py` sinh — 44.1 kHz mono 16-bit, peak −6 dBFS.
///
/// API của soundpool 2.x: nạp ByteData qua rootBundle một lần, lưu soundId,
/// play theo id (xem README của package).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:soundpool/soundpool.dart';

class SoundFx {
  SoundFx._();

  static final SoundFx instance = SoundFx._();

  Soundpool? _pool;
  int? _step;
  int? _pickup;
  int? _win;
  int? _fail;
  int? _click;
  int? _unlock;
  bool _inited = false;

  /// Nạp một lần lúc app vào màn chọn game. Fire-and-forget được.
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      final pool = Soundpool(streamType: StreamType.music);
      _step = await pool.load(await rootBundle.load('assets/game/sfx/step.wav'));
      _pickup =
          await pool.load(await rootBundle.load('assets/game/sfx/pickup.wav'));
      _win = await pool.load(await rootBundle.load('assets/game/sfx/win.wav'));
      _fail = await pool.load(await rootBundle.load('assets/game/sfx/fail.wav'));
      _click =
          await pool.load(await rootBundle.load('assets/game/sfx/click.wav'));
      _unlock =
          await pool.load(await rootBundle.load('assets/game/sfx/unlock.wav'));
      _pool = pool;
    } catch (e) {
      debugPrint('SoundFx init bỏ qua: $e');
      _pool = null;
    }
  }

  void step() => _play(_step);
  void pickup() => _play(_pickup);
  void win() => _play(_win);
  void fail() => _play(_fail);
  void click() => _play(_click);
  void unlock() => _play(_unlock);

  void _play(int? soundId) {
    final pool = _pool;
    if (pool == null || soundId == null) return;
    pool.play(soundId).catchError((_) => 0);
  }
}
