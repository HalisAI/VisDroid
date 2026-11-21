// SPDX-License-Identifier: MIT
/// Danh sách màn chơi của Mê cung ViScript — 15 màn / 4 thế giới.
///
/// Thế giới 1–3: grid, hướng xuất phát và `par` (số bước chuẩn của route
/// tối ưu) đã kiểm chứng bằng engine thật + simulator (`scripts/verify_levels_v2.py`,
/// route giải trong JSON `work/game-assets/levels-verified.json`).
/// Thế giới 4 (màn 11–15): par là BFS tối ưu tuyệt đối, kiểm chứng bằng
/// `scripts/design_levels_v4.py` (BFS + mini-sim khớp semantics `simulate()`).
/// Lưu ý: par màn 6 là 14 (bậc thang rẽ đủ mỗi bậc — par sư phạm, route dạy
/// học trong hint phải đạt 3★) dù đường đi tối ưu thuần túy chỉ 12 bước.
/// Đừng đổi grid/par nếu chưa chạy lại chuỗi kiểm chứng.
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
  GameWorld(4, 'Tổng kết hành trình', 'Cửa bẫy, ngã tư, hai tầng — dùng mọi kỹ năng'),
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
    title: 'Rừng ngọc snake',
    task: 'Mê cung snake thật sự: 2 viên ngọc rải rác trên đường. '
        'Đây là màn khó nhất của thế giới Săn kho báu — chia nhỏ từng đoạn!',
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

  // ── Thế giới 4 · Tổng kết hành trình ───────────────────────────────
  // Màn 11–15: par = BFS tối ưu tuyệt đối (scripts/design_levels_v4.py,
  // route mô phỏng lại bằng simulate() trong test/levels_extra_test.dart).
  MazeLevel(
    id: '11',
    world: 4,
    title: 'Bẫy ngọc',
    task: 'Ngọc nằm giữa đường — nhặt đúng chỗ rồi rẽ xuống ngay. '
        'Đi tiếp về phía đông là ổ cụt: nhìn trước đường đi, đừng lọt bẫy!',
    startFacing: Facing.east,
    par: 11,
    grid: [
      '#########',
      '#S..X...#',
      '###.#.###',
      '#......C#',
      '#########',
    ],
    hint: 'Route tối ưu: di_tien(3) → nhat_do() → di_tien(1) → re_phai() → '
        'di_tien(2) → re_trai() → di_tien(2). '
        'Nhặt ngọc ở giữa hành lang rồi rẽ xuống — ổ bên phải là bẫy!',
    starterCode: '''
$helperCode

# Màn 11: Bẫy ngọc — nhìn trước đường đi!

''',
  ),
  MazeLevel(
    id: '12',
    world: 4,
    title: 'Săn ba ngọc',
    task: 'Ba viên ngọc rải trên hành lang trên, cờ ở hành lang dưới. '
        'Sau khi quay đầu nhặt viên cuối, lùi đúng 1 ô để vào hố xuống!',
    startFacing: Facing.east,
    par: 20,
    grid: [
      '###########',
      '#S.X..X..X#',
      '#####.##.##',
      '#.....C...#',
      '###########',
    ],
    hint: 'Route tối ưu: di_tien(2) → nhat_do() → di_tien(3) → nhat_do() → '
        'di_tien(3) → re_trai() → re_trai() → nhat_do() → di_tien(1) → '
        're_trai() → di_tien(2) → re_phai() → di_tien(2). '
        'Hai lần re_trai() liên tiếp = quay ngược 180°!',
    starterCode: '''
$helperCode

# Màn 12: Săn ba ngọc — kế hoạch trước, code sau!

''',
  ),
  MazeLevel(
    id: '13',
    world: 4,
    title: 'Ngã tư đảo',
    task: 'Hai viên ngọc ở đầu hai nhánh của ngã tư. '
        'Thứ tự ghé hai nhánh quyết định tổng số bước — vẽ route trên giấy trước!',
    startFacing: Facing.east,
    par: 25,
    grid: [
      '###########',
      '#####X#####',
      '#####.#####',
      '#S.......X#',
      '#####.#####',
      '#####C#####',
      '###########',
    ],
    hint: 'Route tối ưu: di_tien(8) → re_trai() → re_trai() → nhat_do() → '
        'di_tien(4) → re_phai() → di_tien(2) → re_trai() → re_trai() → '
        'nhat_do() → di_tien(4). '
        'Ghé nhánh đông trước, nhánh bắc sau — thử đảo thứ tự để thấy vì sao tốn thêm bước!',
    starterCode: '''
$helperCode

# Màn 13: Ngã tư đảo — thứ tự ghé nhánh quan trọng!

''',
  ),
  MazeLevel(
    id: '14',
    world: 4,
    title: 'Hai tầng quanh hồ',
    task: 'Đường hai tầng chữ S vòng quanh hồ đá: xuống tầng dưới qua khe hở '
        'bên phải, viên ngọc nằm ở đầu phía tây tầng giữa.',
    startFacing: Facing.east,
    par: 25,
    grid: [
      '##########',
      '#S.......#',
      '#######..#',
      '#X.......#',
      '##.#######',
      '#C.......#',
      '##########',
    ],
    hint: 'Route tối ưu: di_tien(6) → re_phai() → di_tien(2) → re_phai() → '
        'di_tien(6) → re_trai() → re_trai() → nhat_do() → di_tien(1) → '
        're_phai() → di_tien(2) → re_phai() → di_tien(1). '
        'Ngọc ở góc tây tầng giữa — nhặt xong lùi 1 ô rồi mới xuống!',
    starterCode: '''
$helperCode

# Màn 14: Hai tầng quanh hồ — snake kép quanh hồ đá!

''',
  ),
  MazeLevel(
    id: '15',
    world: 4,
    title: 'Kho báu cuối',
    task: 'Màn cuối của hành trình! Ba viên ngọc trên hai tầng mê cung — '
        'dùng mọi kỹ năng đã học: đếm ô, quay 180°, chọn lộ trình ngắn nhất.',
    startFacing: Facing.east,
    par: 34,
    grid: [
      '#############',
      '#S...X.....X#',
      '######.######',
      '#..X....C...#',
      '#############',
    ],
    hint: 'Route tối ưu: di_tien(4) → nhat_do() → di_tien(6) → re_trai() → '
        're_trai() → nhat_do() → di_tien(5) → re_trai() → di_tien(2) → '
        're_phai() → di_tien(3) → re_trai() → re_trai() → nhat_do() → '
        'di_tien(5). '
        'Chia nhỏ từng đoạn: ngọc 1 → ngọc 2 quay đầu → xuống tầng dưới → ngọc 3 → cờ.',
    starterCode: '''
$helperCode

# Màn 15: Kho báu cuối — màn trùm của hành trình!

''',
  ),
];

/// Lấy màn theo id (đọc từ file tiến độ).
MazeLevel levelById(String id) =>
    kGameLevels.firstWhere((l) => l.id == id, orElse: () => kGameLevels.first);
