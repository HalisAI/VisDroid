// SPDX-License-Identifier: MIT
/// Dịch vụ cài đặt: chủ đề, ngôn ngữ, tuỳ chọn chạy — lưu bằng SharedPreferences
/// của Android qua kênh `visdroid/prefs` (MainActivity), một map JSON nhỏ.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'l10n.dart';

/// Store cài đặt — nạp một lần lúc khởi động, ghi lại qua channel.
class PrefsStore {
  PrefsStore._(this._map);

  static const _channel = MethodChannel('visdroid/prefs');
  final Map<String, String> _map;

  static Future<PrefsStore> load() async {
    Map<String, String> map = <String, String>{};
    try {
      final raw = await _channel
          .invokeMethod<String>('get', {'key': 'json'});
      if (raw != null) {
        map = Map<String, String>.from(jsonDecode(raw) as Map);
      }
    } catch (_) {
      // Không có platform channel (test/preview) — dùng store rỗng trong RAM.
    }
    return PrefsStore._(map);
  }

  String? get(String key) => _map[key];

  Future<void> set(String key, String value) async {
    _map[key] = value;
    await _channel
        .invokeMethod('set', {'key': 'json', 'value': jsonEncode(_map)});
  }

  Future<void> remove(String key) async {
    _map.remove(key);
    await _channel
        .invokeMethod('set', {'key': 'json', 'value': jsonEncode(_map)});
  }
}

class AppState extends ChangeNotifier {
  AppState(this._prefs) {
    _themeMode = ThemeMode.values[_int('themeMode', 0)];
    final li = _int('lang', 0);
    _lang = li == 1 ? AppLang.english : AppLang.vietnamese;
    _useVm = _bool('useVm', false);
    _strictCaps = _bool('strictCaps', false);
    _noExtern = _bool('noExtern', false);
    _lastFile = _prefs.get('lastFile');
    _fontSize = _double('fontSize', 15.0);
    _autoSave = _bool('autoSave', true);
  }

  final PrefsStore _prefs;
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

  int _int(String key, int def) =>
      int.tryParse(_prefs.get(key) ?? '') ?? def;
  double _double(String key, double def) =>
      double.tryParse(_prefs.get(key) ?? '') ?? def;
  bool _bool(String key, bool def) {
    final v = _prefs.get(key);
    return v == null ? def : v == 'true';
  }

  void setThemeMode(ThemeMode m) {
    _themeMode = m;
    _prefs.set('themeMode', m.index.toString());
    notifyListeners();
  }

  void setLang(AppLang l) {
    _lang = l;
    _prefs.set('lang', l == AppLang.english ? '1' : '0');
    notifyListeners();
  }

  void setUseVm(bool v) {
    _useVm = v;
    _prefs.set('useVm', v.toString());
    notifyListeners();
  }

  void setStrictCaps(bool v) {
    _strictCaps = v;
    _prefs.set('strictCaps', v.toString());
    notifyListeners();
  }

  void setNoExtern(bool v) {
    _noExtern = v;
    _prefs.set('noExtern', v.toString());
    notifyListeners();
  }

  void setFontSize(double v) {
    _fontSize = v;
    _prefs.set('fontSize', v.toString());
    notifyListeners();
  }

  void setAutoSave(bool v) {
    _autoSave = v;
    _prefs.set('autoSave', v.toString());
    notifyListeners();
  }

  void setLastFile(String? path) {
    _lastFile = path;
    if (path == null) {
      _prefs.remove('lastFile');
    } else {
      _prefs.set('lastFile', path);
    }
    notifyListeners();
  }
}
