// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:io';

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
    required this.images,
  });

  // Selected language
  final String currentLanguage;

  // Supported languages (in database, not in Flutter interface)
  final List<String> supportedLanguages;

  // Modules available for selection
  final List<Module> selectableModules;

  // Reference to show
  final ReferenceData reference;

  // Images being loaded
  final Map<String, JsonImage> images;

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

  // Merges [from] json into [to] as _deepMergeMap() does, but start
  // from object [id]
  static bool _findAndMerge(dynamic to, Map<String, dynamic> from, String id) {
    for (final value in (to is List)
        ? to
        : (to is Map)
            ? to.values
            : []) {
      if (value is Map) {
        if (value['id'] == id) {
          // Found! Do the merging
          _deepMergeMap(value as Map<String, dynamic>, from);
          return true;
        }
        if (_findAndMerge(value as Map<String, dynamic>, from, id)) {
          return true;
        }
      } else if (value is List) {
        if (_findAndMerge(value, from, id)) return true;
      }
    }

    return false;
  }

  // Return 'true' on success
  static Future<bool> _loadAndApplyPatch(Map<String, dynamic> module,
      String patch, Future<dynamic> Function(String) loadAndDecode) async {
    final patchJson = await loadAndDecode(patch) as List<dynamic>?;
    if (patchJson == null) return false;
    for (final (patchedObject as Map<String, dynamic>) in patchJson) {
      _findAndMerge(module, patchedObject, patchedObject['id'] as String);
    }
    return true;
  }

  // Load [selectedModules] from [jsonName] using [locale] language
  // with English as fallback
  static Future<JsonData> fromJson(
      Locale? locale,
      String jsonName,
      List<String>? selectedModules,
      File? Function(String name) openFile) async {
    List<Module> selectableModules = [];

    Future<dynamic> loadJsonAndDecode(String jsonName) async {
      try {
        final jsonString = await openFile("$jsonName.json")?.readAsString();
        if (jsonString == null) return null;
        return jsonDecode(jsonString);
      } catch (_) {
        return null;
      }
    }

    // Parse main JSON file
    final mainJson = await loadJsonAndDecode(jsonName) as Map<String, dynamic>;

    // Get list of supported languages
    final supportedLanguages = (mainJson['languages'] as List<dynamic>)
        .map((e) => e as String)
        .toList();

    // Get currently selected language
    final language = (supportedLanguages.contains(locale?.languageCode))
        ? (locale?.languageCode)!
        : supportedLanguages.first;

    // Apply main JSON localization (with fallback to English)
    final mainLocale = (await loadJsonAndDecode("${jsonName}_$language") ??
        await loadJsonAndDecode("${jsonName}_en")) as Map<String, dynamic>?;
    if (mainLocale != null) _deepMergeMap(mainJson, mainLocale);

    // Load each module and append to main json, merging and/or replacing same values
    for (final moduleName in (mainJson['modules'] as List<dynamic>? ?? [])
        .map((m) => (m as Map<String, dynamic>)['name'] as String)) {
      // Load module with patches
      final module =
          (await loadJsonAndDecode(moduleName) as Map<String, dynamic>?) ?? {};

      // Apply module patches
      for (final (patchName as String)
          in module['patches'] as List<dynamic>? ?? []) {
        await _loadAndApplyPatch(
            module, "${moduleName}_$patchName", loadJsonAndDecode);
      }

      // Apply module localization with patches (with fallback to English)
      final moduleLocale =
          (await loadJsonAndDecode("${moduleName}_$language") ??
                  await loadJsonAndDecode("${moduleName}_en"))
              as Map<String, dynamic>?;
      if (moduleLocale != null) {
        _deepMergeMap(module, moduleLocale);

        for (final (patchName as String)
            in moduleLocale['patches'] as List<dynamic>? ?? []) {
          await _loadAndApplyPatch(module,
                  "${moduleName}_${language}_$patchName", loadJsonAndDecode) ||
              await _loadAndApplyPatch(
                  module, "${moduleName}_en_$patchName", loadJsonAndDecode);
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

    MapEntry<String, JsonImage>? parseJsonImage(
        Map<String, dynamic> image, bool icon) {
      try {
        return MapEntry(
            image['id'] as String,
            JsonImage(
                icon: icon,
                provider: FileImage(openFile(image['name'] as String)!)));
      } catch (_) {
        return null;
      }
    }

    final images = <String, JsonImage>{};
    images.addEntries((mainJson['icons'] as List<dynamic>?)
            ?.map((icon) => icon as Map<String, dynamic>)
            .map((icon) => parseJsonImage(icon, true))
            .nonNulls ??
        []);
    images.addEntries((mainJson['images'] as List<dynamic>?)
            ?.map((icon) => icon as Map<String, dynamic>)
            .map((icon) => parseJsonImage(icon, false))
            .nonNulls ??
        []);

    // Parse the resulting JSON
    return JsonData(
        currentLanguage: language,
        supportedLanguages: supportedLanguages,
        selectableModules: selectableModules,
        reference: ReferenceData.fromJson(
          mainJson,
          images,
        ),
        images: images);
  }
}

class JsonImage {
  const JsonImage({
    required this.provider,
    required this.icon,
  });

  // Provider to load the image
  final ImageProvider provider;

  // Set to render with same height as text
  final bool icon;
}
