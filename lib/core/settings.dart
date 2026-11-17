// SPDX-License-Identifier: MIT
/// Dịch vụ cài đặt (SharedPreferences): chủ đề, ngôn ngữ, tuỳ chọn chạy.
library;

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';

class AppState extends ChangeNotifier {
  AppState(this._prefs) {
    _themeMode = ThemeMode.values[_prefs.getInt('themeMode') ?? 0];
    final li = _prefs.getInt('lang') ?? 0;
    _lang = li == 1 ? AppLang.english : AppLang.vietnamese;
    _useVm = _prefs.getBool('useVm') ?? false;
    _strictCaps = _prefs.getBool('strictCaps') ?? false;
    _noExtern = _prefs.getBool('noExtern') ?? false;
    _lastFile = _prefs.getString('lastFile');
    _fontSize = _prefs.getDouble('fontSize') ?? 15.0;
    _autoSave = _prefs.getBool('autoSave') ?? true;
  }

  final SharedPreferences _prefs;
  ThemeMode _themeMode = ThemeMode.system;
  AppLang _lang = AppLang.vietnamese;
  bool _useVm = false;
  bool _strictCaps = false;
  bool _noExtern = false;
  String? _lastFile;
  double _fontSize = 15.0;
  bool _autoSave = true;

  ThemeMode get themeMode => _themeMode;
  AppLang get lang => _lang;
  bool get useVm => _useVm;
  bool get strictCaps => _strictCaps;
  bool get noExtern => _noExtern;
  String? get lastFile => _lastFile;
  double get fontSize => _fontSize;
  bool get autoSave => _autoSave;

  void setThemeMode(ThemeMode m) {
    _themeMode = m;
    _prefs.setInt('themeMode', m.index);
    notifyListeners();
  }

  void setLang(AppLang l) {
    _lang = l;
    _prefs.setInt('lang', l == AppLang.english ? 1 : 0);
    notifyListeners();
  }

  void setUseVm(bool v) {
    _useVm = v;
    _prefs.setBool('useVm', v);
    notifyListeners();
  }

  void setStrictCaps(bool v) {
    _strictCaps = v;
    _prefs.setBool('strictCaps', v);
    notifyListeners();
  }

  void setNoExtern(bool v) {
    _noExtern = v;
    _prefs.setBool('noExtern', v);
    notifyListeners();
  }

  void setFontSize(double v) {
    _fontSize = v;
    _prefs.setDouble('fontSize', v);
    notifyListeners();
  }

  void setAutoSave(bool v) {
    _autoSave = v;
    _prefs.setBool('autoSave', v);
    notifyListeners();
  }

  void setLastFile(String? path) {
    _lastFile = path;
    if (path == null) {
      _prefs.remove('lastFile');
    } else {
      _prefs.setString('lastFile', path);
    }
    notifyListeners();
  }
}
