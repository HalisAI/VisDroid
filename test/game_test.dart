// SPDX-License-Identifier: MIT
/// Test logic Mê cung ViScript — thuần Dart, không cần engine FFI.
///
/// Route giải là stdout THẬT của script mẫu đã chạy qua engine (`vis run`,
/// xem `scripts/game-snippets/`); hình học màn chơi đối chiếu với
/// `scripts/verify_maze_levels.py`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:visdroid/game/maze.dart';

/// Route giải đúng của từng màn (stdout từ engine thật).
const _solutions = {
  '1': 'tien 5\n',
  '2': 'tien 4\nphai\ntien 3\n',
  '3': 'tien 3\nnhat\ntien 4\nnhat\ntien 2\n',
  '4': 'tien 1\nphai\ntien 1\ntrai\n' * 3 + 'tien 2\n',
};

MazeLevel _level(String id) =>
    kMazeLevels.firstWhere((l) => l.id == id);

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

    test('tien quá 100 bước → lỗi', () {
      expect(parseCommands('tien 101').ok, isFalse);
      expect(parseCommands('tien 100').ok, isTrue);
    });

    test('stdout trống → lỗi "không in ra lệnh"', () {
      expect(parseCommands('').ok, isFalse);
    });
  });

  group('simulate — route giải thật phải WIN', () {
    for (final entry in _solutions.entries) {
      test('màn ${entry.key} thắng với route engine thật', () {
        final pr = parseCommands(entry.value);
        expect(pr.ok, isTrue);
        final oc = simulate(_level(entry.key), pr.cmds);
        expect(oc.win, isTrue, reason: oc.failMsg);
        expect(oc.frames.last.at, _level(entry.key).goal);
      });
    }
  });

  group('simulate — lỗi học được từ thất bại', () {
    test('đâm tường → fail + frame bump', () {
      final pr = parseCommands('tien 9\n');
      final oc = simulate(_level('1'), pr.cmds);
      expect(oc.win, isFalse);
      expect(oc.failMsg, contains('đâm tường'));
      expect(oc.failStep, 1);
      expect(oc.frames.last.bump, isTrue);
      // Robot đứng yên khi đâm tường.
      expect(oc.frames.last.at, _level('1').start);
    });

    test('nhặt khi không có đồ → fail', () {
      final pr = parseCommands('nhat\n');
      final oc = simulate(_level('3'), pr.cmds);
      expect(oc.win, isFalse);
      expect(oc.failMsg, contains('không có đồ'));
    });

    test('dừng giữa đường (không tới cờ) → fail chỉ rõ vị trí', () {
      // Màn 3: nhặt đủ đồ nhưng dừng ở (8,1), chưa tới cờ (10,1).
      final pr = parseCommands('tien 3\nnhat\ntien 4\nnhat\n');
      final oc = simulate(_level('3'), pr.cmds);
      expect(oc.win, isFalse);
      expect(oc.failMsg, contains('cờ'));
    });

    test('thiếu món đồ → fail rõ ràng', () {
      final pr = parseCommands('tien 3\nnhat\ntien 4\ntien 2\n');
      final oc = simulate(_level('3'), pr.cmds);
      expect(oc.win, isFalse);
      expect(oc.failMsg, contains('chưa nhặt'));
    });
  });

  test('4 màn khai báo hợp lệ: đủ S, C, kích thước lưới đều nhau', () {
    for (final lv in kMazeLevels) {
      expect(lv.grid.first.length, lv.cols);
      for (final row in lv.grid) {
        expect(row.length, lv.cols, reason: 'màn ${lv.id} lệch cột');
      }
      // _find ném nếu thiếu S/C.
      expect(lv.start, isNotNull);
      expect(lv.goal, isNotNull);
    }
  });
}
