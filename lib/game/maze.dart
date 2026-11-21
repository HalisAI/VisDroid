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

/// Vector hướng và phép quay — public để màn hình game vẽ mũi chỉ hướng.
extension FacingDelta on Facing {
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
    required this.world,
    required this.title,
    required this.task,
    required this.grid,
    required this.startFacing,
    required this.starterCode,
    required this.hint,
    required this.par,
  });

  final String id;
  final int world; // thế giới (nhóm màn trong màn chọn kiểu game).
  final String title;
  final String task;
  final List<String> grid;
  final Facing startFacing;
  final String starterCode;
  final String hint;

  /// Số bước chuẩn (di chuyển + quay + nhặt) của route tối ưu đã kiểm chứng
  /// bằng engine thật. Chấm sao: ≤ par = 3★, ≤ par+4 = 2★, còn lại 1★.
  final int par;

  int get cols => grid.first.length;
  int get rows => grid.length;

  /// Ngoài lưới hoặc gặp `#` đều là tường. Soi độ dài TỪNG hàng: lưới lệch
  /// hàng (hàng ngắn hơn hàng đầu) phải trả về tường, không RangeError index.
  bool isWall(Cell c) {
    if (c.y < 0 || c.y >= rows || c.x < 0) return true;
    final row = grid[c.y];
    if (c.x >= row.length) return true;
    return row[c.x] == '#';
  }

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
  const GameCmd(this.kind, this.n);

  final CmdKind kind;
  final int n; // số bước với `tien`, không dùng cho lệnh khác.
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
/// qua; dòng khác ⇒ lỗi kèm vị trí để người chơi sửa. Giới hạn 500 lệnh VÀ 500
/// bước đi (một lệnh `tien` sinh tới 100 bước) để hoạt ảnh không chạy vô hạn.
ParseResult parseCommands(String stdout) {
  final cmds = <GameCmd>[];
  var steps = 0; // tổng bước đi của mọi lệnh tien — cap theo BƯỚC.
  final lines = stdout.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final ln = i + 1;
    final s = lines[i].trim();
    if (s.isEmpty || s.startsWith('#')) continue;
    final tenMatch = RegExp(r'^tien\s+(\d+)$').firstMatch(s);
    if (tenMatch != null) {
      // tryParse chứ không parse — số quá lớn (> 2^63) làm int.parse ném
      // FormatException ngoài tầm bắt của màn chơi; coi như vi phạm giới hạn.
      final n = int.tryParse(tenMatch.group(1)!);
      if (n == null || n > 100) {
        return ParseResult(const [], 'tien tối đa 100 bước mỗi lệnh '
            '(nhận được ${tenMatch.group(1)!})', ln);
      }
      steps += n;
      cmds.add(GameCmd(CmdKind.forward, n));
      continue;
    }
    switch (s) {
      case 'trai':
        cmds.add(GameCmd(CmdKind.turnLeft, 0));
        continue;
      case 'phai':
        cmds.add(GameCmd(CmdKind.turnRight, 0));
        continue;
      case 'nhat':
        cmds.add(GameCmd(CmdKind.pickup, 0));
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
  // Hoạt ảnh chạy theo BƯỚC (mỗi ô đi/quay/nhặt 1 frame), không theo số lệnh —
  // `tien 100` × 5 đã là 500 frame dù chỉ 5 lệnh, nên phải cap cả tổng bước.
  if (steps > 500) {
    return ParseResult(const [], 'tổng số bước đi quá 500 (>500) — script có vòng lặp vô hạn?', 0);
  }
  if (cmds.isEmpty) {
    return ParseResult(const [], 'script không in ra lệnh nào — hãy gọi các hàm ra lệnh', 0);
  }
  return ParseResult(cmds, null, null);
}

/// Một khung hình hoạt ảnh: vị trí + hướng robot, món đồ còn lại, và cờ
/// `bump` khi robot đâm tường (đứng yên ở ô hiện tại).
///
/// [q] là số lần quay 90° cộng dồn (phải +1, trái −1) — dùng để nội suy góc
/// quay mượt theo đúng chiều rẽ, không bị "đi đường tắt" qua π.
class SimFrame {
  const SimFrame({
    required this.at,
    required this.facing,
    required this.picked,
    this.q = 0,
    this.bump = false,
  });

  final Cell at;
  final Facing facing;
  final Set<Cell> picked;
  final int q;
  final bool bump;
}

/// Kết quả mô phỏng cả hàng lệnh.
class SimOutcome {
  const SimOutcome({
    required this.win,
    required this.frames,
    this.failMsg,
    this.failStep,
  });

  final bool win;
  final List<SimFrame> frames; // frames[0] = trạng thái ban đầu.
  final String? failMsg; // khác null khi thua.
  final int? failStep; // số thứ tự lệnh gây thua (1-based).
}

/// Chạy mô phỏng hàng lệnh trên bản đồ — không đụng UI.
SimOutcome simulate(MazeLevel level, List<GameCmd> cmds) {
  var at = level.start;
  var facing = level.startFacing;
  var q = 0; // quay cộng dồn cho tween góc mượt.
  final picked = <Cell>{};
  final frames = <SimFrame>[
    SimFrame(at: at, facing: facing, picked: Set.of(picked)),
  ];

  for (var i = 0; i < cmds.length; i++) {
    final cmd = cmds[i];
    switch (cmd.kind) {
      case CmdKind.turnLeft:
        facing = facing.turnedLeft;
        q -= 1;
        frames.add(SimFrame(at: at, facing: facing, picked: Set.of(picked), q: q));
        break;
      case CmdKind.turnRight:
        facing = facing.turnedRight;
        q += 1;
        frames.add(SimFrame(at: at, facing: facing, picked: Set.of(picked), q: q));
        break;
      case CmdKind.pickup:
        if (level.items.contains(at) && !picked.contains(at)) {
          picked.add(at);
          frames.add(SimFrame(at: at, facing: facing, picked: Set.of(picked), q: q));
        } else {
          frames.add(SimFrame(at: at, facing: facing, picked: Set.of(picked), q: q));
          return SimOutcome(
            win: false,
            frames: frames,
            failMsg: "không có đồ để nhặt ở ô $at (lệnh thứ ${i + 1})",
            failStep: i + 1,
          );
        }
        break;
      case CmdKind.forward:
        for (var step = 0; step < cmd.n; step++) {
          final next = at + facing.delta;
          if (level.isWall(next)) {
            frames.add(SimFrame(
              at: at,
              facing: facing,
              picked: Set.of(picked),
              q: q,
              bump: true,
            ));
            return SimOutcome(
              win: false,
              frames: frames,
              failMsg: 'đâm tường ở ô $next (lệnh thứ ${i + 1})',
              failStep: i + 1,
            );
          }
          at = next;
          frames.add(SimFrame(at: at, facing: facing, picked: Set.of(picked), q: q));
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
