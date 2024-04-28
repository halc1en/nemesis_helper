import 'dart:ui';

import 'package:base85/base85.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:quiver/time.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:nemesis_helper/model/json_data.dart';
import 'package:nemesis_helper/model/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef LinkTapCallback = void Function(String);

@immutable
class Nesting {
  const Nesting() : _depth = 0;
  const Nesting._explicit(this._depth);

  /// First 3 levels are for headers and next 2 for body
  final int _depth;

  /// Cached styles for faster retrieval
  static List<TextStyle>? _styles;

  /// Cached sizes for faster retrieval
  static List<double>? _heights;

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

class TextFmtRange {
  TextFmtRange(
    this.start, {
    this.bold = false,
    this.italic = false,
    this.highlight = false,
    this.link,
    this.image,
  }) : assert(start >= 0);

  final int start;
  bool bold;
  bool italic;
  bool highlight;
  String? link;
  ParsedImage? image;

  TextFmtRange copyWith({
    int? start,
    bool? bold,
    bool? italic,
    bool? highlight,
    String? link,
    ParsedImage? image,
  }) {
    return TextFmtRange(
      start ?? this.start,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      highlight: highlight ?? this.highlight,
      link: link ?? this.link,
      image: image ?? this.image,
    );
  }

  TextFmtRange clone() {
    return this.copyWith();
  }
}

/// A helper class to calculate offset from top-level chapter to jump target
class JumpTarget {
  /// Top-level parent of jump target
  final ReferenceChapter _top;

  /// Jump target
  final ReferenceChapter _target;

  /// Index of [_top] and [_target] (the one used in [ScrollablePositionedList.builder])
  final int index;

  /// Temporary widget used to calculate offset from
  /// top parent of jump target to itself
  final Offstage offstage;

  JumpTarget({
    required ReferenceChapter top,
    required ReferenceChapter target,
    required this.index,
    required this.offstage,
  })  : _top = top,
        _target = target,
        assert(top.globalKey(true) != null),
        assert(target.globalKey(true) != null);

  double calculateOffset() {
    final topRender =
        _top.globalKey(true)?.currentContext?.findRenderObject() as RenderBox?;
    final targetRender = _target
        .globalKey(true)
        ?.currentContext
        ?.findRenderObject() as RenderBox?;
    if (topRender == null || targetRender == null) {
      print("link target is not rendered anymore!");
      return 0.0;
    }
    assert(topRender.attached && targetRender.attached);

    final topPosition = topRender.localToGlobal(Offset.zero);
    final targetPosition = targetRender.localToGlobal(Offset.zero);

    final offset = topPosition.dy - targetPosition.dy;
    print(
        "Chapter #$index has offset $offset in size ${topRender.size.height}");
    return offset;
  }
}

/// Helper class for holding additional information that goes along Jsons
class ReferenceAssets {
  ReferenceAssets(
      {required this.images,
      required this.icons,
      required SharedPreferences? sharedPreferences})
      : _sharedPreferences = sharedPreferences {
    this._collapsed = List<int>.from(codec.decode(
        sharedPreferences?.getString("reference_collapsed_chapters") ?? ""));
  }

  final codec = Base85Codec(Alphabets.z85);

  /// Images that can be referenced from text
  final Map<String, JsonImage> images;

  /// Icons that can be referenced from text
  final Map<String, JsonIcon> icons;

  final SharedPreferences? _sharedPreferences;

  /// Inefficient but Dart has neither unsigned integers nor byte integers
  late List<int> _collapsed;

  /// Set expansion state for chapter specified by [ReferenceChapter.expansionId]
  void updateExpanded(int id, bool set) {
    if (this.isExpanded(id) == set) return;

    int index = id >> 3;
    int bitmask = 1 << (id & 0x7);

    if (index >= this._collapsed.length) {
      // Round size to 4 (requirement of z85 encoding)
      int toAdd = index + 1 - this._collapsed.length;
      if (toAdd % 4 != 0) toAdd += 4 - toAdd % 4;

      // Use 0 so that by default all items will be expanded
      this._collapsed.addAll(List<int>.filled(toAdd, 0));
    }

    if (set) {
      this._collapsed[index] &= ~bitmask;
    } else {
      this._collapsed[index] |= bitmask;
    }

    Future(() async => await this._sharedPreferences?.setString(
        "reference_collapsed_chapters",
        codec.encode(Uint8List.fromList(this._collapsed))));
  }

  /// Get expansion state for chapter specified by [ReferenceChapter.expansionId]
  bool isExpanded(int id) {
    int index = id >> 3;
    int bitmask = 1 << (id & 0x7);

    return index >= this._collapsed.length ||
        (this._collapsed[index] & bitmask) == 0;
  }
}

class ReferenceChapter {
  ReferenceChapter({
    required String? text,
    required this.id,
    required this.depth,
    required this.last,
    required this.nested,
  }) {
    if (text != null) this.text = parseJsonString(text);
  }

  // This chapter's text
  String? text;

  // Nested chapters
  final List<ReferenceChapter> nested;

  /// This chapter's id (for hyperlinks to it)
  final String? id;

  // Whether this chapter is the last child of it's parent
  bool last;

  /// This chapter's global key (for hyperlinks to it)
  ///
  /// [offstage] chooses which widget to select: the one rendered
  /// for user or one hidden in the [Offstage].
  GlobalKey? globalKey(bool offstage) {
    return (offstage) ? _globalKeyOffstage : _globalKeyReal;
  }

  // ignore: prefer_final_fields
  late GlobalKey? _globalKeyReal =
      (id != null || depth.isTop()) ? GlobalKey() : null;
  // ignore: prefer_final_fields
  late GlobalKey? _globalKeyOffstage =
      (id != null || depth.isTop()) ? GlobalKey() : null;

  static int idGen = 0;
  late int expansionId = (this.depth.isCollapsible()) ? ++idGen : 0;

  /// This chapter's format without search field highlight
  final List<TextFmtRange> formatNoHighlight = [];

  /// Nesting level in JSON
  final Nesting depth;

  /// Expansion state
  void setExpanded(bool value, ReferenceAssets assets,
      {required bool offstage}) {
    if (offstage) return;

    assets.updateExpanded(this.expansionId, value);

    try {
      if (value) {
        this.expansionController(offstage)?.expand();
      } else {
        this.expansionController(offstage)?.collapse();
      }
    } catch (err) {
      if (kDebugMode) {
        print(
            'Could not ${value ? "expand" : "collapse"} ${this.text}, probably off-screen');
      }
    }
  }

  ExpansionTileController? _expansionController;
  ExpansionTileController? expansionController(bool offstage) {
    return (offstage) ? null : this._expansionController;
  }

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
  String parseJsonString(
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

              final parsedImageText = parseJsonString(m[1] ?? "",
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

              final parsedLinkText = parseJsonString(m[5] ?? "",
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

  /// Update [format] by changing highlight to passed [highlight] value
  /// starting at [cursor]
  void updateFormatWithHighlight(List<TextFmtRange> format, int cursor,
      {required bool highlight}) {
    final int prevIndex = format.lastIndexWhere((s) => s.start <= cursor);
    if (prevIndex < 0) {
      format.insert(0, TextFmtRange(cursor));
      return;
    }

    final TextFmtRange prevFmt = format[prevIndex];
    if (prevFmt.start == cursor) {
      format.replaceRange(prevIndex, prevIndex + 1,
          [prevFmt.copyWith(start: cursor, highlight: highlight)]);
      format.skip(prevIndex + 1).forEach((f) => f.highlight = highlight);
    } else {
      format.insert(
          prevIndex + 1, prevFmt.copyWith(start: cursor, highlight: highlight));
      format.skip(prevIndex + 2).forEach((f) => f.highlight = highlight);
    }
  }

  Widget _scaledImage(BuildContext context, TextFmtRange fmt,
      String imageString, ImageProvider provider, TextStyle errorStyle) {
    // Determine image size based on actual screen size
    final screenSize = MediaQuery.sizeOf(context);
    final imageWidth = fmt.image!.widthLogical ?? screenSize.width;

    return Image(
      errorBuilder: (context, err, _) {
        return Text("Error loading ${imageString.substring(1)}: $err",
            style: errorStyle);
      },
      image: ResizeImage(
        provider,
        policy: ResizeImagePolicy.fit,
        allowUpscaling: false,
        width: imageWidth.round(),
        height: screenSize.height.round(),
      ),
      filterQuality: FilterQuality.medium,
      fit: BoxFit.contain,
    );
  }

  /// Render a single part of [ReferenceChapter.text] that has the same formatting [fmt];
  /// this is a building block of rendering [ReferenceChapter.text]
  InlineSpan _renderSingleSpan(
      BuildContext context,
      String text,
      TextStyle? styleOverride,
      TextFmtRange fmt,
      ReferenceAssets assets,
      LinkTapCallback? onLinkTap) {
    final highlightColor = this.depth.highlightColor(context);
    final textStyle = styleOverride ??
        this.depth.textStyle(context).copyWith(
            fontWeight: fmt.bold ? FontWeight.bold : null,
            fontStyle: fmt.italic ? FontStyle.italic : null,
            backgroundColor: fmt.highlight ? highlightColor : null);

    // Paint image if needed
    Widget? imageWidget;
    final imageString = fmt.image?.link;
    if (imageString != null) {
      final errorStyle = TextStyle(color: Theme.of(context).colorScheme.error);
      final jsonImage = assets.images[imageString.substring(1)];
      final jsonIcon = assets.icons[imageString.substring(1)];

      if (jsonImage != null) {
        final provider = jsonImage.provider;
        imageWidget = (provider != null)
            ? _scaledImage(context, fmt, imageString, provider, errorStyle)
            : FutureBuilder(
                future: jsonImage.providerFuture,
                builder: (context, snapshot) {
                  final provider = snapshot.data;
                  if (provider == null) {
                    if (snapshot.hasError) {
                      return Text(
                          "Error loading ${imageString.substring(1)} provider: ${snapshot.error}",
                          style: errorStyle);
                    }
                    return const SizedBox.shrink();
                  }

                  return _scaledImage(
                      context, fmt, imageString, provider, errorStyle);
                },
              );
      } else if (jsonIcon != null) {
        imageWidget = Image(
          errorBuilder: (context, err, _) {
            return Text("Error loading ${imageString.substring(1)}: $err",
                style: errorStyle);
          },
          image: jsonIcon.provider,
          filterQuality: FilterQuality.medium,
          height: this.depth.textHeight(context, styleOverride),
        );
      } else {
        imageWidget = Text(
            '"${imageString.substring(1)}" is not defined in JSON',
            style: errorStyle);
      }
    }

    return switch ((imageWidget, fmt.link)) {
      (null, null) => TextSpan(text: text, style: styleOverride ?? textStyle),
      (Widget image, null) => WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: image,
        ),
      (Widget? image, String link) => WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          // Capture finger taps/mouse clicks
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: (onLinkTap != null) ? () async => onLinkTap(link) : null,
              child: (image != null)
                  ? image
                  : Text.rich(
                      TextSpan(
                        text: text,
                        style: (styleOverride ?? textStyle).copyWith(
                          color: Colors.lightBlue,
                          // Use hyperlink style
                          decorationColor: Colors.lightBlue,
                          decoration: TextDecoration.underline,
                          decorationThickness: 1.5,
                        ),
                      ),
                      // Workaround for https://github.com/flutter/flutter/issues/126962
                      textScaler: TextScaler.noScaling,
                    ),
            ),
          ),
        ),
    };
  }

  /// Renders [ReferenceChapter.text] while taking into account:
  ///  - highlighting [regex] matches
  ///  - formatting according to [ReferenceChapter.format]
  ///
  /// Returns rendered [Widget] and whether [regex] matches it
  (Widget, bool) renderText(BuildContext context, RegExp? regex,
      ReferenceAssets assets, LinkTapCallback? onLinkTap, GlobalKey? key,
      {TextStyle? styleOverride, String? tocPrefix}) {
    // Render top-level headers in uppercase when not in table of contents
    final text = (tocPrefix == null && this.depth.isTop())
        ? this.text?.toUpperCase()
        : this.text;

    // Shortcut for the simplest cases of plain text or no text
    if (text == null) return (const SizedBox.shrink(), false);
    if (regex == null && this.formatNoHighlight.isEmpty) {
      final widget = Container(
        alignment: Alignment.centerLeft,
        padding: this.depth.indentation(),
        child: Text(
          // Also add specified table of contents prefix
          "${tocPrefix ?? ''}$text",
          key: key,
          style: styleOverride ?? this.depth.textStyle(context),
        ),
      );
      return (widget, false);
    }

    // Create a local copy of formatting and add all search matches to it
    final List<TextFmtRange> format = [];
    if ((this.formatNoHighlight.firstOrNull?.start ?? 1) > 0) {
      format.add(TextFmtRange(0));
    }
    format.addAll(this.formatNoHighlight.map((fmt) => fmt.clone()));
    if (format.last.start < text.length) {
      format.add(TextFmtRange(text.length));
    }

    bool matches = false;
    if (regex != null) {
      int cursor = 0;
      text.splitMapJoin(regex, onMatch: (m) {
        matches = true;
        updateFormatWithHighlight(format, cursor, highlight: true);
        cursor = m.end;
        return "";
      }, onNonMatch: (n) {
        updateFormatWithHighlight(format, cursor, highlight: false);
        cursor += n.length;
        return "";
      });
    }

    // And render requested format using [TextSpan] and [WidgetSpan]
    final spans = <InlineSpan>[];
    final spansLeft = <InlineSpan>[];
    final spansRight = <InlineSpan>[];

    if (tocPrefix != null) {
      spans.add(TextSpan(
          text: tocPrefix,
          style: styleOverride ?? this.depth.textStyle(context)));
    }

    TextFmtRange fmt = format.first;
    for (final nextFmt in format.skip(1)) {
      final span = _renderSingleSpan(
          context,
          text.substring(fmt.start, nextFmt.start),
          styleOverride,
          fmt,
          assets,
          onLinkTap);

      // Take "float" image attribute into account
      switch (fmt.image?.float) {
        case ImageFloat.left:
          spansLeft.add(span);
          break;
        case ImageFloat.right:
          spansRight.add(span);
          break;
        default:
          spans.add(span);
          break;
      }
      fmt = nextFmt;
    }

    Widget widget = Text.rich(key: key, TextSpan(children: spans));

    if (spansLeft.isNotEmpty || spansRight.isNotEmpty) {
      widget = Row(children: [
        if (spansLeft.isNotEmpty) Text.rich(TextSpan(children: spansLeft)),
        Expanded(child: widget),
        if (spansRight.isNotEmpty) Text.rich(TextSpan(children: spansRight)),
      ]);
    }

    widget = Container(
      key: key,
      alignment: Alignment.centerLeft,
      padding: this.depth.indentation(),
      child: widget,
    );
    return (widget, matches);
  }

  /// Render this chapter together with it's children as widget
  ///
  /// Set [offstage] to build yet another instance of the widget; useful
  /// for calculating dimensions when jumping through links.
  (Widget, bool) renderChapter(BuildContext context, RegExp? regex,
      bool forceExpandCollapse, ReferenceAssets assets,
      {required bool offstage, required LinkTapCallback? onLinkTap}) {
    final List<Widget> nestedWidgets;
    bool nestedMatches;

    // Recursively walk children
    (nestedWidgets, nestedMatches) = this
        .nested
        .map((ReferenceChapter child) => child.renderChapter(
            context, regex, forceExpandCollapse, assets,
            offstage: offstage, onLinkTap: onLinkTap))
        .fold<(List<Widget>, bool)>(([], false), (prev, element) {
      return (prev.$1..add(element.$1), prev.$2 || element.$2);
    });

    final (widget, thisMatches) = (this.text != null)
        ? renderText(context, regex, assets, onLinkTap, null)
        : (null, false);

    // Make sure that all [ScrollablePositionedList] children have
    // global key.  It's necessary to avoid needless full rebuilds
    // (including state!!) for it's jumpTo() method.
    final globalKey = this.globalKey(offstage);
    switch ((
      widget,
      nestedWidgets.isEmpty ? null : nestedWidgets,
      this.depth.isCollapsible()
    )) {
      case (Widget widget, List<Widget> nestedWidgets, true):
        // Force expanding and collapsing when user changes search field
        // and do nothing otherwise
        final forcedExpansion = nestedMatches || thisMatches;
        if (forceExpandCollapse) {
          this.setExpanded(forcedExpansion, assets, offstage: offstage);
        }
        if (!offstage) {
          this._expansionController ??= ExpansionTileController();
        }

        return (
          ExpansionTile(
            key: globalKey,
            controller: this.expansionController(offstage),
            // To make sure children widgets are always available for offset
            // calculation and expansion (it's easier this way than expanding
            // all nested [ExpansionTile]s frame-by-frame through callbacks
            // when searching for jump target's position)
            maintainState: true,
            onExpansionChanged: (value) =>
                assets.updateExpanded(this.expansionId, value),
            initiallyExpanded: assets.isExpanded(this.expansionId),
            title: widget,
            children: nestedWidgets,
          ),
          nestedMatches || thisMatches
        );
      case (Widget widget, List<Widget> nestedWidgets, false):
        return (
          Column(key: globalKey, children: [widget, ...nestedWidgets]),
          nestedMatches || thisMatches
        );
      case (Widget widget, null, _):
        // Use simple [Text] if possible
        return (
          (globalKey == null)
              ? widget
              : SizedBox(key: globalKey, child: widget),
          thisMatches,
        );
      case (null, List<Widget> nestedWidgets, _):
        // [ExpansionTile] by definition requires some text in header
        // so use simple [Column] instead
        final Widget chapter;
        switch ((nestedWidgets.length, globalKey)) {
          case (1, null):
            chapter = nestedWidgets.first;
          case (1, GlobalKey _):
            chapter = SizedBox(key: globalKey, child: nestedWidgets.first);
          case _:
            chapter = Column(key: globalKey, children: [...nestedWidgets]);
        }
        return (chapter, nestedMatches);
      case (null, null, _):
        return (SizedBox.shrink(key: globalKey), false);
    }

    // Silence the compiler
    throw Exception("Unhandled case in chapter rendering");
  }

  /// Jump or scroll to this chapter if it matches [chapterId].
  /// Set [parentContext] to closest rendered parent chapter of
  /// this one; if not null then we can just scroll to target.
  ///
  /// Returns whether this chapter (including children) matches
  /// and optional [JumpTarget] instance if target isn't rendered
  /// yet.
  (bool, JumpTarget?) jumpToChapter(
    BuildContext context,
    int index,
    bool useScroll,
    String chapterId,
    List<ReferenceChapter> parents,
    RegExp? regex,
    ReferenceAssets assets,
  ) {
    bool thisMatches = (this.id == chapterId.substring(1));
    final chaptersList = parents.toList()..add(this);

    final (bool nestedMatches, JumpTarget? jumpTarget) = this
            .nested
            .map((chapter) => chapter.jumpToChapter(context, index, useScroll,
                chapterId, chaptersList, regex, assets))
            .where((value) => value.$1)
            .firstOrNull ??
        (false, null);

    print(
        "Searching for $chapterId at nesting ${this.depth._depth}, this: $thisMatches, nested: $nestedMatches, text: $text, ${(this.globalKey(false)?.currentContext == null) ? 'null context' : 'has context'}");

    if (!thisMatches && !nestedMatches) {
      return (false, null);
    }

    if (!thisMatches) {
      return (true, jumpTarget);
    }

    // Jump to target!

    // Expand all parents of jump target and target itself...
    for (final chapter in chaptersList) {
      chapter.setExpanded(true, assets, offstage: false);
    }

    // Easy path: target is rendered already so we can just scroll to it.
    var thisContext = this.globalKey(false)?.currentContext;
    final thisRender = thisContext?.findRenderObject() as RenderBox?;

    if (thisRender != null && useScroll) {
      print(
          "Found target in viewport at offset ${thisRender.localToGlobal(Offset.zero).dy}, scrolling");

      // Wait for for parents' expand() to finish (200 ms is default
      // expansion time) while scrolling to target's parents, and
      // then scroll to the target.
      for (var i = 0; i <= 300; i += 50) {
        Future.delayed(aMillisecond * i, () {
          final targetContext = chaptersList.reversed
              .map((chapter) => chapter.globalKey(false)?.currentContext)
              .firstOrNull;
          if (targetContext != null) {
            Scrollable.ensureVisible(
              targetContext,
              curve: Curves.linear,
              duration: aMillisecond * 100,
            );
          }
        });
      }

      return (true, null);
    }

    // Hard path: calculate proper position for jump and schedule it
    final topChapter = chaptersList.first;
    return (
      true,
      JumpTarget(
        top: topChapter,
        target: this,
        index: index,
        offstage: Offstage(
          child: topChapter
              .renderChapter(context, regex, true, assets,
                  offstage: true, onLinkTap: null)
              .$1,
        ),
      )
    );
  }

  factory ReferenceChapter.fromJson(
      Nesting depth, bool last, Map<String, dynamic> json) {
    final jsonText = json['text'];
    final nestedJson = json['nested'] as List<dynamic>?;

    final nested = nestedJson?.indexed
            .map((child) => ReferenceChapter.fromJson(
                depth.next(),
                child.$1 + 1 == nestedJson.length,
                child.$2 as Map<String, dynamic>))
            .toList() ??
        [];

    return ReferenceChapter(
      text: (jsonText is List) ? jsonText.join('\n') : (jsonText as String?),
      id: json['id'] as String?,
      depth: depth,
      last: last,
      nested: nested,
    );
  }
}

@immutable
class ReferenceData {
  final List<ReferenceChapter> nested;

  final ReferenceAssets assets;

  const ReferenceData({required this.nested, required this.assets});

  List<Widget> show(
      BuildContext context, RegExp? regex, bool forceExpandCollapse,
      {required LinkTapCallback onLinkTap}) {
    return this
        .nested
        .map((child) => child
            .renderChapter(context, regex, forceExpandCollapse, this.assets,
                offstage: false, onLinkTap: onLinkTap)
            .$1)
        .toList();
  }

  JumpTarget? jumpToChapter(
      BuildContext context, int currentIndex, String chapterId, RegExp? regex) {
    return nested.indexed
        .map((val) {
          final (index, chapter) = val;
          return chapter.jumpToChapter(
            context,
            index,
            // Seems that ensureVisible() does not work will with
            // [ExpansionTile] so use jumps instead of scrolling
            false,
            chapterId,
            [],
            regex,
            this.assets,
          );
        })
        .where((ret) => ret.$1)
        .firstOrNull
        ?.$2;
  }

  factory ReferenceData.fromJson(
      Map<String, dynamic> json,
      Map<String, JsonImage> images,
      Map<String, JsonIcon> icons,
      SharedPreferences? sharedPreferences) {
    var nestedJson = json['reference'] as List<dynamic>? ?? [];

    var nested = nestedJson.indexed
        .map<ReferenceChapter>((child) => ReferenceChapter.fromJson(
            const Nesting(),
            child.$1 + 1 == nestedJson.length,
            child.$2 as Map<String, dynamic>))
        .toList();

    return ReferenceData(
        nested: nested,
        assets: ReferenceAssets(
            images: images,
            icons: icons,
            sharedPreferences: sharedPreferences));
  }
}

class Reference extends StatefulWidget {
  const Reference({super.key, required this.ui, required this.reference});

  final UISettings ui;
  final ReferenceData? reference;

  @override
  State<Reference> createState() => _ReferenceState();
}

class _ReferenceState extends State<Reference>
    with
        AutomaticKeepAliveClientMixin<Reference>,
        SingleTickerProviderStateMixin {
  /// Saved state for when app is closed
  late TextEditingController _searchController;
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();

  RegExp? _regex;
  bool _forceExpandCollapse = false;

  final _listKey = GlobalKey();

  /// Clicked link's target useful for calculating it's dimensions
  Offstage? _offstage;

  // For overall smoothness
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    final lastSearch =
        widget.ui.sharedPreferences?.getString("reference_search_field");
    this._searchController = TextEditingController(text: lastSearch);
    this._searchController.addListener(_searchFieldListener);
    if (lastSearch != null) onSearchChange(lastSearch);

    this
        ._itemPositionsListener
        .itemPositions
        .addListener(_itemPositionListener);

    super.initState();
  }

  @override
  void dispose() {
    super.dispose();

    this._searchController.dispose();
    this
        ._itemPositionsListener
        .itemPositions
        .removeListener(_itemPositionListener);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final ref = widget.reference;
    if (ref == null) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);

    final forceExpandCollapse = this._forceExpandCollapse;
    this._forceExpandCollapse = false;

    double initialAlignment =
        widget.ui.sharedPreferences?.getDouble("reference_scroll_alignment") ??
            0.0;
    int initialIndex =
        widget.ui.sharedPreferences?.getInt("reference_scroll_index") ?? 0;
    if (initialIndex >= ref.nested.length) {
      initialIndex = 0;
      initialAlignment = 0.0;
    }

    return Column(
      children: [
        if (this._offstage != null) this._offstage!,
        Row(
          children: [
            // Table of contents
            PopupMenuButton<int>(
              tooltip: AppLocalizations.of(context).tableOfContents,
              icon: const Icon(Icons.menu_book),
              iconColor: theme.colorScheme.secondary,
              onSelected: (int index) {
                this._itemScrollController.jumpTo(index: index, alignment: 0.0);
              },
              itemBuilder: (BuildContext context) {
                var shownChapters =
                    this._itemPositionsListener.itemPositions.value;
                final (firstShown, lastShown) = (
                  shownChapters.firstOrNull?.index,
                  shownChapters.lastOrNull?.index
                );
                final textStyle = Theme.of(context).textTheme.titleMedium!;

                return ref.nested.indexed.map((topChapter) {
                  final index = topChapter.$1;
                  final bool isOnScreen = (firstShown != null &&
                      lastShown != null &&
                      index >= firstShown &&
                      index <= lastShown);

                  return PopupMenuItem<int>(
                    padding: const EdgeInsets.symmetric(vertical: 0.0),
                    value: index,
                    child: topChapter.$2
                        .renderText(context, null, ref.assets, null, null,
                            tocPrefix: "${index + 1}. ",
                            styleOverride: !isOnScreen
                                ? textStyle
                                : textStyle.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary))
                        .$1,
                  );
                }).toList();
              },
            ),

            const VerticalDivider(thickness: 1.5, endIndent: 0.0, width: 1.5),

            // Search field
            Expanded(
              child: TextField(
                controller: this._searchController,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).searchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed: () {
                      this._searchController.clear();
                      setState(() {
                        this._regex = null;
                      });
                    },
                    icon: const Icon(Icons.clear),
                  ),
                ),
                onChanged: (value) {
                  onSearchChange(value);
                },
              ),
            ),
          ],
        ),
        Expanded(
          child: ScrollbarTheme(
            data: const ScrollbarThemeData(
                interactive: false, radius: Radius.zero),
            child: ScrollablePositionedList.builder(
              key: this._listKey,
              initialScrollIndex: initialIndex,
              initialAlignment: initialAlignment,
              itemScrollController: this._itemScrollController,
              itemPositionsListener: this._itemPositionsListener,
              itemCount: ref.nested.length,
              itemBuilder: (context, index) {
                return ref.nested[index].renderChapter(
                  context,
                  this._regex,
                  forceExpandCollapse,
                  ref.assets,
                  offstage: false,
                  onLinkTap: (String jumpTo) {
                    final jumpTarget = widget.reference
                        ?.jumpToChapter(context, index, jumpTo, this._regex);

                    if (jumpTarget != null) {
                      setState(() {
                        this._offstage = jumpTarget.offstage;
                      });
                      SchedulerBinding.instance.addPostFrameCallback((_) {
                        final offset = jumpTarget.calculateOffset();
                        setState(() {
                          this._offstage = null;
                        });

                        final listHeight = (this
                                ._listKey
                                .currentContext
                                ?.findRenderObject() as RenderBox?)
                            ?.size
                            .height;

                        if (listHeight != null) {
                          // Do not use [ScrollablePositionedList.scrollTo],
                          // it is broken when list has [ExpansionTile]
                          this._itemScrollController.jumpTo(
                              index: jumpTarget.index,
                              alignment: offset / listHeight);
                        }
                      });
                    }
                  },
                ).$1;
              },
            ),
          ),
        ),
      ],
    );
  }

  void _searchFieldListener() {
    widget.ui.sharedPreferences
        ?.setString("reference_search_field", this._searchController.text);
  }

  void _itemPositionListener() {
    final firstItem =
        this._itemPositionsListener.itemPositions.value.firstOrNull;
    widget.ui.sharedPreferences
        ?.setInt("reference_scroll_index", firstItem?.index ?? 0);
    widget.ui.sharedPreferences?.setDouble(
        "reference_scroll_alignment", firstItem?.itemLeadingEdge ?? 0.0);
  }

  void onSearchChange(String value) {
    if (value.isNotEmpty) {
      try {
        setState(() {
          this._forceExpandCollapse = true;
          this._regex = RegExp(value,
              caseSensitive: false,
              unicode: true,
              multiLine: true,
              dotAll: true);
        });
      } catch (_) {}
    } else if (this._regex != null) {
      setState(() {
        this._regex = null;
      });
    }
  }
}
