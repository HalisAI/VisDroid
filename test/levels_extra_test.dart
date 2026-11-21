// SPDX-License-Identifier: MIT
/// Kiểm chứng bất biến toàn bộ 15 màn + route tối ưu của 5 màn mới (thế giới 4).
///
/// Route màn 11–15 sinh ra từ BFS tối ưu trong `scripts/design_levels_v4.py`
/// và mô phỏng lại bằng `simulate()` thật ở đây — par sai một bước là test đỏ.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:visdroid/game/levels.dart';
import 'package:visdroid/game/maze.dart';

/// Route giải tối ưu (stdout) cho màn 11–15 — từ scripts/design_levels_v4.py.
const _routes = {
  '11': 'tien 3\nnhat\ntien 1\nphai\ntien 2\ntrai\ntien 2\n',
  '12':
      'tien 2\nnhat\ntien 3\nnhat\ntien 3\ntrai\ntrai\nnhat\ntien 1\ntrai\ntien 2\nphai\ntien 2\n',
  '13':
      'tien 8\ntrai\ntrai\nnhat\ntien 4\nphai\ntien 2\ntrai\ntrai\nnhat\ntien 4\n',
  '14':
      'tien 6\nphai\ntien 2\nphai\ntien 6\ntrai\ntrai\nnhat\ntien 1\nphai\ntien 2\nphai\ntien 1\n',
  '15':
      'tien 4\nnhat\ntien 6\ntrai\ntrai\nnhat\ntien 5\ntrai\ntien 2\nphai\ntien 3\ntrai\ntrai\nnhat\ntien 5\n',
};

MazeLevel _level(String id) => kGameLevels.firstWhere((l) => l.id == id);

void main() {
  group('bất biến toàn bộ kGameLevels', () {
    test('mỗi màn có start ≠ cờ, start/cờ/đồ không nằm trong tường', () {
      for (final lv in kGameLevels) {
        expect(lv.start, isNot(equals(lv.goal)),
            reason: 'màn ${lv.id}: S trùng C');
        expect(lv.isWall(lv.start), isFalse,
            reason: 'màn ${lv.id}: S trong tường');
        expect(lv.isWall(lv.goal), isFalse,
            reason: 'màn ${lv.id}: C trong tường');
        for (final it in lv.items) {
          expect(lv.isWall(it), isFalse,
              reason: 'màn ${lv.id}: đồ trong tường $it');
        }
        expect(lv.items, isNot(contains(lv.start)),
            reason: 'màn ${lv.id}: đồ đè S');
        expect(lv.items, isNot(contains(lv.goal)),
            reason: 'màn ${lv.id}: đồ đè C');
      }
    });

    test('grid chữ nhật + tường bao kín 4 mép', () {
      for (final lv in kGameLevels) {
        final w = lv.cols;
        for (final row in lv.grid) {
          expect(row.length, w, reason: 'màn ${lv.id}: hàng lệch cột');
          expect(row.startsWith('#') && row.endsWith('#'), isTrue,
              reason: 'màn ${lv.id}: thiếu tường mép trái/phải');
        }
        expect(lv.grid.first, '#' * w,
            reason: 'màn ${lv.id}: thiếu tường mép trên');
        expect(lv.grid.last, '#' * w,
            reason: 'màn ${lv.id}: thiếu tường mép dưới');
      }
    });

    test('15 màn / 4 thế giới, id duy nhất, không thế giới nào rỗng', () {
      expect(kGameLevels, hasLength(15));
      expect(kGameWorlds, hasLength(4));
      expect(kGameLevels.map((l) => l.id).toSet(), hasLength(15));
      final worldIds = kGameWorlds.map((w) => w.id).toSet();
      for (final lv in kGameLevels) {
        expect(worldIds, contains(lv.world),
            reason: 'màn ${lv.id}: world ${lv.world} không có trong kGameWorlds');
      }
      for (final w in kGameWorlds) {
        expect(kGameLevels.any((l) => l.world == w.id), isTrue,
            reason: 'thế giới ${w.id} rỗng');
      }
    });

    test('par hợp lệ (> 0) trên mọi màn', () {
      for (final lv in kGameLevels) {
        expect(lv.par, greaterThan(0), reason: 'màn ${lv.id}: par = 0');
      }
    });
  });

  group('thế giới 4 — route tối ưu đạt đúng par', () {
    for (final entry in _routes.entries) {
      test('màn ${entry.key} giải bằng route chuẩn → thắng, đúng par', () {
        final lv = _level(entry.key);
        expect(lv.world, 4);
        final pr = parseCommands(entry.value);
        expect(pr.ok, isTrue, reason: pr.error);
        final oc = simulate(lv, pr.cmds);
        expect(oc.win, isTrue, reason: 'màn ${entry.key} thua: ${oc.failMsg}');
        expect(oc.frames.length - 1, lv.par,
            reason: 'màn ${entry.key}: route tối ưu tiêu tốn '
                '${oc.frames.length - 1} bước ≠ par ${lv.par}');
      });
    }
  });
}
