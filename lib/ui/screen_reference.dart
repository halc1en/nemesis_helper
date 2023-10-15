import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:quiver/time.dart';

import 'package:nemesis_helper/model/settings.dart';

typedef LinkTapCallback = void Function(String);

@immutable
class Nesting {
  const Nesting() : _depth = 0;
  const Nesting._explicit(this._depth);

  // First 3 levels are for headers and next 2 for body
  final int _depth;

  // Cached styles for faster retrieval
  static List<TextStyle>? _styles;

  // Headers do not take part in multi-paragraph search
  bool isHeader() => this._depth <= 2;

  // Comments explain previous paragraph clearer and should be indented
  bool isComment() => this._depth >= 4;

  // First two levels use [ExpansionTile] and can be collapsed
  bool isCollapsible() => this._depth <= 1;

  Nesting next() => Nesting._explicit(this._depth + 1);

  // Get text style for each of 0 to 4 allowed nesting depths in JSON
  TextStyle textStyle(BuildContext context) {
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
            color: Colors.blue,
            shadows: [Shadow(color: Colors.blue.shade600, blurRadius: 2)]),
        textTheme.bodyMedium!,
        labelMedium.copyWith(
            color: Color.lerp(labelMedium.color, Colors.black, 0.2),
            fontStyle: FontStyle.italic,
            fontSize: labelMedium.fontSize! * 1.1),
      ];
    }

    return Nesting._styles![this._depth.clamp(0, Nesting._styles!.length - 1)];
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
}

class TextFmtRange {
  TextFmtRange(
    this.start, {
    this.bold = false,
    this.italic = false,
    this.highlight = false,
    this.link,
  }) : assert(start >= 0);

  final int start;
  bool bold;
  bool italic;
  bool highlight;
  String? link;

  TextFmtRange clone() {
    return TextFmtRange(this.start,
        bold: this.bold,
        italic: this.italic,
        highlight: this.highlight,
        link: this.link);
  }
}

class ReferenceChapter {
  ReferenceChapter(
      {required String? text,
      required this.id,
      required this.depth,
      required this.nested}) {
    if (text != null) this.text = parseJsonString(text);
  }

  // This chapter's text
  String? text;

  // Nested chapters
  final List<ReferenceChapter> nested;

  // This chapter's id and key (for hyperlinks to it)
  final String? id;
  final GlobalKey key = GlobalKey();

  // This chapter's format without search field highlight
  final List<TextFmtRange> formatNoHighlight = [];

  // Nesting level in JSON
  final Nesting depth;

  ExpansionTileController? expansionController;

  static final RegExp specialRegex =
      RegExp(r'\\\*|\\\]|\\\[|\[(.*?[^\\])\]\((.+?)\)|\*\*|\*', unicode: true);

  // Parse [text] and return the resulting string.
  // Save all found formatting hints to [this.formatNoHighlight]
  // Special characters:
  //  **bold text**
  //  *italic text*
  //  [link text](link URL)
  String parseJsonString(String text,
      {int cursor = 0, bool bold = false, bool italic = false, String? link}) {
    void saveFormatting() {
      this
          .formatNoHighlight
          .add(TextFmtRange(cursor, bold: bold, italic: italic, link: link));
    }

    return text.splitMapJoin(ReferenceChapter.specialRegex, onMatch: (m) {
      switch (m[0]) {
        case r"\*":
        case r"\]":
        case r"\[":
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
          if (m[0]![0] == "[") {
            link = m[2];
            saveFormatting();

            final parsedLinkText = parseJsonString(m[1] ?? "",
                cursor: cursor, bold: bold, italic: italic, link: link);

            cursor += parsedLinkText.length;
            link = null;
            saveFormatting();

            return parsedLinkText;
          }
          assert(false);
          return "";
      }
    }, onNonMatch: (n) {
      cursor += n.length;
      return n;
    });
  }

  static const Indentation = 12.0;

  // Update [format] by changing highlight to passed [highlight] value
  // starting at [cursor]
  void updateFormatWithHighlight(List<TextFmtRange> format, int cursor,
      {required bool highlight}) {
    final int prevIndex = format.lastIndexWhere((s) => s.start <= cursor);
    if (prevIndex < 0) {
      format.insert(0, TextFmtRange(cursor));
      return;
    }

    final TextFmtRange prevFmt = format[prevIndex];
    if (prevFmt.start == cursor) {
      format.replaceRange(prevIndex, prevIndex + 1, [
        TextFmtRange(cursor,
            bold: prevFmt.bold, italic: prevFmt.italic, highlight: highlight)
      ]);
      format.skip(prevIndex + 1).forEach((f) => f.highlight = highlight);
    } else {
      format.insert(
          prevIndex + 1,
          TextFmtRange(cursor,
              bold: prevFmt.bold,
              italic: prevFmt.italic,
              highlight: highlight));
      format.skip(prevIndex + 2).forEach((f) => f.highlight = highlight);
    }
  }

  // Renders [this.text] while taking into account:
  //  - highlighting [regex] matches
  //  - formatting according to [this.format]
  //
  // Returns rendered [InlineSpan] and whether [regex]/[jumpTo] matches it
  (InlineSpan, bool) renderText(BuildContext context,
      List<InlineSpan>? nestedSpans, RegExp? regex, LinkTapCallback onLinkTap) {
    final text = this.text;

    // Shortcut for the simplest cases of plain text or no text
    if (text == null || regex == null && this.formatNoHighlight.isEmpty) {
      return (
        TextSpan(
          // Insert newline between different nesting levels
          text: (text != null && (nestedSpans?.isNotEmpty ?? false))
              ? "$text\n"
              : text,
          style: this.depth.textStyle(context),
          children: nestedSpans,
        ),
        false
      );
    }

    // If search field is not empty then get all matches
    final format = [...this.formatNoHighlight.map((fmt) => fmt.clone())];

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

    // And render those matches using [TextSpan]
    final highlightSpans = <InlineSpan>[];

    TextFmtRange prevFmt = TextFmtRange(0);
    for (final fmt in format) {
      highlightSpans.add(_renderSingleSpan(context,
          text.substring(prevFmt.start, fmt.start), prevFmt, onLinkTap));
      prevFmt = fmt;
    }
    // Show nested spans after the end of [this.text]
    highlightSpans.add(_renderSingleSpan(
        context, text.substring(prevFmt.start), prevFmt, onLinkTap,
        children: nestedSpans));

    return (TextSpan(children: highlightSpans), matches);
  }

  // Render a single part of [this.text] that has the same formatting [fmt];
  // this is a building block of rendering [this.text]
  InlineSpan _renderSingleSpan(BuildContext context, String text,
      TextFmtRange fmt, LinkTapCallback onLinkTap,
      {List<InlineSpan>? children}) {
    final InlineSpan span;
    final highlightColor = this.depth.highlightColor(context);
    final textStyle = this.depth.textStyle(context).copyWith(
        fontWeight: fmt.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: fmt.italic ? FontStyle.italic : FontStyle.normal,
        backgroundColor: fmt.highlight ? highlightColor : null);

    final link = fmt.link;
    if (link == null) {
      // No hyperlinks - just render the text
      span = TextSpan(
          // Insert newline between different nesting levels
          text: (children != null) ? "$text\n" : text,
          style: textStyle,
          children: children);
    } else {
      // Use hyperlink style and capture finger taps/mouse clicks
      span = WidgetSpan(
        baseline: TextBaseline.alphabetic,
        alignment: PlaceholderAlignment.baseline,
        style: textStyle.copyWith(
          decorationColor: Colors.lightBlue,
          decoration: TextDecoration.underline,
          decorationThickness: 1.5,
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () async {
              onLinkTap(link);
            },
            child: Text.rich(
              TextSpan(
                // Insert newline between different nesting levels
                text: (children != null) ? "$text\n" : text,
                style: textStyle.copyWith(color: Colors.lightBlue),
                children: children,
              ),
              // Workaround for https://github.com/flutter/flutter/issues/126962
              textScaleFactor: 1,
            ),
          ),
        ),
      );
    }

    return span;
  }

  // Render this chapter as [InlineSpan] suitable for
  // embedding into [RichText] widget.
  (InlineSpan, bool) recurseSpan(
      BuildContext context, RegExp? regex, LinkTapCallback onLinkTap) {
    // Recursively walk children
    var (nestedSpans, nestedMatches) = this
        .nested
        .map((ReferenceChapter child) =>
            child.recurseSpan(context, regex, onLinkTap))
        .fold<(List<InlineSpan>?, bool)>((null, false), (prev, element) {
      return ((prev.$1 ?? [])..add(element.$1), prev.$2 || element.$2);
    });

    // Render this node with children
    var (span, thisMatches) =
        renderText(context, nestedSpans, regex, onLinkTap);

    // Add indentation for comments
    if (this.depth.isComment()) {
      span = WidgetSpan(
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: Indentation),
          child: Text.rich(span),
        ),
      );
    }

    return (span, nestedMatches || thisMatches);
  }

  // Render this chapter as widget
  (Widget, bool) recurseWidget(BuildContext context, RegExp? regex,
      bool forceExpandCollapse, LinkTapCallback onLinkTap) {
    final List<Widget> widgets;
    bool nestedMatches;

    // Recursively walk children
    if (depth.next().isCollapsible()) {
      // Use [ExpansionTile] for collapsible chapters
      (widgets, nestedMatches) = this
          .nested
          .map((ReferenceChapter child) => child.recurseWidget(
              context, regex, forceExpandCollapse, onLinkTap))
          .fold<(List<Widget>, bool)>(([], false), (prev, element) {
        return (prev.$1..add(element.$1), prev.$2 || element.$2);
      });
    } else {
      // Otherwise use [Text.rich]
      final List<InlineSpan> nestedSpans;
      (nestedSpans, nestedMatches) = this
          .nested
          .map((ReferenceChapter child) =>
              child.recurseSpan(context, regex, onLinkTap))
          .fold<(List<InlineSpan>, bool)>(([], false), (prev, element) {
        return (prev.$1..add(element.$1), prev.$2 || element.$2);
      });

      widgets = [];
      if (nestedSpans.isNotEmpty) {
        widgets.add(Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
          child: Text.rich(
            TextSpan(children: nestedSpans),
            textAlign: TextAlign.justify,
          ),
        ));
      }
    }

    // [ExpansionTile] by definition requires some text in header
    // so use simple [Column] if text was not specified
    final text = this.text;
    if (text == null) {
      return (
        Container(
            key: key,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(children: widgets)),
        nestedMatches
      );
    } else {
      final (span, thisMatches) = renderText(context, null, regex, onLinkTap);

      // Force expanding and collapsing when user changes search field
      // and do nothing otherwise
      if (forceExpandCollapse && (nestedMatches || thisMatches)) {
        this.expansionController?.expand();
      } else if (forceExpandCollapse && !nestedMatches && !thisMatches) {
        this.expansionController?.collapse();
      }
      this.expansionController ??= ExpansionTileController();

      return (
        ExpansionTile(
          key: key,
          controller: this.expansionController,
          initiallyExpanded: true,
          maintainState: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text.rich(span),
          children: widgets,
        ),
        nestedMatches || thisMatches
      );
    }
  }

  bool jumpToChapter(String chapterId) {
    bool found = (this.id == chapterId.substring(1) ||
        this.nested.any((chapter) => chapter.jumpToChapter(chapterId)));

    if (found) {
      this.expansionController?.expand();

      final thisContext = this.key.currentContext;
      if (thisContext != null) {
        // Wait for 220 ms for expand() to finish (add a bit to
        // expansion time to avoid overshooting)
        for (var i = 0; i <= 220; i += 20) {
          Future.delayed(aMillisecond * (220 - i), () {
            Scrollable.ensureVisible(thisContext,
                curve: Curves.linear, duration: aMillisecond * 50);
            return const SizedBox.shrink();
          });
        }
      }
    }

    return found;
  }

  factory ReferenceChapter.fromJson(Nesting depth, Map<String, dynamic> json) {
    final jsonText = json['text'];

    return ReferenceChapter(
      text: (jsonText is List) ? jsonText.join('\n') : (jsonText as String?),
      id: json['id'] as String?,
      depth: depth,
      nested: (json['nested'] as List<dynamic>?)
              ?.map((e) => ReferenceChapter.fromJson(
                  depth.next(), e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

@immutable
class ReferenceData {
  final List<ReferenceChapter> nested;

  const ReferenceData({required this.nested});

  List<Widget> show(
      BuildContext context, RegExp? regex, bool forceExpandCollapse,
      {required LinkTapCallback onLinkTap}) {
    return this
        .nested
        .map((child) => child
            .recurseWidget(context, regex, forceExpandCollapse, onLinkTap)
            .$1)
        .toList();
  }

  void jumpToChapter(String chapterId) {
    nested.any((chapter) => chapter.jumpToChapter(chapterId));
  }

  factory ReferenceData.fromJson(Map<String, dynamic> json) {
    return ReferenceData(
        nested: (json['reference'] as List<dynamic>? ?? [])
            .map<ReferenceChapter>((json) => ReferenceChapter.fromJson(
                const Nesting(), json as Map<String, dynamic>))
            .toList());
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
    with AutomaticKeepAliveClientMixin<Reference> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  RegExp? _regex;
  bool _forceExpandCollapse = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final ref = widget.reference;
    if (ref == null) return const Center(child: CircularProgressIndicator());

    final forceExpandCollapse = this._forceExpandCollapse;
    this._forceExpandCollapse = false;

    return Column(
      children: [
        TextField(
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
          },
        ),
        Expanded(
          child: SingleChildScrollView(
            restorationId: "reference_scroll_offset",
            controller: this._scrollController,
            child: Column(
              children: ref.show(context, this._regex, forceExpandCollapse,
                  onLinkTap: (String jumpTo) =>
                      widget.reference?.jumpToChapter(jumpTo)),
            ),
          ),
        ),
      ],
    );
  }
}
