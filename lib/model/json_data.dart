// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nemesis_helper/ui/screen_reference.dart';

@immutable
class Module {
  const Module({
    required this.name,
    required this.description,
    required this.defaultEnabled,
  });

  final String name;
  final String description;
  final bool defaultEnabled;
}

class JsonData extends ChangeNotifier {
  JsonData({
    required this.currentLanguage,
    required this.supportedLanguages,
    required this.selectableModules,
    required this.reference,
  });

  // Selected language
  final String currentLanguage;

  // Supported languages (in database, not in Flutter interface)
  final List<String> supportedLanguages;

  // Modules available for selection
  final List<Module> selectableModules;

  // Reference to show
  final ReferenceData reference;

  // Merges [from] json into [to]
  static void _deepMergeMap(
      Map<String, dynamic> to, Map<String, dynamic> from) {
    from.forEach((key, value) {
      if (to.containsKey(key)) {
        final toKey = to[key];
        if (toKey is Map && value is Map) {
          // Recursively descend into maps
          _deepMergeMap(
              toKey as Map<String, dynamic>, value as Map<String, dynamic>);
        } else if (toKey is List && value is List) {
          // Merge lists
          (to[key] as List<dynamic>).addAll(value);
        } else if (toKey is List && value is Map ||
            toKey is Map && value is List) {
          //ERROR type mismatch
        } else {
          // Replace leaf values
          to[key] = value;
        }
      } else {
        to[key] = value;
      }
    });
  }

  static bool _findAndMergeList(
      List<dynamic> to, Map<String, dynamic> from, String id) {
    for (final value in to) {
      if (value is Map) {
        if (value['id'] == id) {
          // Found! Do the merging
          _deepMergeMap(value as Map<String, dynamic>, from);
          return true;
        }
        if (_findAndMergeMap(value as Map<String, dynamic>, from, id)) {
          return true;
        }
      } else if (value is List) {
        if (_findAndMergeList(value, from, id)) return true;
      }
    }

    return false;
  }

  // Merges [from] json into [to] as _deepMergeMap() does, but start
  // from object [id]
  static bool _findAndMergeMap(
      Map<String, dynamic> to, Map<String, dynamic> from, String id) {
    for (final value in to.values) {
      if (value is Map) {
        if (value['id'] == id) {
          // Found! Do the merging
          _deepMergeMap(value as Map<String, dynamic>, from);
          return true;
        }
        if (_findAndMergeMap(value as Map<String, dynamic>, from, id)) {
          return true;
        }
      } else if (value is List) {
        if (_findAndMergeList(value, from, id)) return true;
      }
    }

    return false;
  }

  // Return 'true' on success
  static Future<bool> loadAndApplyPatch(Map<String, dynamic> module,
      String patch, Future<dynamic> Function(String) loadAndDecode) async {
    final patchJson = await loadAndDecode(patch) as List<dynamic>?;
    if (patchJson == null) return false;
    for (final (patchedObject as Map<String, dynamic>) in patchJson) {
      _findAndMergeMap(module, patchedObject, patchedObject['id'] as String);
    }
    return true;
  }

  // Load [selectedModules] from [jsonName] using [locale] language
  // with English as fallback
  static Future<JsonData> fromJson(
      Locale? locale,
      String jsonName,
      List<String>? selectedModules,
      Future<String?> Function(String name) loadJson) async {
    List<Module> selectableModules = [];

    Future<dynamic> loadAndDecode(String jsonName) async {
      final jsonString = await loadJson(jsonName);
      if (jsonString == null) return null;
      return jsonDecode(jsonString);
    }

    // Parse main JSON file
    final mainJson = await loadAndDecode(jsonName) as Map<String, dynamic>;

    // Get list of supported languages
    final supportedLanguages = (mainJson['languages'] as List<dynamic>)
        .map((e) => e as String)
        .toList();

    // Get currently selected language
    final language = (supportedLanguages.contains(locale?.languageCode))
        ? (locale?.languageCode)!
        : supportedLanguages.first;

    // Apply main JSON localization (with fallback to English)
    final mainLocale = (await loadAndDecode("${jsonName}_$language") ??
        await loadAndDecode("${jsonName}_en")) as Map<String, dynamic>?;
    if (mainLocale != null) _deepMergeMap(mainJson, mainLocale);

    // Load each module and append to main json, merging and/or replacing same values
    for (final moduleName in (mainJson['modules'] as List<dynamic>? ?? [])
        .map((m) => (m as Map<String, dynamic>)['name'] as String)) {
      // Load module with patches
      final module =
          (await loadAndDecode(moduleName) as Map<String, dynamic>?) ?? {};

      // Apply module patches
      for (final (patchName as String)
          in module['patches'] as List<dynamic>? ?? []) {
        await loadAndApplyPatch(
            module, "${moduleName}_$patchName", loadAndDecode);
      }

      // Apply module localization with patches (with fallback to English)
      final moduleLocale = (await loadAndDecode("${moduleName}_$language") ??
          await loadAndDecode("${moduleName}_en")) as Map<String, dynamic>?;
      if (moduleLocale != null) {
        _deepMergeMap(module, moduleLocale);

        for (final (patchName as String)
            in moduleLocale['patches'] as List<dynamic>? ?? []) {
          await loadAndApplyPatch(module,
                  "${moduleName}_${language}_$patchName", loadAndDecode) ||
              await loadAndApplyPatch(
                  module, "${moduleName}_en_$patchName", loadAndDecode);
        }
      }

      // Collect modules that have descriptions - they will be
      // selectable in settings menu
      final description = module['description'] as String?;
      if (description != null) {
        selectableModules.add(Module(
            name: moduleName,
            description: description,
            defaultEnabled: module['default'] as bool? ?? false));
        // This 'description' field is for this module only, do not merge it
        module.remove('description');
      }

      // Merge module into main JSON if it is enabled
      if (selectedModules?.contains(moduleName) ?? true) {
        _deepMergeMap(mainJson, module);
      }
    }

    // Parse the resulting JSON
    return JsonData(
        currentLanguage: language,
        supportedLanguages: supportedLanguages,
        selectableModules: selectableModules,
        reference: ReferenceData.fromJson(mainJson));
  }
}
