// SPDX-License-Identifier: MIT
/// Cài đặt: chủ đề Sáng/Tối/Theo hệ thống, ngôn ngữ, tuỳ chọn chạy script,
/// cỡ chữ editor và trang giới thiệu — gom nhóm thành các thẻ riêng biệt.
library;

import 'package:material_ui/material_ui.dart';

import '../core/l10n.dart';
import '../core/settings.dart';
import '../core/vis_engine.dart';
import 'cheatsheet_screen.dart';

const String kAppVersion = '1.1.4';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.appState});

  final AppState appState;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _engineVersion = '…';
  bool _engineOk = true;

  @override
  void initState() {
    super.initState();
    _loadEngineInfo();
  }

  Future<void> _loadEngineInfo() async {
    try {
      final engine = VisEngine();
      final v = await engine.versionInfo();
      if (mounted) {
        setState(() {
          _engineVersion = v;
          _engineOk = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _engineVersion = t(context, S.cantOpenEngine);
          _engineOk = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.appState;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t(context, S.tabSettings))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _sectionTitle(context, t(context, S.theme)),
          _card(
            context,
            SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto_outlined),
                  label: Text(t(context, S.themeSystem)),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode_outlined),
                  label: Text(t(context, S.themeLight)),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode_outlined),
                  label: Text(t(context, S.themeDark)),
                ),
              ],
              selected: {app.themeMode},
              onSelectionChanged: (sel) => app.setThemeMode(sel.first),
            ),
          ),
          _sectionTitle(context, t(context, S.language)),
          _card(
            context,
            SegmentedButton<AppLang>(
              segments: [
                ButtonSegment(
                  value: AppLang.vietnamese,
                  label: Text(t(context, S.langVietnamese)),
                ),
                ButtonSegment(
                  value: AppLang.english,
                  label: Text(t(context, S.langEnglish)),
                ),
              ],
              selected: {app.lang},
              onSelectionChanged: (sel) => app.setLang(sel.first),
            ),
          ),
          _sectionTitle(context, '${t(context, S.run)} · script'),
          _card(
            context,
            Column(
              children: [
                SwitchListTile(
                  title: Text(t(context, S.useVmPath)),
                  subtitle: Text('vis run --vm', style: _mono(context)),
                  value: app.useVm,
                  onChanged: (v) => app.setUseVm(v),
                ),
                SwitchListTile(
                  title: Text(t(context, S.strictCaps)),
                  subtitle: Text('vis run --strict-caps', style: _mono(context)),
                  value: app.strictCaps,
                  onChanged: (v) => app.setStrictCaps(v),
                ),
                SwitchListTile(
                  title: Text(t(context, S.noExtern)),
                  subtitle: Text('vis run --no-extern', style: _mono(context)),
                  value: app.noExtern,
                  onChanged: (v) => app.setNoExtern(v),
                ),
              ],
            ),
          ),
          _sectionTitle(context, t(context, S.editor)),
          _card(
            context,
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Expanded(child: Text(t(context, S.fontSize))),
                      Text(app.fontSize.toInt().toString(),
                          style: _mono(context)),
                    ],
                  ),
                ),
                Slider(
                  value: app.fontSize,
                  min: 10,
                  max: 24,
                  divisions: 14,
                  label: app.fontSize.toInt().toString(),
                  onChanged: (v) => app.setFontSize(v),
                ),
                SwitchListTile(
                  title: Text(t(context, S.autoSave)),
                  value: app.autoSave,
                  onChanged: (v) => app.setAutoSave(v),
                ),
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(t(context, S.cheatSheet)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const CheatSheetScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _sectionTitle(context, t(context, S.about)),
          _card(
            context,
            Column(
              children: [
                ListTile(
                  leading: Icon(
                    _engineOk ? Icons.memory : Icons.error_outline,
                    color: _engineOk ? cs.primary : cs.error,
                  ),
                  title: Text(t(context, S.engineVersion)),
                  subtitle: Text(_engineVersion, style: _mono(context)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VisDroid $kAppVersion',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Dart 3.14 · Flutter 3.50 · Android 7.1.1+ (API 25)',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t(context, S.aboutDesc),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Widget child) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: child,
      ),
    );
  }

  TextStyle? _mono(BuildContext context) => const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
      );

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
