// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';
import 'package:nemesis_helper/model/settings.dart';

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

  /// Selected language
  final String currentLanguage;

  /// Supported languages (in database, not in Flutter interface)
  final List<String> supportedLanguages;

  /// Modules available for selection
  final List<Module> selectableModules;

  /// Reference to show
  final ReferenceData reference;

  /// Images being loaded
  final Map<String, JsonImage> images;

  /// Merges [from] json into [to]
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

  /// Merges [from] json into [to] as _deepMergeMap() does, but start
  /// from object [id]
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

  /// Return 'true' on success
  static Future<bool> _loadAndApplyPatch(
      Map<String, dynamic> module,
      String patch,
      Future<dynamic> Function(String, {required bool canFail})
          openJson) async {
    final patchJson = await openJson(patch, canFail: true) as List<dynamic>?;
    if (patchJson == null) return false;
    for (final (patchedObject as Map<String, dynamic>) in patchJson) {
      _findAndMerge(module, patchedObject, patchedObject['id'] as String);
    }
    return true;
  }

  /// Load [selectedModules] from [jsonName] using [locale] language
  /// with English as fallback
  static Future<JsonData> fromJson(
      BuildContext context,
      UISettings ui,
      String jsonName,
      Future<dynamic> Function(String name, {required bool canFail}) openJson,
      Future<ImageProvider<Object>?> Function(String name, bool offline)
          openImage) async {
    final locale = ui.locale;
    final selectedModules = ui.selectedModules;
    final offline = ui.offline;
    List<Module> selectableModules = [];

    // Parse main JSON file
    final mainJson =
        await openJson(jsonName, canFail: false) as Map<String, dynamic>;

    // Get list of supported languages
    final supportedLanguages =
        (mainJson['languages'] as List<dynamic>? ?? ["en"])
            .map((e) => e as String)
            .toList();

    // Get currently selected language
    final language = (supportedLanguages.contains(locale?.languageCode))
        ? (locale?.languageCode)!
        : supportedLanguages.first;

    // Apply main JSON localization (with fallback to English)
    final mainLocale =
        (await openJson("${jsonName}_$language", canFail: true) ??
                await openJson("${jsonName}_en", canFail: true))
            as Map<String, dynamic>?;
    if (mainLocale != null) _deepMergeMap(mainJson, mainLocale);

    // Load each module and append to main json, merging and/or replacing same values
    for (final moduleName in (mainJson['modules'] as List<dynamic>? ?? [])
        .map((m) => (m as Map<String, dynamic>)['name'] as String)) {
      // Load module with patches
      final module = (await openJson(moduleName, canFail: false)
              as Map<String, dynamic>?) ??
          {};

      // Apply module patches
      for (final (patchName as String)
          in module['patches'] as List<dynamic>? ?? []) {
        await _loadAndApplyPatch(module, "${moduleName}_$patchName", openJson);
      }

      // Apply module localization with patches (with fallback to English)
      final moduleLocale =
          (await openJson("${moduleName}_$language", canFail: true) ??
                  await openJson("${moduleName}_en", canFail: true))
              as Map<String, dynamic>?;
      if (moduleLocale != null) {
        _deepMergeMap(module, moduleLocale);

        for (final (patchName as String)
            in moduleLocale['patches'] as List<dynamic>? ?? []) {
          await _loadAndApplyPatch(
                  module, "${moduleName}_${language}_$patchName", openJson) ||
              await _loadAndApplyPatch(
                  module, "${moduleName}_en_$patchName", openJson);
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

    final icons = <String, JsonIcon>{};
    for (final (name, id) in (mainJson['icons'] as List<dynamic>? ?? [])
        .map((icon) => icon as Map<String, dynamic>)
        .nonNulls
        .map((icon) => (icon['path'] as String, icon['id'] as String))) {
      final provider = await openImage(name, offline);
      if (provider == null) continue;
      if (context.mounted) {
        precacheImage(provider, context, size: const Size.square(64.0));
      }
      icons.addAll({
        id: JsonIcon(provider: ResizeImage(provider, width: 64, height: 64))
      });
    }

    final images = <String, JsonImage>{};
    for (final (name, id) in (mainJson['images'] as List<dynamic>? ?? [])
        .map((image) => image as Map<String, dynamic>)
        .nonNulls
        .map((image) => (image['path'] as String, image['id'] as String))) {
      images.addAll({id: JsonImage(provider: openImage(name, offline))});
    }

    return JsonData(
        currentLanguage: language,
        supportedLanguages: supportedLanguages,
        selectableModules: selectableModules,
        // Parse the resulting JSON
        reference: ReferenceData.fromJson(
            mainJson, images, icons, ui.sharedPreferences),
        images: images);
  }
}

class JsonImage {
  const JsonImage({
    required this.provider,
  });

  /// Provider to load the image
  final Future<ImageProvider?> provider;
}

class JsonIcon {
  const JsonIcon({
    required this.provider,
  });

  /// Provider to load the icon.  Icons are small
  /// so there is no real need in [Future].
  final ImageProvider provider;
}
