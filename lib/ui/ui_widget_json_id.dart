// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:base85/base85.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:quiver/time.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:nemesis_helper/model/json_data.dart';
import 'package:nemesis_helper/model/settings.dart';
import 'package:nemesis_helper/ui/icons_images.dart';
import 'package:nemesis_helper/ui/ui_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef LinkTapCallback = void Function(String);

class TextFmtRange {
  TextFmtRange(
    this.start, {
    this.bold = false,
    this.italic = false,
    this.highlight = false,
    this.link,
    this.image,
    this.chained = false,
  }) : assert(start >= 0);

  final int start;
  final bool bold;
  final bool italic;
  bool highlight;
  final String? link;
  final ParsedImage? image;

  /// This is used to detect if two ranges actually belong to one that got
  /// split to update [highlight]
  final bool chained;

  TextFmtRange copyWith({
    int? start,
    bool? bold,
    bool? italic,
    bool? highlight,
    String? link,
    ParsedImage? image,
    bool? chained,
  }) {
    return TextFmtRange(
      start ?? this.start,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      highlight: highlight ?? this.highlight,
      link: link ?? this.link,
      image: image ?? this.image,
      chained: chained ?? this.chained,
    );
  }

  TextFmtRange clone() {
    return this.copyWith();
  }
}

class _JsonId extends StatefulWidget {
  const _JsonId({
    super.key,
    required this.sharedPreferences,
    required this.chapters,
    required this.assets,
    required this.ui,
    required this.id,
    required this.collapsible,
    required this.searchBar,
    required this.jumpToChapter,
  });

  final SharedPreferences? sharedPreferences;
  final ReferenceAssets assets;

  /// Chapters to build
  final List<ReferenceChapter> chapters;

  /// UIWidgetJsonId's identifier
  final String id;

  final UISettings ui;

  /// Allow collapsing of chapters?
  final bool collapsible;

  /// Do show search bar at top?
  final bool searchBar;

  /// Helper for searching for specific chapter outside of current [UIWidgetJsonId]
  final void Function(String id) jumpToChapter;

  @override
  State<_JsonId> createState() => _JsonIdState();
}

class _JsonIdState extends State<_JsonId>
    with
        AutomaticKeepAliveClientMixin<_JsonId>,
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

  final _z85 = Base85Codec(Alphabets.z85);

  /// Array of bitmasks specifying which chapters are collapsed
  /// Inefficient but Dart has neither unsigned integers nor byte integers
  late List<int> _collapsed;

  @override
  void initState() {
    final lastSearch = widget.sharedPreferences
        ?.getString("json_id__${widget.id}__search_field");
    this._searchController = TextEditingController(text: lastSearch);

    this._collapsed = List<int>.from(_z85.decode(widget.sharedPreferences
            ?.getString("json_id__${widget.id}__collapsed_chapters") ??
        ""));

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

    final theme = Theme.of(context);

    final forceExpandCollapse = this._forceExpandCollapse;
    this._forceExpandCollapse = false;

    double initialAlignment = widget.sharedPreferences
            ?.getDouble("json_id__${widget.id}__scroll_alignment") ??
        0.0;
    int initialIndex = widget.sharedPreferences
            ?.getInt("json_id__${widget.id}__scroll_index") ??
        0;
    if (initialIndex >= widget.chapters.length) {
      initialIndex = 0;
      initialAlignment = 0.0;
    }

    final search = widget.ui.search;
    if (search != null) {
      final (searchId, widgetId) = search;
      if (widget.id == widgetId) {
        widget.ui.search = null;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _jump(context, searchId);
        });
      }
    }

    return Column(
      children: [
        if (this._offstage != null) this._offstage!,
        if (widget.searchBar)
          Row(
            children: [
              // Table of contents
              if (widget.chapters
                      .where((chapter) => chapter.text != null)
                      .length >
                  1)
                PopupMenuButton<int>(
                  tooltip: AppLocalizations.of(context).tableOfContents,
                  icon: const Icon(Icons.menu_book),
                  iconColor: theme.colorScheme.secondary,
                  onSelected: (int index) {
                    this
                        ._itemScrollController
                        .jumpTo(index: index, alignment: 0.0);
                  },
                  itemBuilder: (BuildContext context) {
                    final shownChapters =
                        this._itemPositionsListener.itemPositions.value;
                    final (firstShown, lastShown) = (
                      shownChapters.firstOrNull?.index,
                      shownChapters.lastOrNull?.index
                    );
                    final textStyle = Theme.of(context).textTheme.titleMedium!;

                    return widget.chapters.indexed.map((val) {
                      final (index, topChapter) = val;
                      final bool isOnScreen = (firstShown != null &&
                          lastShown != null &&
                          index >= firstShown &&
                          index <= lastShown);

                      return PopupMenuItem<int>(
                        padding: const EdgeInsets.symmetric(vertical: 0.0),
                        value: index,
                        child: _renderText(
                                context, topChapter, null, null, null,
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
                  onChanged: (value) => onSearchChange(value),
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
              itemCount: widget.chapters.length,
              itemBuilder: (context, index) {
                return _renderChapter(
                  context,
                  widget.chapters[index],
                  forceExpandCollapse,
                  offstage: false,
                  onLinkTap: (String jumpTo) =>
                      _jump(context, jumpTo.substring(1)),
                ).$1;
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Expansion state
  void setExpanded(ReferenceChapter chapter, bool value) {
    final id = chapter.expansionId(widget.id);
    if (id == null) return;

    updateExpanded(id, value);

    try {
      if (value) {
        chapter.expansionController(widget.id)?.expand();
      } else {
        chapter.expansionController(widget.id)?.collapse();
      }
    } catch (err) {
      if (kDebugMode) {
        print(
            'Could not ${value ? "expand" : "collapse"} ${chapter.text}, probably off-screen');
      }
    }
  }

  /// Set expansion state for chapter specified by [ReferenceChapter.expansionId]
  void updateExpanded(int expansionId, bool set) {
    if (this.isExpanded(expansionId) == set) return;

    int index = expansionId >> 3;
    int bitmask = 1 << (expansionId & 0x7);
    int length = this._collapsed.length;

    if (index >= length) {
      // Round size to 4 (requirement of z85 encoding)
      int toAdd = index + 1 - length;
      if (toAdd % 4 != 0) toAdd += 4 - toAdd % 4;

      // Use 0 so that by default all items will be expanded
      this._collapsed.addAll(List<int>.filled(toAdd, 0));
    }

    if (set) {
      this._collapsed[index] &= ~bitmask;
    } else {
      this._collapsed[index] |= bitmask;
    }

    Future(() async => await widget.sharedPreferences?.setString(
        "json_id__${widget.id}__collapsed_chapters",
        _z85.encode(Uint8List.fromList(this._collapsed))));
  }

  void collapseWithChildren(ReferenceChapter chapter) {
    final expansionId = chapter.expansionId(widget.id);
    if (expansionId != null) setExpanded(chapter, false);

    if (chapter.depth.next().isCollapsible()) {
      chapter.nested.forEach(collapseWithChildren);
    }
  }

  /// Get expansion state for chapter specified by [ReferenceChapter.expansionId]
  bool isExpanded(int? expansionId) {
    if (expansionId == null) return true;

    int index = expansionId >> 3;
    int bitmask = 1 << (expansionId & 0x7);

    return index >= this._collapsed.length ||
        (this._collapsed[index] & bitmask) == 0;
  }

  /// Update [format] by changing highlight to passed [highlight] value
  /// starting at [cursor]
  void _updateFormatWithHighlight(List<TextFmtRange> format, int cursor,
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
      format.insert(prevIndex + 1,
          prevFmt.copyWith(start: cursor, highlight: highlight, chained: true));
      format.skip(prevIndex + 2).forEach((f) => f.highlight = highlight);
    }
  }

  /// Render a single part of [ReferenceChapter.text] that has the same formatting [fmt];
  /// this is a building block of rendering [ReferenceChapter.text]
  InlineSpan _renderSingleSpan(
      BuildContext context,
      ReferenceChapter chapter,
      String text,
      TextStyle? styleOverride,
      TextFmtRange fmt,
      LinkTapCallback? onLinkTap) {
    final highlightColor = chapter.depth.highlightColor(context);
    final textStyle = styleOverride ??
        chapter.depth.textStyle(context).copyWith(
            fontWeight: fmt.bold ? FontWeight.bold : null,
            fontStyle: fmt.italic ? FontStyle.italic : null,
            backgroundColor: fmt.highlight ? highlightColor : null);

    // Paint image if needed
    Widget? imageWidget;
    final imageString = fmt.image?.link;
    if (imageString != null) {
      imageWidget = switch ((
        widget.assets.images[imageString.substring(1)],
        widget.assets.icons[imageString.substring(1)]
      )) {
        (JsonImage image, null) =>
          UiImage(jsonImage: image, widthLogical: fmt.image!.widthLogical),
        (null, JsonIcon icon) => UiIcon(
            jsonIcon: icon,
            height: chapter.depth.textHeight(context, styleOverride)),
        (null, null) => Text(
            '"${imageString.substring(1)}" is not defined in JSON',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        (JsonImage _, JsonIcon _) => throw Exception(
            'Image and icon both defined for "${imageString.substring(1)}"'),
      };
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
  (Widget, bool) _renderText(BuildContext context, ReferenceChapter chapter,
      RegExp? regex, LinkTapCallback? onLinkTap, GlobalKey? key,
      {TextStyle? styleOverride, String? tocPrefix}) {
    // Render top-level headers in uppercase when not in table of contents
    final text = (tocPrefix == null && chapter.depth.isTop())
        ? chapter.text?.toUpperCase()
        : chapter.text;
    final style = styleOverride ?? chapter.depth.textStyle(context);

    // Shortcut for the simplest cases of plain text or no text
    if (text == null) return (const SizedBox.shrink(), false);
    if (regex == null && chapter.formatNoHighlight.isEmpty) {
      final widget = Container(
        alignment: Alignment.centerLeft,
        padding: chapter.depth.indentation(),
        child: Text(
          // Also add specified table of contents prefix
          "${tocPrefix ?? ''}$text",
          key: key,
          style: style,
        ),
      );
      return (widget, false);
    }

    // Create a local copy of formatting and add all search matches to it
    final List<TextFmtRange> format = [];
    if ((chapter.formatNoHighlight.firstOrNull?.start ?? 1) > 0) {
      format.add(TextFmtRange(0));
    }
    format.addAll(chapter.formatNoHighlight.map((fmt) => fmt.clone()));
    if (format.last.start < text.length) {
      format.add(TextFmtRange(text.length));
    }

    bool matches = false;
    if (regex != null) {
      int cursor = 0;
      text.splitMapJoin(regex, onMatch: (m) {
        matches = true;
        _updateFormatWithHighlight(format, cursor, highlight: true);
        cursor = m.end;
        return "";
      }, onNonMatch: (n) {
        _updateFormatWithHighlight(format, cursor, highlight: false);
        cursor += n.length;
        return "";
      });
    }

    // And render requested format using [TextSpan] and [WidgetSpan]
    final spans = <InlineSpan>[];
    final spansLeft = <InlineSpan>[];
    final spansRight = <InlineSpan>[];

    if (tocPrefix != null) {
      spans.add(TextSpan(text: tocPrefix, style: style));
    }

    TextFmtRange fmt = format.first;
    for (final nextFmt in format.skip(1)) {
      // Show each image only once
      if (fmt.chained && fmt.image != null) {
        fmt = nextFmt;
        continue;
      }

      final span = _renderSingleSpan(
          context,
          chapter,
          text.substring(fmt.start, nextFmt.start),
          styleOverride,
          fmt,
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
        if (spansLeft.isNotEmpty)
          Text.rich(TextSpan(
              children: [...spansLeft, TextSpan(text: " ", style: style)])),
        Expanded(child: widget),
        if (spansRight.isNotEmpty)
          Text.rich(TextSpan(
              children: [TextSpan(text: " ", style: style), ...spansRight])),
      ]);
    }

    widget = Container(
      key: key,
      alignment: Alignment.centerLeft,
      padding: chapter.depth.indentation(),
      child: widget,
    );
    return (widget, matches);
  }

  /// Render this chapter together with it's children as widget
  ///
  /// Set [offstage] to build yet another instance of the widget; useful
  /// for calculating dimensions when jumping through links.
  (Widget, bool) _renderChapter(
      BuildContext context, ReferenceChapter chapter, bool forceExpandCollapse,
      {required bool offstage, required LinkTapCallback? onLinkTap}) {
    final List<Widget> nestedWidgets;
    bool nestedMatches;

    // Recursively walk children
    (nestedWidgets, nestedMatches) = chapter.nested
        .map((ReferenceChapter child) => _renderChapter(
            context, child, forceExpandCollapse,
            offstage: offstage, onLinkTap: onLinkTap))
        .fold<(List<Widget>, bool)>(([], false), (prev, element) {
      return (prev.$1..add(element.$1), prev.$2 || element.$2);
    });

    final (renderedText, thisMatches) = (chapter.text != null)
        ? _renderText(context, chapter, this._regex, onLinkTap, null)
        : (null, false);

    // Make sure that all [ScrollablePositionedList] children have
    // global key.  It's necessary to avoid needless full rebuilds
    // (including state!!) for it's jumpTo() method.
    final globalKey = chapter.globalKey(offstage, widget.id);
    switch ((
      renderedText,
      nestedWidgets.isEmpty ? null : nestedWidgets,
      widget.collapsible && chapter.depth.isCollapsible()
    )) {
      case (Widget renderedText, List<Widget> nestedWidgets, true):
        // Force expanding and collapsing when user changes search field
        // and do nothing otherwise
        final forcedExpansion = nestedMatches || thisMatches;
        if (forceExpandCollapse && !offstage) {
          setExpanded(chapter, forcedExpansion);
        }

        final expansionId = chapter.expansionId(widget.id);

        return (
          ExpansionTile(
            key: globalKey,
            controller:
                (offstage) ? null : chapter.expansionController(widget.id),
            // To make sure children widgets are always available for offset
            // calculation and expansion (it's easier this way than expanding
            // all nested [ExpansionTile]s frame-by-frame through callbacks
            // when searching for jump target's position)
            maintainState: true,
            onExpansionChanged: (expansionId == null)
                ? null
                : (value) {
                    // Save new expansion value
                    updateExpanded(expansionId, value);

                    // Also collapse all children
                    if (value == false &&
                        chapter.depth.next().isCollapsible()) {
                      chapter.nested.forEach(collapseWithChildren);
                    }
                  },
            initiallyExpanded: isExpanded(expansionId),
            title: renderedText,
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

  void _jump(BuildContext context, String searchId) {
    bool found = widget.chapters.indexed
            .map((val) {
              final (listIndex, chapter) = val;
              return _jumpToChapter(
                context,
                chapter,
                listIndex,
                // Seems that ensureVisible() does not work will with
                // [ExpansionTile] so use jumps instead of scrolling
                false,
                searchId,
              );
            })
            .where((ret) => ret)
            .firstOrNull ??
        false;

    if (!found) {
      // Target chapter is not in this widget, run a full search
      widget.jumpToChapter(searchId);
    }
  }

  /// Jump or scroll to [chapter] if it matches [searchId].
  ///
  /// Returns whether this chapter (including children) matches.
  bool _jumpToChapter(
    BuildContext context,
    ReferenceChapter chapter,
    int listIndex,
    bool useScroll,
    String searchId, {
    List<ReferenceChapter> parents = const [],
  }) {
    bool thisMatches = (chapter.id == searchId);
    final chaptersList = parents.toList()..add(chapter);

    final bool nestedMatches = chapter.nested
            .map((child) => _jumpToChapter(
                context, child, listIndex, useScroll, searchId,
                parents: chaptersList))
            .where((value) => value)
            .firstOrNull ??
        false;

    if (kDebugMode) {
      print(
          "Searching for $searchId at nesting ${chapter.depth}, this: $thisMatches, nested: $nestedMatches, text: ${chapter.text}, ${(chapter.globalKey(false, widget.id)?.currentContext == null) ? 'null context' : 'has context'}");
    }

    if (!thisMatches) {
      return nestedMatches;
    }

    // Jump to target!

    // Expand all parents of jump target and target itself...
    for (final chapter in chaptersList) {
      setExpanded(chapter, true);
    }

    // Easy path: target is rendered already so we can just scroll to it.
    var thisContext = chapter.globalKey(false, widget.id)?.currentContext;
    final thisRender = thisContext?.findRenderObject() as RenderBox?;

    if (thisRender != null && useScroll) {
      if (kDebugMode) {
        print(
            "Found target in viewport at offset ${thisRender.localToGlobal(Offset.zero).dy}, scrolling");
      }

      // Wait for for parents' expand() to finish (200 ms is default
      // expansion time) while scrolling to target's parents, and
      // then scroll to the target.
      for (var i = 0; i <= 300; i += 50) {
        Future.delayed(aMillisecond * i, () {
          final targetContext = chaptersList.reversed
              .map((chapter) =>
                  chapter.globalKey(false, widget.id)?.currentContext)
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

      return true;
    }

    // Hard path: calculate proper position for jump and schedule it
    final offstage = Offstage(
      child: _renderChapter(context, chaptersList.first, true,
              offstage: true, onLinkTap: null)
          .$1,
    );
    setState(() {
      this._offstage = offstage;
    });

    SchedulerBinding.instance.addPostFrameCallback((_) {
      final offset = _calculateOffset(
          parent: chaptersList.first, child: chapter, listIndex: listIndex);
      setState(() {
        this._offstage = null;
      });

      final listHeight =
          (this._listKey.currentContext?.findRenderObject() as RenderBox?)
              ?.size
              .height;

      if (listHeight != null) {
        // Do not use [ScrollablePositionedList.scrollTo],
        // it is broken when list has [ExpansionTile]
        this
            ._itemScrollController
            .jumpTo(index: listIndex, alignment: offset / listHeight);
      }
    });

    return true;
  }

  double _calculateOffset({
    required ReferenceChapter parent,
    required ReferenceChapter child,
    required int listIndex,
  }) {
    final parentKey = parent.globalKey(true, widget.id);
    final childKey = child.globalKey(true, widget.id);
    assert(parentKey != null);
    assert(childKey != null);

    final parentRender =
        parentKey?.currentContext?.findRenderObject() as RenderBox?;
    final childRender =
        childKey?.currentContext?.findRenderObject() as RenderBox?;
    if (parentRender == null || childRender == null) {
      if (kDebugMode) print("link target is not rendered anymore!");
      return 0.0;
    }

    assert(parentRender.attached && childRender.attached);
    final parentPosition = parentRender.localToGlobal(Offset.zero);
    final childPosition = childRender.localToGlobal(Offset.zero);

    final offset = parentPosition.dy - childPosition.dy;
    if (kDebugMode) {
      print(
          "Chapter #$listIndex has offset $offset in size ${parentRender.size.height}");
    }
    return offset;
  }

  void _itemPositionListener() {
    final firstItem =
        this._itemPositionsListener.itemPositions.value.firstOrNull;
    final index = firstItem?.index ?? 0;
    final alignment = firstItem?.itemLeadingEdge ?? 0.0;

    if (kDebugMode) {
      print("scrollIndex $index scrollAlignment $alignment");
    }

    widget.sharedPreferences
        ?.setInt("json_id__${widget.id}__scroll_index", index);
    widget.sharedPreferences
        ?.setDouble("json_id__${widget.id}__scroll_alignment", alignment);
  }

  void onSearchChange(String value) {
    if (value.isNotEmpty) {
      RegExp? regex;
      try {
        regex = RegExp(value,
            caseSensitive: false, unicode: true, multiLine: true, dotAll: true);
      } catch (error) {
        if (kDebugMode) print("Invalid regex: $value, error: $error");
      }

      setState(() {
        this._forceExpandCollapse = true;
        this._regex = regex;
      });
    } else if (this._regex != null) {
      setState(() {
        this._regex = null;
      });
    }

    widget.sharedPreferences?.setString(
        "json_id__${widget.id}__search_field", this._searchController.text);
  }
}

@immutable
class UIWidgetJsonId implements UIWidget {
  final String _id;

  /// Whether this chapter and its children can be collapsed
  final bool _collapsible;

  /// Show search bar?
  final bool _searchBar;

  /// Root chapters to render
  final List<ReferenceChapter> _chapters;

  const UIWidgetJsonId._({
    required String id,
    required bool collapsible,
    required bool searchBar,
    required List<ReferenceChapter> chapters,
  })  : _id = id,
        _collapsible = collapsible,
        _searchBar = searchBar,
        _chapters = chapters;

  /// Create a new [UIWidget] instance
  factory UIWidgetJsonId.fromJson(
      Map<String, dynamic> json, ReferenceData reference) {
    final root = json['root'] as String;
    final List<ReferenceChapter> chapters;

    if (root.endsWith('/*')) {
      chapters =
          reference.findChapterById(root.substring(0, root.length - 2)).nested;
    } else {
      final chapter = reference.findChapterById(root);
      // Chapters are arranged in a lazily built list so it is important to
      // return actual chapters that user will see instead of a single tab.
      chapters = (chapter.depth.isTab()) ? chapter.nested : [chapter];
    }

    final uiWidget = UIWidgetJsonId._(
      id: json['id'] as String,
      collapsible: (json['collapsible'] as bool?) ?? true,
      searchBar: (json['search_bar'] as bool?) ?? false,
      chapters: chapters,
    );

    reference.prepareWidget(uiWidget._id, uiWidget._chapters);

    return uiWidget;
  }

  @override
  Widget uiWidgetBuild(BuildContext context, UISettings ui, dynamic arg) {
    return Consumer<JsonData?>(
      builder: (context, jsonData, _) {
        if (jsonData == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return _JsonId(
          sharedPreferences: ui.sharedPreferences,
          chapters: this._chapters,
          assets: jsonData.reference.assets,
          ui: ui,
          id: this._id,
          collapsible: this._collapsible,
          searchBar: this._searchBar,
          jumpToChapter: (String searchId) {
            final parents = <ReferenceChapter>[];
            final chapter =
                jsonData.reference.findChapterById(searchId, parents: parents);

            final tab = jsonData.tabs
                .where((tab) => (tab.widget is UIWidgetJsonId))
                .where((tab) => parents.followedBy([chapter]).any((chapter) =>
                    (tab.widget as UIWidgetJsonId)
                        ._chapters
                        .any((tabChapter) => tabChapter == chapter)))
                .firstOrNull;
            if (tab == null) return;

            ui.tabIndex = jsonData.tabs.indexOf(tab);
            ui.search = (searchId, (tab.widget as UIWidgetJsonId)._id);
            DefaultTabController.of(context).animateTo(ui.tabIndex);
          },
        );
      },
    );
  }
}
