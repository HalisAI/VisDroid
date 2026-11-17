// SPDX-License-Identifier: MIT
/// Cài đặt: chủ đề Sáng/Tối/Theo hệ thống, ngôn ngữ (Tiếng Việt mặc định /
/// English), tuỳ chọn chạy script và trang giới thiệu.
library;

import 'package:material_ui/material_ui.dart';

import '../core/l10n.dart';
import '../core/settings.dart';
import '../core/vis_engine.dart';

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
    return ListView(
      children: [
        _sectionTitle(context, t(context, S.theme)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<ThemeMode>(
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
        const SizedBox(height: 20),
        _sectionTitle(context, t(context, S.language)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<AppLang>(
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
        const SizedBox(height: 20),
        _sectionTitle(context, '${t(context, S.run)} · script'),
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
        const SizedBox(height: 20),
        _sectionTitle(context, t(context, S.about)),
        ListTile(
          leading: Icon(
            _engineOk ? Icons.memory : Icons.error_outline,
            color: _engineOk
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
          title: Text(t(context, S.engineVersion)),
          subtitle: Text(_engineVersion, style: _mono(context)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('VisDroid 1.0.0'),
              SizedBox(height: 8),
              Text('Dart 3.14 · Flutter 3.50 · Android 7.1.1+ (API 25)'),
            ],
          ),
        ),
      ],
    );
  }

  TextStyle? _mono(BuildContext context) => const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
      );

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
