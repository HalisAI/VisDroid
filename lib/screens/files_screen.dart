// SPDX-License-Identifier: MIT
/// Màn hình tệp: danh sách tệp dự án, tạo/mở/đổi tên/xoá, ví dụ mẫu đi kèm.
library;

import 'package:material_ui/material_ui.dart';

import '../core/l10n.dart';
import '../core/project.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({
    super.key,
    required this.project,
    required this.onOpenFile,
    required this.currentFile,
  });

  final VisProject project;
  final ValueChanged<String> onOpenFile;
  final String? currentFile;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  @override
  Widget build(BuildContext context) {
    final files = widget.project.listFiles();
    return Scaffold(
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: files.isEmpty
                ? Center(
                    child: Text(
                      t(context, S.welcomeBody),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    itemCount: files.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final f = files[i];
                      final name = f.path.split('/').last;
                      final stat = f.statSync();
                      final size = stat.size;
                      final modified = stat.modified;
                      final isCurrent = name == widget.currentFile;
                      return ListTile(
                        leading: Icon(
                          Icons.description_outlined,
                          color: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                        ),
                        title: Text(name),
                        subtitle: Text(
                          '$size B · '
                          '${modified.day}/${modified.month}/${modified.year}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'rename') await _rename(name);
                            if (v == 'delete') await _delete(name);
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text(t(ctx, S.rename)),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(t(ctx, S.delete)),
                            ),
                          ],
                        ),
                        onTap: () => widget.onOpenFile(name),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'new-file',
        tooltip: t(context, S.newFile),
        onPressed: () => _create(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            t(context, S.tabFiles),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Spacer(),
          Text(
            widget.project.root.path,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final name = await _askFileName(
      title: t(context, S.newFile),
      hint: t(context, S.fileNameHint),
    );
    if (name == null || !mounted) return;
    final normalized = VisProject.normalizeName(name);
    if (!VisProject.validName(normalized)) {
      _snack(t(context, S.invalidName));
      return;
    }
    if (widget.project.exists(normalized)) {
      _snack(t(context, S.nameExists));
      return;
    }
    widget.project.create(normalized, content: '');
    widget.onOpenFile(normalized);
    _snack('${t(context, S.fileCreated)}: $normalized');
  }

  Future<void> _rename(String name) async {
    final newName = await _askFileName(
      title: t(context, S.renameFile),
      hint: name,
      initial: name,
    );
    if (newName == null || newName == name || !mounted) return;
    final normalized = VisProject.normalizeName(newName);
    if (!VisProject.validName(normalized)) {
      _snack(t(context, S.invalidName));
      return;
    }
    if (widget.project.exists(normalized)) {
      _snack(t(context, S.nameExists));
      return;
    }
    widget.project.rename(name, normalized);
    if (widget.currentFile == name) {
      widget.onOpenFile(normalized);
    }
    setState(() {});
    _snack('${t(context, S.fileRenamed)}: $normalized');
  }

  Future<void> _delete(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(ctx, S.delete)),
        content: Text('${t(ctx, S.deleteConfirm)}\n\n$name'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t(ctx, S.cancel)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t(ctx, S.delete)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      widget.project.delete(name);
      setState(() {});
      _snack('${t(context, S.fileDeleted)}: $name');
    }
  }

  Future<String?> _askFileName({
    required String title,
    required String hint,
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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
