import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UISettings extends ChangeNotifier {
  final SharedPreferences? _sharedPreferences;

  static const double scaleMin = 0.5;
  static const double scaleMax = 1.8;

  // Settings that are available to user, so any
  // change to them should call notifyListeners()
  double _scale;
  int _tabIndex;
  Locale? _locale;

  double get scale => _scale;
  set scale(double value) {
    if (_scale == value) return;
    _scale = value;
    _sharedPreferences?.setDouble("scale", value);
    notifyListeners();
  }

  int get tabIndex => _tabIndex;
  set tabIndex(int value) {
    if (_tabIndex == value) return;
    _tabIndex = value;
    _sharedPreferences?.setInt("tab_index", value);
    /* No need for notifyListeners() - this is internal 
     * value put here just for saving into SharedPreferences */
  }

  Locale? get locale => _locale;
  set locale(Locale? value) {
    if (_locale == value) return;

    _locale = value;

    if (value != null) {
      _sharedPreferences?.setString("language", value.languageCode);
      final country = value.countryCode;
      if (country != null) {
        _sharedPreferences?.setString("country", country);
      } else {
        _sharedPreferences?.remove("country");
      }
    } else {
      _sharedPreferences?.remove("locale");
    }

    notifyListeners();
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
      if (scaleValue != null) {
        _scale = scaleValue.clamp(scaleMin, scaleMax);
      }

      final tabIndexValue = preferences.getInt("tab_index");
      if (tabIndexValue != null) {
        _tabIndex = tabIndexValue.clamp(1, 3);
      }

      final languageValue = preferences.getString("language");
      final countryValue = preferences.getString("country");
      if (languageValue != null) {
        _locale = Locale(languageValue, countryValue);
      }
    } catch (err) {
      print("SharedPreferences error: $err");
    }
  }
}
