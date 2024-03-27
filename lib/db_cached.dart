// Local cache for remote database
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nemesis_helper/model/settings.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:quiver/time.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A wrapper to access network database with fallbacks to local cache
class DbCached {
  final LazyBox<Uint8List> _cacheImages;
  final Box<String> _cacheUpdatedAt;
  final Box<String> _cacheJsons;

  final Map<String, dynamic>? _networkJsonsCache;
  final List<FileObject>? _networkImagesList;

  /// List of loaded files (maybe in RAM only and not cached locally yet)
  final Set<String> _referencedFiles = {};

  DbCached._(this._cacheImages, this._cacheUpdatedAt, this._cacheJsons,
      this._networkJsonsCache, this._networkImagesList);

  static Future<DbCached> build(UISettings ui) async {
    final Future<Map<String, dynamic>?>? jsons;
    final Future<List<FileObject>?>? images;

    // Schedule network accesses
    if (!ui.offline) {
      await Supabase.initialize(
        url: 'https://crkiyacenvzsbetbmmyg.supabase.co',
        anonKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNya2l5YWNlbnZ6c2JldGJtbXlnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDE3NzUyODMsImV4cCI6MjAxNzM1MTI4M30.dlpo_aVZ57dF_lOKd3WqW53iNycHTvG7jnz7SfszmK0',
      );
      jsons = Supabase.instance.client
          .from('jsons')
          .select('name, json')
          .timeout(aSecond * 5)
          .then((rows) => rows.map((row) =>
              MapEntry<String, dynamic>(row['name'] as String, row['json'])))
          .then((entries) => Map.fromEntries(entries));
      images = Supabase.instance.client.storage
          .from('images')
          .list(searchOptions: const SearchOptions(limit: 1 << 31 - 1));
    } else {
      jsons = null;
      images = null;
    }

    // Schedule filesystem access
    final documents = getApplicationCacheDirectory();

    // And wait for finish
    try {
      await Hive.initFlutter((await documents).path);
      print("cache at ${(await documents).path}");
    } catch (e) {
      print("Could not get cache directory, error: $e");
    }

    try {
      print("documents at ${(await getApplicationDocumentsDirectory()).path}");
    } catch (e) {
      print("Could not get documents directory, error: $e");
    }

    Map<String, dynamic>? rawJsonsCache;
    try {
      rawJsonsCache = await jsons;
    } catch (e) {
      print("Could not load jsons from network database, error: $e");
    }

    List<FileObject>? networkImagesList;
    try {
      networkImagesList = await images;
    } catch (e) {
      print("Could not load images list from network database, error: $e");
    }

    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final pkgName = packageInfo.packageName;

    bool compactAfter10(int entries, int deletedEntries) {
      return deletedEntries > 10;
    }

    Future<LazyBox<Uint8List>> cachedImages = Hive.openLazyBox(
        '${pkgName}_images',
        compactionStrategy: compactAfter10);
    Future<Box<String>> cachedUpdatedAt = Hive.openBox('${pkgName}_updated_at',
        compactionStrategy: compactAfter10);
    Future<Box<String>> cachedJsons =
        Hive.openBox('${pkgName}_jsons', compactionStrategy: compactAfter10);
    return DbCached._(await cachedImages, await cachedUpdatedAt,
        await cachedJsons, rawJsonsCache, networkImagesList);
  }

  /// Remove old cache files that are not referenced by loaded JSONs
  void collectGarbage() {
    final removeTime = DateTime.timestamp().subtract(aDay * 7);

    final imagesToClean = this
        ._cacheImages
        .keys
        .where((image) => !this._referencedFiles.contains(image))
        .map((image) => image as String)
        .toList();
    for (final image in imagesToClean) {
      final updatedAt = this._cacheUpdatedAt.get(image);
      if (updatedAt != null && DateTime.parse(updatedAt).isBefore(removeTime)) {
        this._cacheImages.delete(image);
        this._cacheUpdatedAt.delete(image);
      }
    }

    final jsonsToClean = this
        ._cacheJsons
        .keys
        .where((json) => !this._referencedFiles.contains(json))
        .map((json) => json as String)
        .toList();
    for (final json in jsonsToClean) {
      this._cacheJsons.delete(json);
    }
  }

  /// Debug-only offline mode feature to load from local filesystem
  Future<Uint8List?> openFile(String name) async {
    try {
      final documents = await getApplicationDocumentsDirectory();
      return await File(p.join(documents.path, "nemesis_helper", name))
          .readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Open JSON from network database (or from a local cache);
  /// on error will throw iff [canFail] is false
  Future<Map<String, dynamic>?> openJson(String name,
      {required bool canFail}) async {
    Map<String, dynamic>? networkJsons = this._networkJsonsCache;
    final filename = "$name.json";

    this._referencedFiles.add(filename);

    if (!kReleaseMode) {
      final bytes = await openFile(filename);
      if (bytes != null) {
        print("Loaded \"$filename\" from local filesystem");
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      }
    }

    // Load from network with fallback to local copy
    if (networkJsons == null) {
      final file = this._cacheJsons.get(filename);
      if (file == null) {
        if (canFail) return null;
        throw Exception(
            '$filename is missing from both network database and local cache');
      }
      print(
          "Loaded \"$filename\" from local cache since network connection failed");
      return jsonDecode(file) as Map<String, dynamic>;
    }

    if (!networkJsons.containsKey(name)) {
      if (canFail) return null;
      throw Exception('$filename is missing from network database');
    }

    // Cache loaded JSON locally
    final json = networkJsons[name] as Map<String, dynamic>;
    await this
        ._cacheJsons
        .put(filename, (const JsonEncoder.withIndent('\t')).convert(json));
    await this
        ._cacheUpdatedAt
        .put(filename, DateTime.timestamp().toIso8601String());

    print("Loaded \"$filename\" from network database");
    return Map<String, dynamic>.from(json);
  }

  /// Load image from network database (or from a local cache);
  /// will throw if image is not found
  Future<ImageProvider<Object>> openImage(String name, bool offline) async {
    this._referencedFiles.add(name);

    if (!kReleaseMode) {
      final bytes = await openFile(name);
      if (bytes != null) {
        print("Loaded \"$name\" from local filesystem");
        return MemoryImage(bytes);
      }
    }

    final localImage = await this._cacheImages.get(name);
    final localUpdatedAt = this._cacheUpdatedAt.get(name);
    try {
      final remoteUpdatedAt = this
          ._networkImagesList!
          .firstWhere((image) => image.name == name)
          .updatedAt;

      if (!offline &&
          (localImage == null ||
              localUpdatedAt == null ||
              remoteUpdatedAt == null ||
              localUpdatedAt != remoteUpdatedAt)) {
        final remoteImage = await Supabase.instance.client.storage
            .from('images')
            .download(name)
            .timeout(aSecond * 60);

        // Cache loaded image locally
        this._cacheImages.put(name, remoteImage);
        if (remoteUpdatedAt != null) {
          this._cacheUpdatedAt.put(name, remoteUpdatedAt);
        }

        print('Loaded "$name" from network database');
        return MemoryImage(remoteImage);
      }
    } catch (e) {
      print("Could not load $name from network, error $e");
    }

    print('Loaded "$name" from local cache');
    return MemoryImage(localImage!);
  }
}
