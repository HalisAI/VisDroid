// SPDX-License-Identifier: MIT
/// Mê cung ViScript — game dạy lập trình kiểu Code Combat, bản một người chơi.
///
/// Mô hình (theo issue #1): người chơi viết script ViScript in các lệnh ra
/// stdout (`tien 3`, `trai`, `phai`, `nhat`), bấm Chạy — engine chạy trong
/// sandbox như mọi script khác, app phân tích stdout thành hàng lệnh rồi cho
/// robot thực hiện lần lượt kèm hoạt ảnh. Không cần sửa engine.
///
/// Tệp này thuần Dart (không phụ thuộc Flutter) để test được bằng `dart test`.
library;

/// Hướng robot đang nhìn.
enum Facing { east, south, west, north }

/// Điểm lưới (x cột, y hàng) — gốc trên trái.
class Cell {
  const Cell(this.x, this.y);

  final int x;
  final int y;

  Cell operator +(Cell o) => Cell(x + o.x, y + o.y);

  @override
  bool operator ==(Object other) => other is Cell && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x,$y)';
}

extension _FacingDelta on Facing {
  Cell get delta => switch (this) {
        Facing.east => const Cell(1, 0),
        Facing.south => const Cell(0, 1),
        Facing.west => const Cell(-1, 0),
        Facing.north => const Cell(0, -1),
      };

  Facing get turnedLeft => switch (this) {
        Facing.east => Facing.north,
        Facing.north => Facing.west,
        Facing.west => Facing.south,
        Facing.south => Facing.east,
      };

  Facing get turnedRight => switch (this) {
        Facing.east => Facing.south,
        Facing.south => Facing.west,
        Facing.west => Facing.north,
        Facing.north => Facing.east,
      };
}

/// Một màn chơi: lưới ký tự (`#` tường, `.` sàn, `S` xuất phát, `C` cờ,
/// `X` món đồ), hướng ban đầu, code khởi đầu và gợi ý.
class MazeLevel {
  const MazeLevel({
    required this.id,
    required this.title,
    required this.task,
    required this.grid,
    required this.startFacing,
    required this.starterCode,
    required this.hint,
  });

  final String id;
  final String title;
  final String task;
  final List<String> grid;
  final Facing startFacing;
  final String starterCode;
  final String hint;

  int get cols => grid.first.length;
  int get rows => grid.length;

  bool isWall(Cell c) =>
      c.y < 0 || c.y >= rows || c.x < 0 || c.x >= cols || grid[c.y][c.x] == '#';

  Cell get start => _find('S');
  Cell get goal => _find('C');
  List<Cell> get items => [
        for (var y = 0; y < rows; y++)
          for (var x = 0; x < grid[y].length; x++)
            if (grid[y][x] == 'X') Cell(x, y),
      ];

  Cell _find(String ch) {
    for (var y = 0; y < rows; y++) {
      final x = grid[y].indexOf(ch);
      if (x >= 0) return Cell(x, y);
    }
    throw StateError('màn $id thiếu ô $ch');
  }
}

/// Lệnh robot đọc được từ stdout.
enum CmdKind { forward, turnLeft, turnRight, pickup }

class GameCmd {
  const GameCmd(this.kind, this.n, this.stdoutLine);

  final CmdKind kind;
  final int n; // số bước với `tien`, không dùng cho lệnh khác.
  final int stdoutLine; // dòng trong stdout (1-based) — báo lỗi dễ hiểu.
}

/// Kết quả phân tích stdout thành hàng lệnh.
class ParseResult {
  const ParseResult(this.cmds, this.error, this.errorLine);

  final List<GameCmd> cmds;
  final String? error;
  final int? errorLine; // dòng stdout gây lỗi (1-based).

  bool get ok => error == null;
}

/// Phân tích stdout của script thành hàng lệnh.
///
/// Quy tắc: mỗi dòng non-trống phải là một lệnh (`tien <n>` với 0 ≤ n ≤ 100,
/// `trai`, `phai`, `nhat`); dòng trống hoặc bắt đầu bằng `#` (in debug) được bỏ
/// qua; dòng khác ⇒ lỗi kèm vị trí để người chơi sửa. Giới hạn 500 lệnh để
/// hoạt ảnh không chạy vô hạn.
ParseResult parseCommands(String stdout) {
  final cmds = <GameCmd>[];
  final lines = stdout.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final ln = i + 1;
    final s = lines[i].trim();
    if (s.isEmpty || s.startsWith('#')) continue;
    final tenMatch = RegExp(r'^tien\s+(\d+)$').firstMatch(s);
    if (tenMatch != null) {
      final n = int.parse(tenMatch.group(1)!);
      if (n > 100) {
        return ParseResult(const [], 'tien tối đa 100 bước mỗi lệnh (nhận được $n)', ln);
      }
      cmds.add(GameCmd(CmdKind.forward, n, ln));
      continue;
    }
    switch (s) {
      case 'trai':
        cmds.add(GameCmd(CmdKind.turnLeft, 0, ln));
        continue;
      case 'phai':
        cmds.add(GameCmd(CmdKind.turnRight, 0, ln));
        continue;
      case 'nhat':
        cmds.add(GameCmd(CmdKind.pickup, 0, ln));
        continue;
    }
    return ParseResult(
      const [],
      "không hiểu dòng: '$s' — chỉ nhận: tien <số bước>, trai, phai, nhat",
      ln,
    );
  }
  if (cmds.length > 500) {
    return ParseResult(const [], 'quá 500 lệnh (>500) — script có vòng lặp vô hạn?', 0);
  }
  if (cmds.isEmpty) {
    return ParseResult(const [], 'script không in ra lệnh nào — hãy gọi các hàm ra lệnh', 0);
  }
  return ParseResult(cmds, null, null);
}

/// Một khung hình hoạt ảnh: vị trí + hướng robot, món đồ còn lại, và cờ
/// `bump` khi robot đâm tường (đứng yên ở ô hiện tại).
class SimFrame {
  const SimFrame({
    required this.at,
    required this.facing,
    required this.picked,
    this.bump = false,
  });

  final Cell at;
  final Facing facing;
  final Set<Cell> picked;
  final bool bump;
}

/// Kết quả mô phỏng cả hàng lệnh.
class SimOutcome {
  const SimOutcome({
    required this.win,
    required this.frames,
    required this.stepCount,
    this.failMsg,
    this.failStep,
  });

  final bool win;
  final List<SimFrame> frames; // frames[0] = trạng thái ban đầu.
  final int stepCount; // tổng lệnh.
  final String? failMsg; // khác null khi thua.
  final int? failStep; // số thứ tự lệnh gây thua (1-based).

  /// Chạy tới đây thì dừng hoạt ảnh (chỉ số frame cuối).
  int get lastFrame => failMsg == null ? frames.length - 1 : failFrame;

  int get failFrame {
    // frames: mỗi lệnh sinh 1..n frame; fail frame là frame cuối.
    return frames.length - 1;
  }
}

/// Chạy mô phỏng hàng lệnh trên bản đồ — không đụng UI.
SimOutcome simulate(MazeLevel level, List<GameCmd> cmds) {
  var at = level.start;
  var facing = level.startFacing;
  final picked = <Cell>{};
  final frames = <SimFrame>[SimFrame(at: at, facing: facing, picked: Set.of(picked))];

  for (var i = 0; i < cmds.length; i++) {
    final cmd = cmds[i];
    switch (cmd.kind) {
      case CmdKind.turnLeft:
        facing = facing.turnedLeft;
        frames.add(SimFrame(at: at, facing: facing, picked: Set.of(picked)));
        break;
      case CmdKind.turnRight:
        facing = facing.turnedRight;
        frames.add(SimFrame(at: at, facing: facing, picked: Set.of(picked)));
        break;
      case CmdKind.pickup:
        if (level.items.contains(at) && !picked.contains(at)) {
          picked.add(at);
          frames.add(SimFrame(at: at, facing: facing, picked: Set.of(picked)));
        } else {
          frames.add(SimFrame(at: at, facing: facing, picked: Set.of(picked)));
          return SimOutcome(
            win: false,
            frames: frames,
            stepCount: cmds.length,
            failMsg: "không có đồ để nhặt ở ô $at (lệnh thứ ${i + 1})",
            failStep: i + 1,
          );
        }
        break;
      case CmdKind.forward:
        for (var step = 0; step < cmd.n; step++) {
          final next = at + facing.delta;
          if (level.isWall(next)) {
            frames.add(SimFrame(at: at, facing: facing, picked: Set.of(picked), bump: true));
            return SimOutcome(
              win: false,
              frames: frames,
              stepCount: cmds.length,
              failMsg: 'đâm tường ở ô $next (lệnh thứ ${i + 1})',
              failStep: i + 1,
            );
          }
          at = next;
          frames.add(SimFrame(at: at, facing: facing, picked: Set.of(picked)));
        }
        break;
    }
  }

  final win = at == level.goal && picked.length == level.items.length;
  String? failMsg;
  var failStep = 0;
  if (!win) {
    if (at != level.goal) {
      failMsg = 'robot kết thúc ở ô $at nhưng cờ ở ô ${level.goal} '
          '— route phải kết thúc NGAY trên ô cờ';
    } else {
      failMsg = 'còn ${level.items.length - picked.length} món đồ chưa nhặt';
    }
    failStep = cmds.length;
  }
  return SimOutcome(
    win: win,
    frames: frames,
    stepCount: cmds.length,
    failMsg: failMsg,
    failStep: failStep,
  );
}

/// Code khởi đầu dùng chung — hàm ra lệnh cho robot (cú pháp đã kiểm chứng
/// bằng engine thật, xem `scripts/game-snippets/`).
const String helperCode = '''
# Các hàm ra lệnh cho robot — có sẵn, đừng xoá!
fn di_tien(n: int):
    print("tien {n}")

fn re_trai():
    print("trai")

fn re_phai():
    print("phai")

fn nhat_do():
    print("nhat")
''';

/// Bốn màn khởi đầu: tuần tự → rẽ/vòng lặp → nhặt đồ → tự viết hàm.
/// (dùng `final` vì starterCode nội suy [helperCode])
final List<MazeLevel> kMazeLevels = [
  MazeLevel(
    id: '1',
    title: 'Lệnh đầu tiên',
    task: 'Robot nhìn sang phải, cờ cách 5 ô. Gọi di_tien(5) để tới cờ.',
    startFacing: Facing.east,
    grid: [
      '########',
      '#S....C#',
      '########',
    ],
    hint: 'Gõ di_tien(5) dưới phần khai báo hàm rồi bấm Chạy. '
        'Thử đổi số để xem robot đi xa hơn — đi quá cờ coi như chưa xong!',
    starterCode: '''
$helperCode

# Màn 1: đi thẳng tới cờ. Viết lệnh ở dưới đây:

''',
  ),
  MazeLevel(
    id: '2',
    title: 'Rẽ và vòng lặp',
    task: 'Đi hết hành lang rồi rẽ phải, xuống dưới tới cờ. '
        'Thử dùng vòng lặp for i in 0..3: di_tien(1).',
    startFacing: Facing.east,
    grid: [
      '#######',
      '#S....#',
      '#####.#',
      '#####.#',
      '#####C#',
      '#######',
    ],
    hint: 'Cách trực tiếp: di_tien(4) → re_phai() → di_tien(3).\n'
        'Cách có vòng lặp: di_tien(4), re_phai(), rồi for i in 0..3: di_tien(1).',
    starterCode: '''
$helperCode

# Màn 2: đi hết hành lang, rẽ phải, xuống tới cờ.

''',
  ),
  MazeLevel(
    id: '3',
    title: 'Nhặt đồ trên đường',
    task: 'Nhặt ĐỦ 2 món 🎁 trên hành lang rồi dừng ở cờ. '
        'Nhặt = robot đang đứng NGAY trên ô món đồ khi gọi nhat_do().',
    startFacing: Facing.east,
    grid: [
      '############',
      '#S..X...X.C#',
      '############',
    ],
    hint: 'di_tien(3) → nhat_do() → di_tien(4) → nhat_do() → di_tien(2). '
        'Lưu ý: phải kết thúc NGAY trên ô cờ, không đi lố!',
    starterCode: '''
$helperCode

# Màn 3: nhặt đủ 2 món 🎁 rồi tới cờ.

''',
  ),
  MazeLevel(
    id: '4',
    title: 'Viết hàm của bạn',
    task: 'Bậc thang lặp lại 3 lần giống nhau. Tự viết hàm mot_bac() đi đúng '
        '1 bậc (tiến 1 → rẽ phải → tiến 1 → rẽ trái) rồi dùng vòng lặp gọi 3 lần.',
    startFacing: Facing.east,
    grid: [
      '##########',
      '#S.......#',
      '##..######',
      '###..#####',
      '####..C###',
      '##########',
    ],
    hint: 'fn mot_bac():\n'
        '    di_tien(1)\n'
        '    re_phai()\n'
        '    di_tien(1)\n'
        '    re_trai()\n'
        '\n'
        'for i in 0..3:\n'
        '    mot_bac()\n'
        'di_tien(2)',
    starterCode: '''
$helperCode

# Màn 4: bậc thang! Tự viết hàm mot_bac() đi đúng 1 bậc rồi lặp 3 lần.

''',
  ),
];
