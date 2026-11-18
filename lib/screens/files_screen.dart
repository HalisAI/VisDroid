// SPDX-License-Identifier: MIT
/// Màn hình tệp: danh sách tệp dự án, tạo/mở/đổi tên/xoá, ví dụ mẫu đi kèm.
library;

import 'package:material_ui/material_ui.dart';

import '../core/l10n.dart';
import '../core/project.dart';
import '../widgets/name_dialog.dart';

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
    final cs = Theme.of(context).colorScheme;
    final files = widget.project.listFiles();
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, S.tabFiles)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Text(
                '${files.length} ${t(context, S.filesCount)}',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 14, color: cs.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.project.root.path,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: cs.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: files.isEmpty
                ? _empty(context)
                : ListView.separated(
                    itemCount: files.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
                    itemBuilder: (context, i) {
                      final f = files[i];
                      final name = f.path.split('/').last;
                      final stat = f.statSync();
                      final isCurrent = name == widget.currentFile;
                      return ListTile(
                        tileColor: isCurrent
                            ? cs.primaryContainer.withValues(alpha: 0.35)
                            : null,
                        leading: Icon(
                          Icons.description_outlined,
                          color: isCurrent
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        subtitle: Text(
                          '${_fmtSize(stat.size)} · '
                          '${stat.modified.day}/${stat.modified.month}/${stat.modified.year}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: isCurrent
                            ? Icon(Icons.check_circle, size: 18, color: cs.primary)
                            : PopupMenuButton<String>(
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-file',
        tooltip: t(context, S.newFile),
        onPressed: () => _create(),
        icon: const Icon(Icons.note_add_outlined),
        label: Text(t(context, S.newFile)),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_outlined,
                size: 56, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              t(context, S.noFileYet),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              t(context, S.noFileHint),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _create() async {
    final name = await askFileName(
      context,
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
    final newName = await askFileName(
      context,
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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
