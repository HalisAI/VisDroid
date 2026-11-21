// SPDX-License-Identifier: MIT
/// Test logic Mê cung ViScript — thuần Dart, không cần engine FFI.
///
/// 10 route giải là stdout THẬT từ engine ViScript (`vis run`, xem
/// `scripts/game-snippets/v2/man-*.vis`, JSON `work/game-assets/
/// levels-verified.json`); par lấy đúng số bước simulator tính ra và khớp
/// với `par` khai báo trong levels.dart.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
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

    test('số quá lớn (> 2^63) → lỗi sạch, không crash int.parse', () {
      final pr = parseCommands('tien 99999999999999999999\n');
      expect(pr.ok, isFalse);
      expect(pr.error, contains('tien tối đa 100'));
      expect(pr.errorLine, 1);
    });

    test('stdout trống → lỗi "không in ra lệnh"', () {
      expect(parseCommands('').ok, isFalse);
    });

    test('cap 500 tính cả tổng bước đi: tien 100 × 6 → lỗi', () {
      // 5 lệnh × 100 bước = 500 bước — đúng mốc, vẫn hợp lệ.
      expect(parseCommands('tien 100\n' * 5).ok, isTrue);
      final pr = parseCommands('tien 100\n' * 6);
      expect(pr.ok, isFalse);
      expect(pr.error, contains('tổng số bước đi quá 500'));
    });

    test('thừa tab/khoảng trắng quanh lệnh vẫn đọc được', () {
      final pr = parseCommands('tien 5\t\n  phai  \n');
      expect(pr.ok, isTrue);
      expect(pr.cmds.map((c) => c.kind).toList(),
          [CmdKind.forward, CmdKind.turnRight]);
    });

    test('phân biệt hoa thường là chủ ý: TIEN là dòng lạ', () {
      // Helper in đúng "tien {n}" thường (scripts/game-snippets) — chữ hoa
      // không phải giao thức robot, báo lỗi cho người chơi sửa.
      final pr = parseCommands('TIEN 5\n');
      expect(pr.ok, isFalse);
      expect(pr.error, contains('TIEN 5'));
    });

    test("'tien 5.0' → lỗi dòng 1 (chỉ nhận số nguyên)", () {
      final pr = parseCommands('tien 5.0\n');
      expect(pr.ok, isFalse);
      expect(pr.errorLine, 1);
    });

    test('dòng lạ >1000 ký tự → lỗi nhưng echo bị cắt, không phình banner', () {
      final pr = parseCommands('${'x' * 1200}\n');
      expect(pr.ok, isFalse);
      expect(pr.error!.length, lessThan(200));
    });

    test('số quá lớn trong lỗi cũng bị cắt bớt', () {
      final pr = parseCommands('tien ${'9' * 300}\n');
      expect(pr.ok, isFalse);
      expect(pr.error!.length, lessThan(200));
    });
  });

  group('khai báo màn chơi', () {
    test('màn chơi: id duy nhất, mỗi thế giới khai báo đều có màn', () {
      // Không hardcode số màn — danh sách màn sẽ được mở rộng thêm.
      expect(kGameLevels, isNotEmpty);
      final ids = kGameLevels.map((l) => l.id).toSet();
      expect(ids, hasLength(kGameLevels.length));
      for (final w in kGameWorlds) {
        expect(
          kGameLevels.where((l) => l.world == w.id),
          isNot(isEmpty),
          reason: 'thế giới ${w.id} (${w.name}) không có màn nào',
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

    test('validateLevels: toàn bộ kGameLevels hợp lệ, không lỗi dữ liệu', () {
      // Helper soi sâu trong maze.dart (grid rỗng/hàng trống/lệch cột/ký tự
      // lạ/S-C trùng hay thiếu/S-C-X đè tường) — rỗng nghĩa là mọi màn sạch.
      expect(validateLevels(kGameLevels), isEmpty);
    });
  });

  group('validateLevels — bắt dữ liệu màn hỏng', () {
    MazeLevel mk(List<String> grid) => MazeLevel(
          id: 'test-mk',
          world: 1,
          title: '',
          task: '',
          grid: grid,
          startFacing: Facing.east,
          starterCode: '',
          hint: '',
          par: 1,
        );

    test('grid rỗng → báo lỗi, không ném "Bad state: No element"', () {
      expect(validateLevels([mk(const [])]), isNotEmpty);
    });

    test('hàng trống → báo lỗi', () {
      final p = validateLevels([mk(['####', '', '####'])]);
      expect(p.join(' | '), contains('trống'));
    });

    test('hàng lệch cột → báo lỗi', () {
      final p = validateLevels([mk(['####', '#S#'])]);
      expect(p.join(' | '), contains('lệch cột'));
    });

    test('ký tự lạ ngoài #.SCX → báo lỗi', () {
      final p = validateLevels([mk(['####', '#S?C#', '####'])]);
      expect(p.join(' | '), contains('ký tự lạ'));
    });

    test('thiếu S / thiếu C → báo lỗi thay vì StateError khi truy cập start', () {
      final p = validateLevels([mk(['####', '#..#', '####'])]);
      expect(p.join(' | '), contains('ô S'));
      expect(p.join(' | '), contains('ô C'));
    });

    test('hai ô S → báo lỗi', () {
      final p = validateLevels([mk(['####', '#SS#', '####'])]);
      expect(p.join(' | '), contains('2 ô S'));
    });

    test('lưới chuẩn 1 S 1 C → không lỗi', () {
      expect(validateLevels([mk(['####', '#SC#', '####'])]), isEmpty);
    });
  });

  group('MazeLevel — lưới lệch hàng', () {
    // Hàng 2 ngắn hơn hàng đầu (4 < 5) — cố tình lệch cột, không qua level
    // thật (levels.dart có test riêng bảo lưới đều cột).
    final lv = MazeLevel(
      id: 'test-lech-hang',
      world: 1,
      title: 'test',
      task: 'test',
      grid: ['#####', '#S.C'],
      startFacing: Facing.east,
      starterCode: '',
      hint: '',
      par: 2,
    );

    test('isWall: ngoài hàng ngắn là tường, không RangeError', () {
      expect(lv.isWall(const Cell(4, 1)), isTrue); // (4,1) ngoài hàng 2.
      expect(lv.isWall(const Cell(-1, 1)), isTrue);
      expect(lv.isWall(const Cell(2, 1)), isFalse); // ô sàn trong hàng.
      expect(lv.isWall(const Cell(0, 1)), isTrue); // '#' thường.
    });

    test('simulate trên lưới lệch hàng: đâm "tường" ngoài hàng thay vì crash', () {
      final pr = parseCommands('tien 4\n');
      final oc = simulate(lv, pr.cmds);
      expect(oc.win, isFalse);
      expect(oc.failMsg, contains('đâm tường'));
      expect(oc.failStep, 1);
    });

    test('simulate trên lưới lệch hàng: route trong hàng vẫn thắng', () {
      final pr = parseCommands('tien 2\n');
      final oc = simulate(lv, pr.cmds);
      expect(oc.win, isTrue, reason: oc.failMsg);
      expect(oc.frames.last.at, lv.goal);
    });
  });

  group('simulate — route giải thật phải WIN đúng par', () {
    // Màn mới thêm vào levels.dart chưa có route kiểm chứng sẽ được bổ sung
    // route sau; ở đây chỉ chạy các màn đã có route trong _solutions.
    for (final lv in kGameLevels) {
      final route = _solutions[lv.id];
      if (route == null) continue;
      test('màn ${lv.id} (${lv.title})', () {
        final pr = parseCommands(route);
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

  group('simulate — biên chạy', () {
    // Màn giả lập có hành lang đi LỐI qua cờ: C ở (3,1), sàn (4,1), tường (5,1).
    final lvQuaCo = MazeLevel(
      id: 'test-qua-co',
      world: 1,
      title: 'test',
      task: 'test',
      grid: ['######', '#S.C.#', '######'],
      startFacing: Facing.east,
      starterCode: '',
      hint: '',
      par: 3,
    );

    test('tien 0: parse hợp lệ, không sinh bước — kết thúc ở S nên thua rõ ràng', () {
      final pr = parseCommands('tien 0\n');
      expect(pr.ok, isTrue);
      final oc = simulate(_level('1'), pr.cmds);
      expect(oc.frames.length, 1); // chỉ còn frame ban đầu, không frame di chuyển.
      expect(oc.win, isFalse);
      expect(oc.failMsg, contains('cờ'));
    });

    test('đi LỐI qua cờ rồi dừng sau nó → thua, thông điệp dạy đúng chỗ dừng', () {
      // S ở (1,1), cờ ở (3,1): tien 3 đi QUA cờ, dừng ở (4,1).
      final pr = parseCommands('tien 3\n');
      final oc = simulate(lvQuaCo, pr.cmds);
      expect(oc.win, isFalse);
      expect(oc.failMsg, contains('NGAY trên ô cờ'));
      expect(oc.frames.last.at, const Cell(4, 1));
    });

    test('dừng đúng ô cờ (không có đồ để nhặt) → thắng', () {
      final pr = parseCommands('tien 2\n');
      final oc = simulate(lvQuaCo, pr.cmds);
      expect(oc.win, isTrue, reason: oc.failMsg);
    });
  });

  group('simulate — thất bại có dạy học', () {
    test('đâm tường → fail + frame bump, robot dừng ở ô cuối hợp lệ', () {
      final pr = parseCommands('tien 9\n');
      final oc = simulate(_level('1'), pr.cmds);
      expect(oc.win, isFalse);
      expect(oc.failMsg, contains('đâm tường'));
      expect(oc.failStep, 1);
      expect(oc.frames.last.bump, isTrue);
      // Màn 1: S(1,1) → đi east tới ô (6,1) liền trước tường (7,1) rồi bump.
      expect(oc.frames.last.at, const Cell(6, 1));
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
        final route = _solutions[lv.id];
        if (route == null) continue; // màn mới chưa có route — bỏ qua.
        final pr = parseCommands(route);
        final oc = simulate(lv, pr.cmds);
        final steps = oc.frames.length - 1;
        expect(p.starsFor(steps, lv.par), 3,
            reason: 'màn ${lv.id}: route chuẩn phải đạt 3★');
      }
    });

    test('id cũ trong file lưu không làm sai allDone/totalStars', () async {
      final p = await fresh();
      // Tiến độ của màn không còn trong kGameLevels (danh sách màn đổi giữa
      // các bản app) — phải bị bỏ qua khi tính tổng, không tính nhầm.
      p.stars['id_da_xoa'] = 3;
      for (final lv in kGameLevels) {
        p.recordWin(lv, lv.par);
      }
      expect(p.allDone, isTrue);
      expect(p.totalStars, kGameLevels.length * 3);
      expect(p.totalStars, p.maxStars);
    });

    testWidgets('file lưu lẫn kiểu lạ: mục sai kiểu bị bỏ, phần lành vẫn giữ', (tester) async {
      const ch = MethodChannel('visdroid/prefs');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ch, (m) async {
        if (m.method != 'get') return null;
        return jsonEncode({
          'game_progress_v2': jsonEncode({
            'stars': {'1': 3, '2': 'ba', '3': 99, '4': -2},
            'best': {'1': 5, '2': [1]},
            'code': {'1': 'ok', '2': 42},
          }),
        });
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(ch, null));
      final p = await fresh();
      await p.load(); // fresh() chỉ dựng đối tượng — phải load() mới đọc prefs.
      expect(p.starsOf(kGameLevels[0]), 3); // mục lành giữ nguyên
      expect(p.starsOf(kGameLevels[1]), 0); // 'ba' sai kiểu → bỏ, không xoá sạch
      expect(p.starsOf(kGameLevels[2]), 3); // 99 → kẹp trong 0..3
      expect(p.starsOf(kGameLevels[3]), 0); // âm → 0
      expect(p.totalStars, p.maxStars - (kGameLevels.length - 2) * 3);
      expect(p.bestOf(kGameLevels[0]), 5);
      expect(p.bestOf(kGameLevels[1]), isNull); // list → bỏ
      expect(p.codeOf(kGameLevels[0]), 'ok');
      expect(p.codeOf(kGameLevels[1]), kGameLevels[1].starterCode); // 42 → bỏ
    });
  });
}
