// SPDX-License-Identifier: MIT
/// Hiệu ứng âm thanh của Mê cung — audioplayers, một player cho mỗi SFX
/// (mode lowLatency cho âm ngắn kiểu game).
///
/// Thiết kế an toàn: thiếu plugin/thiết bị không âm thanh thì chơi im lặng,
/// không bao giờ làm app chết (mọi lỗi nuốt trong try/catch). WAV do
/// `scripts/gen_sfx.py` sinh — 44.1 kHz mono 16-bit, peak −6 dBFS.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class SoundFx {
  SoundFx._();

  static final SoundFx instance = SoundFx._();

  final Map<String, AudioPlayer> _players = {};
  bool _inited = false;

  static const List<String> _names = [
    'step', 'pickup', 'win', 'fail', 'click', 'unlock',
  ];

  /// Nạp một lần lúc app vào màn chọn game. Fire-and-forget được.
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      for (final n in _names) {
        final p = AudioPlayer(playerId: 'visdroid_sfx_$n');
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setSource(AssetSource('game/sfx/$n.wav'));
        _players[n] = p;
      }
    } catch (e) {
      debugPrint('SoundFx init bỏ qua: $e');
      // Dọn player đã tạo trước khi lỗi (thiếu asset/thiết bị) — không thì
      // mỗi lần init hỏng lại rò một nhóm player native.
      for (final p in _players.values) {
        try {
          await p.dispose();
        } catch (_) {
          // Player hỏng sẵn thì bỏ qua — mục tiêu chỉ là không rò rỉ.
        }
      }
      _players.clear();
    }
  }

  void step() => _play('step');
  void pickup() => _play('pickup');
  void win() => _play('win');
  void fail() => _play('fail');
  void click() => _play('click');
  void unlock() => _play('unlock');

  void _play(String name) {
    final p = _players[name];
    if (p == null) return;
    p.play(AssetSource('game/sfx/$name.wav')).catchError((_) {});
  }
}
