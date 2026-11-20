// SPDX-License-Identifier: MIT
/// VisDroid — IDE ViScript cho Android, nhúng engine ViScript qua FFI.
///
/// Shell 3 tab (Soạn thảo / Tệp / Cài đặt). Bấm ▶ ở tab soạn thảo mở
/// màn thực thi riêng (kiểu Pydroid); Back quay lại soạn thảo.
/// Chủ đề (Sáng/Tối) và ngôn ngữ (Tiếng Việt mặc định / English) theo `AppState`
/// lưu bằng SharedPreferences; tiếng Anh chọn trong Cài đặt.
library;

import 'package:material_ui/material_ui.dart';
import 'core/l10n.dart';
import 'core/project.dart';
import 'core/run_history.dart';
import 'core/settings.dart';
import 'core/vis_engine.dart';
import 'screens/editor_screen.dart';
import 'screens/files_screen.dart';
import 'screens/maze_screen.dart';
import 'screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await PrefsStore.load();
  runApp(VisDroidApp(state: AppState(prefs)));
}

class VisDroidApp extends StatelessWidget {
  const VisDroidApp({
    super.key,
    required this.state,
    this.engine,
    this.history,
  });

  final AppState state;

  /// Cho phép tiêm engine giả trong test/preview.
  final ScriptEngine? engine;

  /// Cho phép tiêm lịch sử chạy có sẵn trong test/preview.
  final RunHistoryStore? history;

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
        home: Shell(
          state: state,
          engine: engine ?? VisEngine(),
          history: history ?? RunHistoryStore(),
        ),
      ),
    );
  }
}

final ThemeData _light = ThemeData(
  useMaterial3: true,
  colorSchemeSeed: const Color(0xFF2563EB),
  brightness: Brightness.light,
  visualDensity: VisualDensity.comfortable,
);

final ThemeData _dark = ThemeData(
  useMaterial3: true,
  colorSchemeSeed: const Color(0xFF2563EB),
  brightness: Brightness.dark,
  visualDensity: VisualDensity.comfortable,
);

class Shell extends StatefulWidget {
  const Shell({
    super.key,
    required this.state,
    required this.engine,
    required this.history,
  });

  final AppState state;
  final ScriptEngine engine;
  final RunHistoryStore history;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  VisProject? _project;
  String? _lastFileName;
  bool _booted = false;
  final GlobalKey<EditorScreenState> _editorKey = GlobalKey<EditorScreenState>();

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
              engine: widget.engine,
              history: widget.history,
              useVm: widget.state.useVm,
              strictCaps: widget.state.strictCaps,
              noExtern: widget.state.noExtern,
              onFileOpened: (name) => _lastFileName = name,
              fontSize: widget.state.fontSize,
              autoSave: widget.state.autoSave,
              onWantFiles: () => setState(() => _tab = 1),
            ),
            FilesScreen(
              project: project,
              currentFile: _lastFileName,
              onOpenFile: _openFromFiles,
            ),
            SettingsScreen(appState: widget.state),
            MazeScreen(
              engine: widget.engine,
              prefs: widget.state.prefs,
              appState: widget.state,
            ),
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
            NavigationDestination(
              icon: const Icon(Icons.sports_esports_outlined),
              selectedIcon: const Icon(Icons.sports_esports),
              label: t(context, S.gameTab),
            ),
          ],
        ),
      ),
    );
  }
}
