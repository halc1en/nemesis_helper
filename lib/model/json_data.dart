// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import 'package:nemesis_helper/model/settings.dart';
import 'package:nemesis_helper/ui/ui_widget_json_id.dart';
import 'package:nemesis_helper/ui/ui_widget.dart';

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
    required this.tabs,
  });

  /// Selected language
  final String currentLanguage;

  /// Supported languages (in database, not in Flutter interface)
  final List<String> supportedLanguages;

  /// Modules available for selection
  final List<Module> selectableModules;

  /// Reference to show
  final ReferenceData reference;

  /// Loaded tabs
  final List<JsonTab> tabs;

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
  /// from object [id].  This object must exist.
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
    //
    // Here and below create local copies from JSON so that it can be freed
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
    for (final (path, id) in (mainJson['icons'] as List<dynamic>? ?? [])
        .map((icon) => icon as Map<String, dynamic>)
        .nonNulls
        .map((icon) => (icon['path'] as String, icon['id'] as String))) {
      final provider = await openImage(path, offline);
      if (provider == null) continue;
      if (context.mounted) {
        precacheImage(provider, context, size: const Size.square(64.0));
      }
      icons.addAll({
        id: JsonIcon(
          provider: ResizeImage(provider, width: 64, height: 64),
          path: path,
        )
      });
    }

    final images = <String, JsonImage>{};
    for (final (path, id) in (mainJson['images'] as List<dynamic>? ?? [])
        .map((image) => image as Map<String, dynamic>)
        .nonNulls
        .map((image) => (image['path'] as String, image['id'] as String))) {
      images.addAll({
        id: JsonImage(providerFuture: openImage(path, offline), path: path)
      });
    }

    // Parse the resulting JSON
    final reference = ReferenceData.fromJson(mainJson, images, icons);

    // Get list of tabs
    final tabsNames = (mainJson['tabs_names'] as List<dynamic>? ?? [])
        .map((e) => e as String)
        .toList();
    final tabs = <JsonTab>[];
    for (final (index, tab) in (mainJson['tabs'] as List<dynamic>? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .indexed) {
      final icon = tab['icon'] as String?;
      final iconMaterialName = tab['icon_material'] as String?;

      tabs.add(JsonTab(
        index: index,
        name: tabsNames[index],
        icon: (icon != null) ? icons[icon] : null,
        iconMaterial: (iconMaterialName != null)
            ? MdiIcons.fromString(_toCamelCase(iconMaterialName))
            : null,
        widget:
            UIWidget.fromJson(tab['widget'] as Map<String, dynamic>, reference),
      ));
    }
    if (tabs.isEmpty) throw Exception("No tabs specified");

    return JsonData(
        currentLanguage: language,
        supportedLanguages: supportedLanguages,
        selectableModules: selectableModules,
        reference: reference,
        images: images,
        tabs: tabs);
  }
}

String _toCamelCase(String text) {
  if (text.isEmpty) return "";

  // Split the string by underscores
  List<String> words = text.split(RegExp(r'_|-'));

  // Capitalize the first letter of each word except the first one
  return [
    words.first,
    ...words
        .skip(1)
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1))
  ].join();
}

class JsonImage {
  JsonImage({
    required Future<ImageProvider?> providerFuture,
    required this.path,
  }) {
    this.providerFuture =
        providerFuture.then((provider) => this.provider = provider);
  }

  /// Provider to load the image
  late Future<ImageProvider?> providerFuture;

  /// Set after the image is loaded
  ImageProvider? provider;

  /// Path in storage
  final String path;
}

@immutable
class JsonIcon {
  const JsonIcon({
    required this.provider,
    required this.path,
  });

  /// Provider to load the icon.  Icons are small
  /// so there is no real need in [Future].
  final ImageProvider provider;

  /// Path in JSON
  final String path;
}

@immutable
class JsonTab {
  const JsonTab({
    required this.index,
    required this.name,
    this.iconMaterial,
    this.icon,
    required this.widget,
  });

  /// Tab position
  final int index;

  /// Localized tab name
  final String name;

  /// [JsonIcon] to show on tab
  final JsonIcon? icon;

  /// Or can use icon name from Material spec:
  /// https://pictogrammers.com/library/mdi/
  final IconData? iconMaterial;

  /// Tab content
  final UIWidget widget;
}

class ReferenceChapter {
  ReferenceChapter({
    required String? text,
    required this.id,
    required this.depth,
    required this.nested,
  }) {
    this.text = (text != null) ? _parseJsonString(text) : null;
  }

  factory ReferenceChapter.notFoundChapter(String? id) => ReferenceChapter(
        text: 'Chapter "$id" not found in JSON',
        id: null,
        depth: const Nesting(),
        nested: [],
      );

  // This chapter's text
  late String? text;

  // Nested chapters
  final List<ReferenceChapter> nested;

  /// This chapter's id (for hyperlinks to it)
  final String? id;

  /// This chapter's format without search field highlight
  final List<TextFmtRange> formatNoHighlight = [];

  /// Nesting level in JSON
  final Nesting depth;

  /// This chapter's global key (for hyperlinks to it)
  ///
  /// [offstage] chooses which widget to select: the one rendered
  /// for user or one hidden in the [Offstage].
  GlobalKey? globalKey(bool offstage, String uiWidget) =>
      (offstage) ? _globalKeyOffstage[uiWidget] : _globalKey[uiWidget];

  final Map<String, GlobalKey> _globalKey = {};
  final Map<String, GlobalKey> _globalKeyOffstage = {};

  ExpansionTileController? expansionController(String uiWidget) =>
      this._expansionControllers[uiWidget];
  final Map<String, ExpansionTileController> _expansionControllers = {};

  int? expansionId(String uiWidget) => this._expansionId[uiWidget];
  final Map<String, int> _expansionId = {};

  /// Create keys and controllers for specified widget
  /// in this chapter and it's children
  void _prepareWidget(String uiWidget, IdGen generator) {
    if (this.isJumpTarget()) {
      this._globalKey[uiWidget] = GlobalKey();
      this._globalKeyOffstage[uiWidget] = GlobalKey();
    }
    if (this.depth.isCollapsible()) {
      this._expansionControllers[uiWidget] = ExpansionTileController();
      this._expansionId[uiWidget] = generator.get();
    }

    for (final chapter in this.nested) {
      chapter._prepareWidget(uiWidget, generator);
    }
  }

  /// Whether this chapter can be a jump target.  Only jump targets
  /// need a [globalKey] for calculating their position on screen.
  bool isJumpTarget() => id != null || depth.isTop();

  static final RegExp formattingRegex = RegExp(
    // Escaping special characters
    r'\\\*|\\\]|\\\[|\\!'
    r'|'
    // Inline images and icons
    r'!\[(.*?[^\\]?)\]\((.+?)\)(\{(.+?)\})?'
    r'|'
    // Links
    r'\[(.*?[^\\])\]\((.+?)\)'
    r'|'
    // Bold and italic
    r'\*\*|\*',
    unicode: true,
  );

  /// Parse [text] and return the resulting string.
  /// Save all found formatting hints to [formatNoHighlight]
  /// Special characters:
  ///  **bold text**
  ///  *italic text*
  ///  [link text](link URL)
  String _parseJsonString(
    String text, {
    int cursor = 0,
    bool bold = false,
    bool italic = false,
    String? link,
    ParsedImage? image,
  }) {
    void saveFormatting() {
      this.formatNoHighlight.add(TextFmtRange(cursor,
          bold: bold, italic: italic, link: link, image: image));
    }

    return text.splitMapJoin(ReferenceChapter.formattingRegex, onMatch: (m) {
      switch (m[0]) {
        case r"\*":
        case r"\]":
        case r"\[":
        case r"\!":
          /* Escaped special symbol *[]! */
          cursor += 1;
          return m[0]![1];
        case "**":
          bold = !bold;
          saveFormatting();
          return "";
        case "*":
          italic = !italic;
          saveFormatting();
          return "";
        default:
          switch (m[0]![0]) {
            case "!":
              /* Inline image: ![text for searching](URL){ optional=attributes } */
              image = ParsedImage(link: m[2], attributes: m[4]);
              saveFormatting();

              final parsedImageText = _parseJsonString(m[1] ?? "",
                  cursor: cursor,
                  bold: bold,
                  italic: italic,
                  link: link,
                  image: image);

              cursor += parsedImageText.length;
              image = null;
              saveFormatting();

              return parsedImageText;
            case "[":
              /* Link: [link text](URL) */
              link = m[6];
              saveFormatting();

              final parsedLinkText = _parseJsonString(m[5] ?? "",
                  cursor: cursor,
                  bold: bold,
                  italic: italic,
                  link: link,
                  image: image);

              cursor += parsedLinkText.length;
              link = null;
              saveFormatting();

              return parsedLinkText;
            default:
              assert(false);
              return "";
          }
      }
    }, onNonMatch: (n) {
      cursor += n.length;
      return n;
    });
  }

  ReferenceChapter? _findById(String id, {List<ReferenceChapter>? parents}) {
    if (this.id == id) return this;

    parents?.add(this);
    final chapter = this
        .nested
        .map((chapter) => chapter._findById(id, parents: parents))
        .nonNulls
        .firstOrNull;
    if (chapter == null) parents?.removeLast();
    return chapter;
  }

  factory ReferenceChapter._fromJson(Nesting depth, Map<String, dynamic> json) {
    final jsonText = json['text'];
    final nestedJson = json['nested'] as List<dynamic>?;

    final nested = nestedJson
            ?.map((child) => ReferenceChapter._fromJson(
                depth.next(), child as Map<String, dynamic>))
            .toList() ??
        [];

    return ReferenceChapter(
      text: (jsonText is List) ? jsonText.join('\n') : (jsonText as String?),
      id: json['id'] as String?,
      depth: depth,
      nested: nested,
    );
  }
}

@immutable
class Nesting {
  // The top-most level -1 is special, only tabs can specify it
  const Nesting() : _depth = -1;
  const Nesting._explicit(this._depth);

  /// First 3 levels are for headers and next 2 for body
  final int _depth;

  /// Cached styles for faster retrieval
  static List<TextStyle>? _styles;

  /// Cached sizes for faster retrieval
  static List<double>? _heights;

  /// Is this tab?
  bool isTab() => this._depth == -1;

  /// Most top-level chapter?
  bool isTop() => this._depth == 0;

  /// Headers do not take part in multi-paragraph search
  bool isHeader() => this._depth <= 2;

  /// Comments explain previous paragraph clearer and should be indented
  bool isComment() => this._depth >= 4;

  /// First two levels use [ExpansionTile] and can be collapsed
  bool isCollapsible() => this._depth <= 1;

  /// Is rendered as [InlineSpan] (as opposed to [Widget]).
  /// First two levels use [ExpansionTile] for collapsing
  /// and the last level uses [Container] for padding.
  bool isSpan() => !isCollapsible() && !isComment();

  Nesting next() => Nesting._explicit(this._depth + 1);

  EdgeInsets indentation() {
    if (this.isComment()) return const EdgeInsets.only(left: 24, right: 4);
    if (!this.isCollapsible()) return const EdgeInsets.only(left: 12, right: 4);
    return const EdgeInsets.symmetric(horizontal: 4);
  }

  /// Get text style for each of 0 to 4 allowed nesting depths in JSON
  TextStyle textStyle(BuildContext context) {
    _initStyles(context);
    return Nesting._styles![this._depth.clamp(0, Nesting._styles!.length - 1)];
  }

  double textHeight(BuildContext context, TextStyle? styleOverride) {
    // Cannot use cached value if custom style is requested
    if (styleOverride != null) {
      return (TextPainter(
        text: TextSpan(text: "T", style: styleOverride),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout())
          .size
          .height;
    }

    // Get height from cache
    if (Nesting._heights == null) {
      _initStyles(context);
      Nesting._heights = Nesting._styles!
          .map((depthStyle) => TextPainter(
                text: TextSpan(text: "T", style: depthStyle),
                maxLines: 1,
                textDirection: TextDirection.ltr,
              ))
          .map((painter) => (painter..layout()).size.height)
          .toList();
    }

    return Nesting
        ._heights![this._depth.clamp(0, Nesting._heights!.length - 1)];
  }

  Color? highlightColor(BuildContext context) {
    final nestingStyle = this.textStyle(context);
    return Color.lerp(
        nestingStyle.color ??
            nestingStyle.foreground?.color ??
            Theme.of(context).colorScheme.background,
        Colors.black,
        0.6);
  }

  void _initStyles(BuildContext context) {
    if (Nesting._styles == null) {
      final textTheme = Theme.of(context).textTheme;
      // These can't be null since they are explicitly initialized
      // in MaterialApp.textTheme
      final labelMedium = textTheme.labelMedium!;
      Nesting._styles = [
        textTheme.headlineMedium!.copyWith(
            shadows: [Shadow(color: Colors.blue.shade200, blurRadius: 10)],
            letterSpacing: -0.7,
            height: 1),
        textTheme.titleLarge!.copyWith(
            decoration: TextDecoration.underline,
            shadows: [Shadow(color: Colors.blue.shade400, blurRadius: 5)],
            height: 1),
        textTheme.bodyLarge!.copyWith(
            color: Colors.blue.shade400,
            shadows: [Shadow(color: Colors.blue.shade600, blurRadius: 2)]),
        textTheme.bodyMedium!.copyWith(color: Colors.blue.shade50),
        labelMedium.copyWith(
            color: Color.lerp(labelMedium.color, Colors.black, 0.2),
            fontStyle: FontStyle.italic,
            fontSize: labelMedium.fontSize! * 1.1),
      ];
    }
  }

  @override
  String toString() => '$_depth';
}

class IdGen {
  int _unusedId = 0;

  int get() => _unusedId++;
}

@immutable
class ReferenceData {
  final List<ReferenceChapter> nested;

  final ReferenceAssets assets;

  const ReferenceData({required this.nested, required this.assets});

  /// Create keys and controllers for specified widget
  void prepareWidget(String uiWidget, List<ReferenceChapter> chapters) {
    final idGen = IdGen();
    for (final chapter in chapters) {
      chapter._prepareWidget(uiWidget, idGen);
    }
  }

  factory ReferenceData.fromJson(
    Map<String, dynamic> json,
    Map<String, JsonImage> images,
    Map<String, JsonIcon> icons,
  ) {
    var nestedJson = json['reference'] as List<dynamic>? ?? [];

    var nested = nestedJson
        .map<ReferenceChapter>((child) => ReferenceChapter._fromJson(
            const Nesting(), child as Map<String, dynamic>))
        .toList();

    return ReferenceData(
        nested: nested, assets: ReferenceAssets(images: images, icons: icons));
  }

  /// Find chapter with specified [id].  If [parents] is not null then all
  /// parents of the target chapter will be returned there.
  ReferenceChapter findChapterById(String id,
      {List<ReferenceChapter>? parents}) {
    final chapter = this
        .nested
        .map((chapter) => chapter._findById(id, parents: parents))
        .nonNulls
        .firstOrNull;

    if (chapter == null) {
      return ReferenceChapter.notFoundChapter(id);
    }

    return chapter;
  }
}

/// Helper class for holding additional information that goes along Jsons
class ReferenceAssets {
  ReferenceAssets({required this.images, required this.icons});

  /// Images that can be referenced from text
  final Map<String, JsonImage> images;

  /// Icons that can be referenced from text
  final Map<String, JsonIcon> icons;
}

enum ImageFloat {
  none,
  left,
  right,
}

class ParsedImage {
  /// Link text as specified in JSON
  final String? link;

  /// Whether to float this image to left/right of text after it
  ImageFloat float;

  /// Requested width of this image in logical pixels
  int? widthLogical;

  static final RegExp formattingRegex = RegExp(
    // Width in millimeters
    r'(width)=(\d+)'
    r'|'
    // Float to left or right
    r'(float)=(left|right)',
    unicode: true,
  );

  ParsedImage({this.link, String? attributes})
      : this.float = ImageFloat.none,
        this.widthLogical = null {
    if (attributes == null) return;

    for (final Match m in formattingRegex.allMatches(attributes)) {
      if (m[1] == "width") {
        final widthMm = int.tryParse(m[2]!);
        if (widthMm != null) {
          this.widthLogical = 38 * widthMm ~/ 10;
        }
      } else if (m[3] == "float") {
        this.float = m[4] == "left" ? ImageFloat.left : ImageFloat.right;
      } else {
        print("Not matched: ${m[0]}");
      }
    }
  }
}
