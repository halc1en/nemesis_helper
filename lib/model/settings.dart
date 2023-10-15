import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UISettings extends ChangeNotifier {
  final SharedPreferences? _sharedPreferences;

  static const double scaleMin = 0.5;
  static const double scaleMax = 1.8;

  // Flag to indicate that changed setting requires reloading/reparsing JSON
  bool reloadJson = false;

  // Settings that are available to user, so any
  // change to them should call notifyListeners()
  double _scale;
  int _tabIndex;
  Locale? _locale;
  String? _selectedModules;

  double get scale => _scale;
  set scale(double value) {
    if (_scale == value) return;
    _scale = value;
    _sharedPreferences?.setDouble("scale", value);
    notifyListeners();
  }

  int get tabIndex => this._tabIndex;
  set tabIndex(int value) {
    if (this._tabIndex == value) return;
    this._tabIndex = value;
    this._sharedPreferences?.setInt("tab_index", value);
    /* No need for notifyListeners() - this is internal 
     * value put here just for saving into SharedPreferences */
  }

  Locale? get locale => this._locale;
  set locale(Locale? value) {
    if (this._locale == value) return;

    this._locale = value;

    if (value != null) {
      this._sharedPreferences?.setString("language", value.languageCode);
      final country = value.countryCode;
      if (country != null) {
        this._sharedPreferences?.setString("country", country);
      } else {
        this._sharedPreferences?.remove("country");
      }
    } else {
      this._sharedPreferences?.remove("locale");
    }

    /* After locale change we have to reload JSON with proper language */
    this.reloadJson = true;

    notifyListeners();
  }

  List<String>? get selectedModules {
    final modules = this._selectedModules;
    if (modules == null) return null;
    return (jsonDecode(modules) as List<dynamic>?)
        ?.map((item) => item as String)
        .toList();
  }

  void selectedModulesSet(List<String>? value) {
    final encoded = jsonEncode(value);
    if (this._selectedModules == encoded) return;

    this._selectedModules = encoded;

    if (value != null) {
      this._sharedPreferences?.setString("modules", encoded);
    } else {
      this._sharedPreferences?.remove("modules");
    }

    /* Load the new modules */
    this.reloadJson = true;

    notifyListeners();
  }

  void selectedModulesAdd(String module) {
    final modules = selectedModules ?? [];
    if (!modules.any((m) => m == module)) {
      modules.add(module);
      final encoded = jsonEncode(modules);
      this._selectedModules = encoded;
      this._sharedPreferences?.setString("modules", encoded);

      /* Load the new modules */
      this.reloadJson = true;

      notifyListeners();
    }
  }

  void selectedModulesRemove(String module) {
    final modules = selectedModules;
    if (modules != null) {
      modules.removeWhere((m) => m == module);
      final encoded = jsonEncode(modules);
      this._selectedModules = encoded;
      this._sharedPreferences?.setString("modules", encoded);

      /* Load the new modules */
      this.reloadJson = true;

      notifyListeners();
    }
  }

  UISettings(this._sharedPreferences)
      : _scale = 1.0,
        _tabIndex = 0 {
    final preferences = _sharedPreferences;
    if (preferences == null) {
      return;
    }

    try {
      final scaleValue = preferences.getDouble("scale");
      if (scaleValue != null) _scale = scaleValue.clamp(scaleMin, scaleMax);

      final tabIndexValue = preferences.getInt("tab_index");
      if (tabIndexValue != null) _tabIndex = tabIndexValue.clamp(0, 1);

      final languageValue = preferences.getString("language");
      final countryValue = preferences.getString("country");
      if (languageValue != null) _locale = Locale(languageValue, countryValue);

      final modulesValue = preferences.getString("modules");
      if (modulesValue != null) _selectedModules = modulesValue;
    } catch (err) {
      print("SharedPreferences error: $err");
    }
  }
}
