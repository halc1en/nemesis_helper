// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:nemesis_helper/ui/settings.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

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

  bool isFirstLevel() => this._depth == 0;
  Nesting nextLevel() => Nesting._explicit(this._depth + 1);

  // Get text style for each of 0 to 4 allowed nesting depths in JSON
  TextStyle? textStyle(BuildContext context) {
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

    return Nesting._styles?.getRange(this._depth, this._depth + 1).firstOrNull;
  }
}

class ReferenceChapter {
  ReferenceChapter({required this.text, required this.nested});

  static const Indentation = 12.0;

  String? text;
  bool bold = false;

  List<ReferenceChapter> nested;

  ExpansionTileController? expansionController;

  (bool, String) searchAndHighlight(RegExp regex,
      {Nesting depth = const Nesting()}) {
    if (depth.isHeader()) {
      // Avoid combining nested text at headers level,
      // just check all nested levels and see if any matches
      final found = nested
          .map((nestedChapter) => nestedChapter
              .searchAndHighlight(regex, depth: depth.nextLevel())
              .$1)
          .fold<bool>(false, (prevValue, found) => prevValue || found);

      // Search at this level too if needed
      final text = this.text;
      if (found || text != null && regex.allMatches(text).isNotEmpty) {
        expansionController?.expand();
        return (true, text ?? "");
      } else {
        expansionController?.collapse();
        return (false, text ?? "");
      }
    } else {
      // Combine nested chapters text and search results recursively
      var (found, text) = nested
          .map((nestedChapter) =>
              nestedChapter.searchAndHighlight(regex, depth: depth.nextLevel()))
          .fold<(bool, String)>(
              (false, this.text ?? ""),
              (prevValue, found) =>
                  (prevValue.$1 || found.$1, prevValue.$2 + found.$2));

      // Search at this level too if needed
      if (found || regex.allMatches(text).isNotEmpty) {
        expansionController?.expand();
        return (true, text);
      } else {
        expansionController?.collapse();
        return (false, text);
      }
    }
  }

  // Rich text is used at depth >=2 to allow words in bold
  InlineSpan showRichText(BuildContext context, Nesting depth) {
    final spans = <InlineSpan>[];

    // Recursively show the children
    spans.addAll(this.nested.map((ReferenceChapter child) =>
        child.showRichText(context, depth.nextLevel())));

    final textSpan = TextSpan(
      text: text,
      style: depth.textStyle(context)?.copyWith(
            fontWeight: bold ? FontWeight.bold : null,
          ),
      children: spans,
    );

    return (!depth.isComment())
        ? textSpan
        : WidgetSpan(
            // Indent comment to link it with paragraph above
            child: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: Indentation),
              child: Text.rich(textSpan),
            ),
          );
  }

  Widget show(BuildContext context, {Nesting depth = const Nesting()}) {
    final widgets = <Widget>[];

    // Recursively show the children
    if (this.nested.isNotEmpty) {
      // First two levels can be collapsed
      if (depth.isFirstLevel()) {
        widgets.addAll(
          this.nested.map((ReferenceChapter child) =>
              child.show(context, depth: depth.nextLevel())),
        );
      } else {
        widgets.add(Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
          child: RichText(
            textAlign: TextAlign.justify,
            text: TextSpan(
              children: this
                  .nested
                  .map((ReferenceChapter child) =>
                      child.showRichText(context, depth.nextLevel()))
                  .toList(),
            ),
          ),
        ));
      }
    }

    // Expansion tile by definition requires some text in header
    // so use normal tile if text was not specified
    final text = this.text;
    if (text == null) {
      return ListTile(
        visualDensity: Theme.of(context)
            .visualDensity
            .copyWith(vertical: VisualDensity.minimumDensity),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Column(children: widgets),
      );
    } else {
      this.expansionController = ExpansionTileController();
      return ExpansionTile(
        controller: this.expansionController,
        initiallyExpanded: true,
        maintainState: true,
        shape: const Border.fromBorderSide(BorderSide.none),
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(text, style: depth.textStyle(context)),
        children: widgets,
      );
    }
  }

  factory ReferenceChapter.fromJson(Locale? locale, Map<String, dynamic> json) {
    return ReferenceChapter(
      text: json['text_${locale?.languageCode ?? "en"}'] as String?,
      nested: (json['nested'] as List<dynamic>?)
              ?.map((e) =>
                  ReferenceChapter.fromJson(locale, e as Map<String, dynamic>))
              .toList() ??
          [],
    )..bold = json['bold'] as bool? ?? false;
  }
}

class ReferenceData {
  final Locale? locale;
  final List<ReferenceChapter> nested;

  ReferenceData({required this.locale, required this.nested});

  List<Widget> show(BuildContext context) {
    return this.nested.map((child) => child.show(context)).toList();
  }

  void searchAndHighlight(String searchText) {
    try {
      final regex = RegExp(searchText,
          caseSensitive: false, unicode: true, multiLine: true, dotAll: true);
      for (var nestedChapter in nested) {
        nestedChapter.searchAndHighlight(regex);
      }
    } catch (_) {}
  }

  factory ReferenceData.fromJson(Locale? locale, String jsonString) {
    return ReferenceData(
        locale: locale,
        nested: (jsonDecode(jsonString) as List<dynamic>)
            .map<ReferenceChapter>((json) =>
                ReferenceChapter.fromJson(locale, json as Map<String, dynamic>))
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
  List<Widget>? _tiles;
  final TextEditingController _searchController = TextEditingController();
  bool _loading = false;

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

    this._tiles = ref.show(context);

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
            if (value.length >= 3) {
              this._reference?.searchAndHighlight(value);
            }
          },
        ),
        Expanded(child: ListView(children: this._tiles!)),
      ],
    );
  }
}
