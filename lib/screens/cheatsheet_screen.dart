// SPDX-License-Identifier: MIT
/// Cheat sheet ViScript — tra cứu nhanh cú pháp ngay trong app.
/// Nội dung bám theo CHEAT-SHEET-ViScript.md của engine (bản rút gọn).
library;

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';

import '../core/l10n.dart';

class _Entry {
  const _Entry(this.title, this.titleEn, this.descVi, this.descEn, this.code);
  final String title;

  /// Tiêu đề tiếng Anh — trước đây chỉ có mô tả là song ngữ, tiêu đề
  /// vẫn tiếng Việt khi người dùng chọn English.
  final String titleEn;
  final String descVi;
  final String descEn;
  final String code;
}

const List<_Entry> _entries = [
  _Entry(
    'In ra màn hình',
    'Printing to the screen',
    'print nhận đúng 1 đối số; chuỗi có nội suy {{tên}}.',
    'print takes exactly 1 argument; strings interpolate {{name}}.',
    'print("Xin chào, ViScript!")\nlet ten = "Minh"\nprint("Chào {ten}!")',
  ),
  _Entry(
    'Biến: let và var',
    'Variables: let and var',
    'let không đổi được (như const), var đổi được. const bắt buộc ghi kiểu.',
    'let is immutable, var is mutable. const requires a type annotation.',
    'let ten = "Minh"\nvar tuoi = 17\ntuoi += 1\nconst MAX: int = 100',
  ),
  _Entry(
    'Hàm',
    'Functions',
    'Dòng cuối của hàm là giá trị trả về — không cần return.',
    'The last expression of a function is its return value.',
    'fn binh_phuong(x: int) -> int:\n    x * x\n\nprint(binh_phuong(7))',
  ),
  _Entry(
    'Rẽ nhánh',
    'Branching',
    'elif (không phải else if); if là biểu thức khi có else.',
    'elif (not else if); if is an expression when it has else.',
    'if diem >= 8:\n    print("Giỏi")\nelif diem >= 5:\n    print("Khá")\nelse:\n    print("Cần cố gắng")\n\nlet kq = if ok: "y" else: "n"',
  ),
  _Entry(
    'Vòng lặp',
    'Loops',
    'for i in 0..3 (không gồm cận trên), 0..=3 (gồm); while và loop đầy đủ.',
    'for i in 0..3 (exclusive), 0..=3 (inclusive); while and loop supported.',
    'for i in 0..3:\n    print(i)\n\nvar i = 0\nwhile i < 3:\n    i += 1\n\nloop:\n    break',
  ),
  _Entry(
    'match & pattern',
    'Pattern matching',
    'So mẫu gọn, không cần return.',
    'Concise pattern matching.',
    'match so:\n    0: print("không")\n    1 | 2: print("ít")\n    _: print("nhiều")',
  ),
  _Entry(
    'Danh sách & bản đồ',
    'Lists & maps',
    'Lập chỉ mục [0], duyệt for x in ds, for (k, v) in m.',
    'Index with [0], iterate with for x in list, for (k, v) in map.',
    'let ds = [1, 2, 3]\nprint(ds[0])\n\nlet m = {"a": 1, "b": 2}\nfor (k, v) in m:\n    print("{k} = {v}")',
  ),
  _Entry(
    'Đơn vị đo',
    'Measurement units',
    'Cộng sai loại đơn vị là lỗi biên dịch, không phải lỗi lúc chạy.',
    'Mixing unit kinds is a compile error, not a runtime error.',
    'print(1kb + 1kib)\nprint(2h + 30m)\n# 2h + 5kb ⇒ lỗi VSxxxx',
  ),
  _Entry(
    'Closure',
    'Closures',
    'Hàm nhiều dòng gán được vào biến.',
    'Multi-line functions can be assigned to variables.',
    'fn(x: int) -> int:\n    x + 1',
  ),
  _Entry(
    'Generic',
    'Generics',
    'Generic dùng [], không dùng <>.',
    'Generics use square brackets, not angle brackets.',
    'fn id[T](x: T) -> T:\n    x',
  ),
  _Entry(
    'Chương trình .vish (chế độ lệnh)',
    '.vish programs (command mode)',
    'Pipeline cấp tệp là chương trình; fn main chỉ khai cap.',
    'In .vish, file-level pipeline is the program; fn main declares caps.',
    '# chạy: vis run script.vish\nuse pkg.std.io\nprint("hello")',
  ),
  _Entry(
    'Quyền cap',
    'Cap permissions',
    'Khai quyền trước khi truy cập fs/net; --strict-caps siết chặt.',
    'Declare caps before fs/net access; --strict-caps enforces them.',
    'fn main(cap fs "data/", cap net "localhost:8000"):',
  ),
];

class CheatSheetScreen extends StatelessWidget {
  const CheatSheetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vi = AppLangScope.of(context) == AppLang.vietnamese;
    return Scaffold(
      appBar: AppBar(title: Text(t(context, S.cheatSheet))),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _entries.length,
        itemBuilder: (context, i) {
          final e = _entries[i];
          final cs = Theme.of(context).colorScheme;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          vi ? e.title : e.titleEn,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    vi ? e.descVi : e.descEn,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          e.code,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.5,
                            height: 1.5,
                            color: cs.onSurface,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: t(context, S.copyOutput),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.copy_outlined, size: 16),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: e.code));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(t(context, S.copied)),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
