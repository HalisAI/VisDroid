// SPDX-License-Identifier: MIT
/// Danh sách màn chơi của Mê cung ViScript — 10 màn / 3 thế giới.
///
/// Grid, hướng xuất phát và `par` (số bước chuẩn của route tối ưu) đều được
/// kiểm chứng bằng engine thật + simulator (`scripts/verify_levels_v2.py`,
/// `scripts/game-snippets/v2/man-*.vis` — route giải nằm trong JSON
/// `work/game-assets/levels-verified.json`). Đừng đổi grid/par nếu chưa chạy
/// lại toàn bộ chuỗi kiểm chứng.
library;

import 'maze.dart';

/// Một thế giới (nhóm màn) trong màn chọn.
class GameWorld {
  const GameWorld(this.id, this.name, this.subtitle);

  final int id;
  final String name;
  final String subtitle;
}

const List<GameWorld> kGameWorlds = [
  GameWorld(1, 'Hành lang khởi động', 'Gọi lệnh đơn giản, làm quen robot'),
  GameWorld(2, 'Sức mạnh vòng lặp', 'for, hàm riêng — code gọn gàng hơn'),
  GameWorld(3, 'Săn kho báu', 'Nhặt ngọc, mê cung thật sự'),
];

/// Màn cuối của thế giới 1 (theo thứ tự trong [kGameLevels] bên dưới).
final List<MazeLevel> kGameLevels = [
  // ── Thế giới 1 · Hành lang khởi động ──────────────────────────────
  MazeLevel(
    id: '1',
    world: 1,
    title: 'Bước đầu tiên',
    task: 'Robot nhìn sang phải, cờ cách 5 ô. Gọi di_tien(5) để robot chạy tới cờ.',
    startFacing: Facing.east,
    par: 5,
    grid: [
      '########',
      '#S....C#',
      '########',
    ],
    hint: 'Gõ di_tien(5) dưới phần khai báo hàm rồi bấm CHẠY. '
        'Đi thiếu thì chưa tới cờ, đi lố thì đâm tường — code cũng phải '
        'vừa vặn như thế đấy!',
    starterCode: '''
$helperCode

# Màn 1: đi thẳng 5 ô tới cờ. Viết lệnh của bạn dưới đây:

''',
  ),
  MazeLevel(
    id: '2',
    world: 1,
    title: 'Rẽ phải lần đầu',
    task: 'Đi hết hành lang rồi rẽ phải, xuống dưới tới cờ. '
        'Robot chỉ đi theo hướng nó đang nhìn!',
    startFacing: Facing.east,
    par: 7,
    grid: [
      '#######',
      '#S....#',
      '#####.#',
      '#####C#',
      '#######',
    ],
    hint: 'di_tien(4) → re_phai() → di_tien(2). '
        'Rẽ xong phải đi tiếp nữa mới tới cờ — mỗi lệnh chỉ là một bước trong kế hoạch.',
    starterCode: '''
$helperCode

# Màn 2: đi hết hành lang, rẽ phải, xuống tới cờ.

''',
  ),
  MazeLevel(
    id: '3',
    world: 1,
    title: 'Góc chữ U',
    task: 'Đi vòng chữ U: sang phải, xuống, rồi quay ngược sang trái tới cờ.',
    startFacing: Facing.east,
    par: 12,
    grid: [
      '#######',
      '#S....#',
      '#####.#',
      '#C....#',
      '#######',
    ],
    hint: 'di_tien(4) → re_phai() → di_tien(2) → re_phai() → di_tien(4). '
        'Đếm số ô từng khúc trước khi viết code — người lập trình giỏi tính trước!',
    starterCode: '''
$helperCode

# Màn 3: vòng chữ U quanh bức tường tới cờ.

''',
  ),
  MazeLevel(
    id: '4',
    world: 1,
    title: 'Đường zigzag',
    task: 'Đường gấp khúc hình chữ S — thay phiên nhau rẽ phải và rẽ trái '
        'qua 5 khúc đường.',
    startFacing: Facing.east,
    par: 12,
    grid: [
      '#########',
      '#S..#...#',
      '###...###',
      '#####..C#',
      '#########',
    ],
    hint: 'Mỗi khúc: di_tien(2), rồi re_phai() hoặc re_trai() đúng chỗ rẽ. '
        'Tổng 4 lần rẽ: phai → trai → phai → trai.',
    starterCode: '''
$helperCode

# Màn 4: zigzag — rẽ trái phải luân phiên.

''',
  ),

  // ── Thế giới 2 · Sức mạnh vòng lặp ────────────────────────────────
  MazeLevel(
    id: '5',
    world: 2,
    title: 'Hành lang dài',
    task: 'Hành lang 9 ô — thử viết vòng lặp for i in 0..9: di_tien(1) '
        'thay vì một lệnh di_tien(9). Cả hai đều được tính là hoàn thành!',
    startFacing: Facing.east,
    par: 9,
    grid: [
      '############',
      '#S........C#',
      '############',
    ],
    hint: 'Cách trực tiếp: di_tien(9)\n'
        'Cách có vòng lặp:\n'
        'for i in 0..9:\n'
        '    di_tien(1)\n'
        'Lưu ý: 0..9 chạy 9 lần — không tính số 9 (giống Python).',
    starterCode: '''
$helperCode

# Màn 5: hành lang dài — lặp cho gọn!

''',
  ),
  MazeLevel(
    id: '6',
    world: 2,
    title: 'Bậc thang',
    task: 'Bậc thang lặp lại 3 lần giống nhau. Tự viết hàm mot_bac() đi '
        'đúng 1 bậc (tiến 1 → rẽ phải → tiến 1 → rẽ trái) rồi lặp 3 lần.',
    startFacing: Facing.east,
    par: 14,
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

# Màn 6: bậc thang — tự viết hàm mot_bac() rồi lặp lại.

''',
  ),
  MazeLevel(
    id: '7',
    world: 2,
    title: 'Vòng quanh hồ',
    task: 'Giữa sân là hồ đá không thể xuyên qua. Robot xuất phát đang nhìn '
        'XUỐNG DƯỚI — đi vòng quanh hồ tới cờ ở góc bên kia.',
    startFacing: Facing.south,
    par: 11,
    grid: [
      '#########',
      '#S......#',
      '#.#####.#',
      '#.#####.#',
      '#.#####.#',
      '#......C#',
      '#########',
    ],
    hint: 'di_tien(4) → re_trai() → di_tien(6). '
        'Đọc kỹ đề trước khi code: robot BẮT ĐẦU nhìn xuống, không phải nhìn sang phải!',
    starterCode: '''
$helperCode

# Màn 7: vòng quanh hồ — xuất phát đang nhìn XUỐNG DƯỚI.

''',
  ),

  // ── Thế giới 3 · Săn kho báu ──────────────────────────────────────
  MazeLevel(
    id: '8',
    world: 3,
    title: 'Hai viên ngọc',
    task: 'Nhặt ĐỦ 2 viên ngọc trên hành lang rồi dừng NGAY trên ô cờ. '
        'Nhặt = đang đứng đúng trên ô ngọc gọi nhat_do().',
    startFacing: Facing.east,
    par: 11,
    grid: [
      '############',
      '#S..X...X.C#',
      '############',
    ],
    hint: 'di_tien(3) → nhat_do() → di_tien(4) → nhat_do() → di_tien(2). '
        'Đi lố qua ngọc là bỏ lỡ kho báu — phải dừng đúng ô!',
    starterCode: '''
$helperCode

# Màn 8: nhặt đủ 2 viên ngọc rồi tới cờ.

''',
  ),
  MazeLevel(
    id: '9',
    world: 3,
    title: 'Ngọc trong hốc',
    task: 'Hai viên ngọc nằm lệch nhau: một ở hàng trên, một dưới hốc bên '
        'trái. Xuống hốc xong phải rẽ PHẢI để quay mũi về hướng tây!',
    startFacing: Facing.east,
    par: 15,
    grid: [
      '########',
      '#S...X.#',
      '######.#',
      '#.C.X..#',
      '########',
    ],
    hint: 'di_tien(4) → nhat_do() → di_tien(1) → re_phai() → di_tien(2) → '
        're_phai() → di_tien(2) → nhat_do() → di_tien(2). '
        'Hai lần re_phai() liên tiếp để quay từ hướng đông sang hướng tây.',
    starterCode: '''
$helperCode

# Màn 9: ngọc trong hốc — rẽ phai hai lần liên tiếp!

''',
  ),
  MazeLevel(
    id: '10',
    world: 3,
    title: 'Kho báu cuối',
    task: 'Màn cuối! Mê cung snake thật sự: 2 viên ngọc rải rác trên đường. '
        'Dùng mọi thứ đã học — tuần tự, rẽ, vòng lặp, hàm — để trùm màn cuối.',
    startFacing: Facing.east,
    par: 24,
    grid: [
      '###########',
      '#S.X....###',
      '#######.###',
      '####X...###',
      '####.######',
      '####.....C#',
      '###########',
    ],
    hint: 'Chia nhỏ từng đoạn như kế hoạch: tới ngọc 1 → nhặt → hết hàng → '
        'xuống → tới ngọc 2 → nhặt → xuống → hết hành lang tới cờ. '
        'Route chuẩn: 24 bước.',
    starterCode: '''
$helperCode

# Màn 10: mê cung cuối — dùng mọi thứ đã học!

''',
  ),
];

/// Lấy màn theo id (đọc từ file tiến độ).
MazeLevel levelById(String id) =>
    kGameLevels.firstWhere((l) => l.id == id, orElse: () => kGameLevels.first);
