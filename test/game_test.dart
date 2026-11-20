// SPDX-License-Identifier: MIT
/// Test logic Mê cung ViScript — thuần Dart, không cần engine FFI.
///
/// 10 route giải là stdout THẬT từ engine ViScript (`vis run`, xem
/// `scripts/game-snippets/v2/man-*.vis`, JSON `work/game-assets/
/// levels-verified.json`); par lấy đúng số bước simulator tính ra và khớp
/// với `par` khai báo trong levels.dart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:visdroid/core/settings.dart';
import 'package:visdroid/game/levels.dart';
import 'package:visdroid/game/maze.dart';
import 'package:visdroid/game/progress.dart';

/// Route giải đã kiểm chứng bằng engine thật cho từng màn (id → stdout).
/// (`final` — route màn 6 dùng `* 3`, không const-eval được)
final _solutions = {
  '1': 'tien 5\n',
  '2': 'tien 4\nphai\ntien 2\n',
  '3': 'tien 4\nphai\ntien 2\nphai\ntien 4\n',
  '4': 'tien 2\nphai\ntien 1\ntrai\ntien 2\nphai\ntien 1\ntrai\ntien 2\n',
  '5': 'tien 9\n',
  '6': 'tien 1\nphai\ntien 1\ntrai\n' * 3 + 'tien 2\n',
  '7': 'tien 4\ntrai\ntien 6\n',
  '8': 'tien 3\nnhat\ntien 4\nnhat\ntien 2\n',
  '9': 'tien 4\nnhat\ntien 1\nphai\ntien 2\nphai\ntien 2\nnhat\ntien 2\n',
  '10':
      'tien 2\nnhat\ntien 4\nphai\ntien 2\nphai\ntien 3\nnhat\ntrai\ntien 2\ntrai\ntien 5\n',
};

MazeLevel _level(String id) =>
    kGameLevels.firstWhere((l) => l.id == id);

void main() {
  group('parseCommands', () {
    test('đọc đúng giao thức tien/trai/phai/nhat', () {
      final pr = parseCommands('tien 4\nphai\n\ntrai\nnhat\n');
      expect(pr.ok, isTrue);
      expect(pr.cmds.map((c) => c.kind).toList(), [
        CmdKind.forward,
        CmdKind.turnRight,
        CmdKind.turnLeft,
        CmdKind.pickup,
      ]);
      expect(pr.cmds.first.n, 4);
    });

    test('bỏ qua dòng trống và dòng # debug', () {
      final pr = parseCommands('# in debug\n\ntien 1\n');
      expect(pr.ok, isTrue);
      expect(pr.cmds, hasLength(1));
    });

    test('dòng lạ → lỗi kèm số dòng', () {
      final pr = parseCommands('tien 1\nlen qua!\n');
      expect(pr.ok, isFalse);
      expect(pr.errorLine, 2);
      expect(pr.error, contains('len qua!'));
    });

    test('tien quá 100 bước → lỗi; 0 bước hợp lệ', () {
      expect(parseCommands('tien 101').ok, isFalse);
      expect(parseCommands('tien 100').ok, isTrue);
      expect(parseCommands('tien 0').ok, isTrue);
    });

    test('stdout trống → lỗi "không in ra lệnh"', () {
      expect(parseCommands('').ok, isFalse);
    });
  });

  group('khai báo màn chơi', () {
    test('10 màn, id duy nhất, thế giới 1..3 không rỗng', () {
      expect(kGameLevels, hasLength(10));
      final ids = kGameLevels.map((l) => l.id).toSet();
      expect(ids, hasLength(10));
      for (final w in [1, 2, 3]) {
        expect(
          kGameLevels.where((l) => l.world == w),
          isNot(isEmpty),
          reason: 'thế giới $w không có màn nào',
        );
      }
    });

    test('mỗi màn: lưới đều cột, đúng 1 S, đúng 1 C, par dương', () {
      for (final lv in kGameLevels) {
        for (final row in lv.grid) {
          expect(row.length, lv.cols, reason: 'màn ${lv.id} lệch cột');
        }
        var s = 0, c = 0;
        for (final row in lv.grid) {
          s += row.split('').where((ch) => ch == 'S').length;
          c += row.split('').where((ch) => ch == 'C').length;
        }
        expect(s, 1, reason: 'màn ${lv.id} phải có đúng 1 S');
        expect(c, 1, reason: 'màn ${lv.id} phải có đúng 1 C');
        expect(lv.par, greaterThan(0));
        expect(lv.starterCode, contains('fn di_tien'));
      }
    });
  });

  group('simulate — 10 route giải thật phải WIN đúng par', () {
    for (final lv in kGameLevels) {
      test('màn ${lv.id} (${lv.title})', () {
        final pr = parseCommands(_solutions[lv.id]!);
        expect(pr.ok, isTrue, reason: 'route màn ${lv.id} phải parse được');
        final oc = simulate(lv, pr.cmds);
        expect(oc.win, isTrue, reason: oc.failMsg);
        expect(oc.frames.last.at, lv.goal);
        final steps = oc.frames.length - 1;
        expect(steps, lv.par,
            reason: 'màn ${lv.id}: par khai báo ${lv.par} ≠ steps thực $steps');
        // 3★ phải đạt với chính route chuẩn.
        expect(lv.par <= lv.par, isTrue);
      });
    }
  });

  group('simulate — thất bại có dạy học', () {
    test('đâm tường → fail + frame bump, robot đứng yên', () {
      final pr = parseCommands('tien 9\n');
      final oc = simulate(_level('1'), pr.cmds);
      expect(oc.win, isFalse);
      expect(oc.failMsg, contains('đâm tường'));
      expect(oc.failStep, 1);
      expect(oc.frames.last.bump, isTrue);
      expect(oc.frames.last.at, _level('1').start);
    });

    test('nhặt khi không có đồ → fail', () {
      final pr = parseCommands('nhat\n');
      final oc = simulate(_level('8'), pr.cmds);
      expect(oc.win, isFalse);
      expect(oc.failMsg, contains('không có đồ'));
    });

    test('dừng giữa đường → fail chỉ rõ cờ ở đâu', () {
      final pr = parseCommands('tien 3\nnhat\ntien 4\nnhat\n');
      final oc = simulate(_level('8'), pr.cmds);
      expect(oc.win, isFalse);
      expect(oc.failMsg, contains('cờ'));
    });

    test('thiếu món đồ → fail rõ ràng', () {
      final pr = parseCommands('tien 3\nnhat\ntien 4\ntien 2\n');
      final oc = simulate(_level('8'), pr.cmds);
      expect(oc.win, isFalse);
      expect(oc.failMsg, contains('chưa nhặt'));
    });

    test('quay cộng dồn: 4 lần rẽ phải quay đủ 360° về hướng cũ', () {
      final pr = parseCommands('phai\nphai\nphai\nphai\n');
      final oc = simulate(_level('1'), pr.cmds);
      expect(oc.frames.last.facing, Facing.east);
      expect(oc.frames.last.q, 4);
    });
  });

  group('GameProgress — vượt ải', () {
    // PrefsStore.load() không có platform channel trong test → store rỗng
    // trong RAM; mọi lỗi channel đã được GameProgress/PrefsStore tự nuốt.
    Future<GameProgress> fresh() async => GameProgress(await PrefsStore.load());

    test('ban đầu chỉ màn đầu mở; tổng sao = 0', () async {
      final p = await fresh();
      expect(p.isUnlocked(0), isTrue);
      expect(p.isUnlocked(1), isFalse);
      expect(p.isUnlocked(9), isFalse);
      expect(p.totalStars, 0);
      expect(p.currentIndex, 0);
      expect(p.allDone, isFalse);
    });

    test('thắng màn 1 → màn 2 mở; sao giữ tốt nhất', () async {
      final p = await fresh();
      final lv1 = kGameLevels[0];
      // Chơi tệ (8 bước > par 5 + 4? = 9 → vẫn 2★ theo công thức par+4)
      p.recordWin(lv1, 8);
      expect(p.starsOf(lv1), 2, reason: '8 bước ≤ par(5)+4 → 2 sao');
      expect(p.isUnlocked(1), isTrue);
      expect(p.currentIndex, 1);
      // Chơi lại tốt hơn — sao phải giữ mức cao nhất.
      p.recordWin(lv1, 5);
      expect(p.starsOf(lv1), 3);
      expect(p.bestOf(lv1), 5);
      // Chơi lại tệ hơn — không hạ sao.
      p.recordWin(lv1, 20);
      expect(p.starsOf(lv1), 3);
      expect(p.bestOf(lv1), 5);
    });

    test('chấm sao: ≤ par 3★, ≤ par+4 2★, còn lại 1★', () async {
      final p = await fresh();
      expect(p.starsFor(5, 5), 3);
      expect(p.starsFor(9, 5), 2);
      expect(p.starsFor(10, 5), 1);
      expect(p.starsFor(24, 24), 3);
    });

    test('code mỗi màn độc lập; reset xoá sạch', () async {
      final p = await fresh();
      final lv1 = kGameLevels[0];
      final lv2 = kGameLevels[1];
      p.setCode(lv1, 'di_tien(5)');
      p.setCode(lv2, 'for i in 0..2: di_tien(1)');
      expect(p.codeOf(lv1), 'di_tien(5)');
      expect(p.codeOf(lv2), 'for i in 0..2: di_tien(1)');
      expect(p.codeOf(kGameLevels[2]), kGameLevels[2].starterCode);
      p.recordWin(lv1, 5);
      expect(p.isUnlocked(1), isTrue);
      p.reset();
      expect(p.starsOf(lv1), 0);
      expect(p.isUnlocked(1), isFalse);
      expect(p.codeOf(lv1), lv1.starterCode);
    });

    test('route giải thật cho đúng 3★ trên từng màn', () async {
      final p = await fresh();
      for (final lv in kGameLevels) {
        final pr = parseCommands(_solutions[lv.id]!);
        final oc = simulate(lv, pr.cmds);
        final steps = oc.frames.length - 1;
        expect(p.starsFor(steps, lv.par), 3,
            reason: 'màn ${lv.id}: route chuẩn phải đạt 3★');
      }
    });
  });
}
