// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:nemesis_helper/ui/settings.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

@immutable
class Nesting {
  const Nesting() : _depth = 0;
  const Nesting._explicit(this._depth);

  // First 3 levels are for headers and next 2 for body
  final int _depth;

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
}

class ReferenceChapter {
  ReferenceChapter(
      {required this.text, required this.depth, required this.nested});

  static const Indentation = 12.0;

  // This chapter's text
  String? text;
  bool bold = false;

  // Nesting level in JSON
  Nesting depth;

  // Nested chapters
  List<ReferenceChapter> nested;

  ExpansionTileController? expansionController;

  // Look for [regex] in [this.text] and highlight it
  (InlineSpan, bool) showOneSpan(
      BuildContext context, List<InlineSpan>? nestedSpans, RegExp? regex) {
    final text = this.text;

    // If search field is empty then show this node without highlighting
    if (text == null || regex == null) {
      return (
        TextSpan(
          text: text,
          style: this
              .depth
              .textStyle(context)
              .copyWith(fontWeight: bold ? FontWeight.bold : null),
          children: nestedSpans,
        ),
        false
      );
    }

    // If search field is not empty then highlight all matches
    var matches = false;
    final textStyle = this.depth.textStyle(context);
    final highlightColor = Color.lerp(
        textStyle.color ??
            textStyle.foreground?.color ??
            Theme.of(context).colorScheme.background,
        Colors.black,
        0.6);

    final highlightSpans = <TextSpan>[];
    void addSpan(String text, {required bool highlight, required bool last}) {
      highlightSpans.add(TextSpan(
        text: text,
        style: textStyle.copyWith(
            fontWeight: bold ? FontWeight.bold : null,
            backgroundColor: (highlight) ? highlightColor : null),
        // Show nested spans after the end of [this.text]
        children: (last) ? nestedSpans : null,
      ));
    }

    int index = 0;
    for (final match in regex.allMatches(text)) {
      matches = true;
      if (index < match.start) {
        addSpan(text.substring(index, match.start),
            highlight: false, last: false);
      }
      addSpan(match[0]!, highlight: true, last: match.end == text.length);
      index = match.end;
    }
    if (index < text.length) {
      addSpan(text.substring(index, text.length), highlight: false, last: true);
    }
    return (TextSpan(children: highlightSpans), matches);
  }

  // Render this chapter as [InlineSpan] suitable for
  // embedding into [RichText] widget.
  (InlineSpan, bool) recurseSpan(BuildContext context, RegExp? regex) {
    // Recursively walk children
    var (nestedSpans, nestedMatchesRegex) = this
        .nested
        .map((ReferenceChapter child) => child.recurseSpan(context, regex))
        .fold<(List<InlineSpan>?, bool)>((null, false), (prev, element) {
      return ((prev.$1 ?? [])..add(element.$1), prev.$2 || element.$2);
    });

    // Render this node with children
    var (span, thisMatchesRegex) = showOneSpan(context, nestedSpans, regex);

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

    return (span, nestedMatchesRegex || thisMatchesRegex);
  }

  // Render this chapter as widget
  (Widget, bool) recurseWidget(
      BuildContext context, RegExp? regex, bool forceExpandCollapse) {
    final List<Widget> widgets;
    bool nestedMatchesRegex;

    // Recursively walk children
    if (depth.next().isCollapsible()) {
      // Use [ExpansionTile] for collapsible chapters
      (widgets, nestedMatchesRegex) = this
          .nested
          .map((ReferenceChapter child) =>
              child.recurseWidget(context, regex, forceExpandCollapse))
          .fold<(List<Widget>, bool)>(([], false), (prev, element) {
        return (prev.$1..add(element.$1), prev.$2 || element.$2);
      });
    } else {
      // Otherwise use [RichText]
      final List<InlineSpan> nestedSpans;
      (nestedSpans, nestedMatchesRegex) = this
          .nested
          .map((ReferenceChapter child) => child.recurseSpan(context, regex))
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
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(children: widgets)),
        nestedMatchesRegex
      );
    } else {
      final (span, thisMatchesRegex) = showOneSpan(context, null, regex);

      // Force expanding and collapsing when user changes search field
      // and do nothing otherwise
      final expanded =
          (regex == null || nestedMatchesRegex || thisMatchesRegex);
      if (forceExpandCollapse) {
        if (expanded) {
          this.expansionController?.expand();
        } else {
          this.expansionController?.collapse();
        }
      }
      this.expansionController ??= ExpansionTileController();

      return (
        ExpansionTile(
          controller: this.expansionController,
          initiallyExpanded: expanded,
          maintainState: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text.rich(span),
          children: widgets,
        ),
        nestedMatchesRegex || thisMatchesRegex
      );
    }
  }

  factory ReferenceChapter.fromJson(
      Nesting depth, Locale? locale, Map<String, dynamic> json) {
    return ReferenceChapter(
      text: json['text_${locale?.languageCode ?? "en"}'] as String?,
      depth: depth,
      nested: (json['nested'] as List<dynamic>?)
              ?.map((e) => ReferenceChapter.fromJson(
                  depth.next(), locale, e as Map<String, dynamic>))
              .toList() ??
          [],
    )..bold = json['bold'] as bool? ?? false;
  }
}

class ReferenceData {
  final Locale? locale;
  final List<ReferenceChapter> nested;

  ReferenceData({required this.locale, required this.nested});

  List<Widget> show(
      BuildContext context, RegExp? regex, bool forceExpandCollapse) {
    return this
        .nested
        .map((child) =>
            child.recurseWidget(context, regex, forceExpandCollapse).$1)
        .toList();
  }

  factory ReferenceData.fromJson(Locale? locale, String jsonString) {
    return ReferenceData(
        locale: locale,
        nested: (jsonDecode(jsonString) as List<dynamic>)
            .map<ReferenceChapter>((json) => ReferenceChapter.fromJson(
                const Nesting(), locale, json as Map<String, dynamic>))
            .toList());
  }
}

class Reference extends StatefulWidget {
  const Reference({super.key, required this.ui});

  final UISettings ui;

  @override
  State<Reference> createState() => _ReferenceState();
}

class _ReferenceState extends State<Reference>
    with AutomaticKeepAliveClientMixin<Reference> {
  ReferenceData? _reference;
  final TextEditingController _searchController = TextEditingController();
  bool _loading = false;
  RegExp? _regex;
  bool _forceExpandCollapse = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    updateJsonFromFile();
    super.initState();
  }

  void updateJsonFromFile() {
    // Nothing to reload if locale has not changed
    if (_reference != null && _reference?.locale == widget.ui.locale) return;

    // Check if loading already works asynchronously
    if (_loading) return;
    // Schedule JSON loading
    this._loading = true;

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      Directory documents = await getApplicationDocumentsDirectory();
      final jsonString =
          await File(p.join(documents.path, "reference.json")).readAsString();
      final ref = ReferenceData.fromJson(widget.ui.locale, jsonString);

      this._loading = false;
      setState(() => this._reference = ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Since we got here something in Provider (i.e. UISettings)
    // has changed, reload JSON
    updateJsonFromFile();

    final ref = this._reference;
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
              onPressed: this._searchController.clear,
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
                this._forceExpandCollapse = true;
                this._regex = null;
              });
            }
          },
        ),
        Expanded(
            child: ListView(
                children: ref.show(context, this._regex, forceExpandCollapse))),
      ],
    );
  }
}
