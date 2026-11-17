// SPDX-License-Identifier: MIT
/// VisDroid — IDE ViScript cho Android, nhúng engine ViScript qua FFI.
///
/// Shell 3 tab (Soạn thảo / Tệp / Cài đặt), nút ▶ chạy tức thì ở tab soạn thảo.
/// Chủ đề (Sáng/Tối) và ngôn ngữ (Tiếng Việt mặc định / English) theo `AppState`
/// lưu bằng SharedPreferences; tiếng Anh chọn trong Cài đặt.
library;

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/l10n.dart';
import 'core/project.dart';
import 'core/settings.dart';
import 'core/vis_engine.dart';
import 'screens/editor_screen.dart';
import 'screens/files_screen.dart';
import 'screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(VisDroidApp(state: AppState(prefs)));
}

class VisDroidApp extends StatelessWidget {
  const VisDroidApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => MaterialApp(
        title: 'VisDroid',
        debugShowCheckedModeBanner: false,
        themeMode: state.themeMode,
        theme: _light,
        darkTheme: _dark,
        home: Shell(state: state),
      ),
    );
  }
}

final ThemeData _light = ThemeData(
  useMaterial3: true,
  colorSchemeSeed: const Color(0xFF2563EB),
  brightness: Brightness.light,
);

final ThemeData _dark = ThemeData(
  useMaterial3: true,
  colorSchemeSeed: const Color(0xFF2563EB),
  brightness: Brightness.dark,
);

class Shell extends StatefulWidget {
  const Shell({super.key, required this.state});

  final AppState state;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  VisProject? _project;
  String? _lastFileName;
  bool _booted = false;
  final GlobalKey<EditorScreenState> _editorKey = GlobalKey<EditorScreenState>();
  final VisEngine _engine = VisEngine();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final project = await VisProject.instance();
    await project.seedExamplesIfNeeded();
    final last = widget.state.lastFile;
    final opened =
        last != null && project.exists(last) ? last : null;
    if (!mounted) return;
    setState(() {
      _project = project;
      _booted = true;
    });
    if (opened != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _editorKey.currentState?.openFile(opened);
      });
    }
  }

  void _openFromFiles(String name) {
    setState(() => _tab = 0);
    _editorKey.currentState?.openFile(name);
  }

  @override
  Widget build(BuildContext context) {
    if (!_booted) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final project = _project!;
    return AppLangScope(
      lang: widget.state.lang,
      child: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            EditorScreen(
              key: _editorKey,
              project: project,
              engine: _engine,
              useVm: widget.state.useVm,
              strictCaps: widget.state.strictCaps,
              noExtern: widget.state.noExtern,
              onFileOpened: (name) => _lastFileName = name,
              fontSize: widget.state.fontSize,
              wordWrap: widget.state.wordWrap,
              autoSave: widget.state.autoSave,
            ),
            FilesScreen(
              project: project,
              currentFile: _lastFileName,
              onOpenFile: _openFromFiles,
            ),
            SettingsScreen(appState: widget.state),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.edit_note_outlined),
              selectedIcon: const Icon(Icons.edit_note),
              label: t(context, S.tabEditor),
            ),
            NavigationDestination(
              icon: const Icon(Icons.folder_outlined),
              selectedIcon: const Icon(Icons.folder),
              label: t(context, S.tabFiles),
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: t(context, S.tabSettings),
            ),
          ],
        ),
      ),
    );
  }
}
