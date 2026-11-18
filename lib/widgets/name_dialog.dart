// SPDX-License-Identifier: MIT
/// Hộp thoại nhập tên tệp — dùng chung cho Tệp và màn soạn thảo.
library;

import 'package:material_ui/material_ui.dart';

import '../core/l10n.dart';

/// Hỏi tên tệp mới / tên đổi. Trả `null` nếu người dùng huỷ.
Future<String?> askFileName(
  BuildContext context, {
  required String title,
  String hint = '',
  String? initial,
}) {
  final ctrl = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t(ctx, S.cancel)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: Text(t(ctx, S.confirm)),
        ),
      ],
    ),
  );
}
