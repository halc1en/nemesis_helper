// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'screen_reference.g.dart';

@immutable
class Nesting {
  const Nesting() : _depth = 0;
  const Nesting._explicit(this._depth);

  // First 3 levels are for headers and next 2 for body
  final int _depth;

  static List<TextStyle>? _styles;

  bool isHeader() => this._depth <= 2;
  bool isFirstLevel() => this._depth == 0;
  Nesting nextLevel() => Nesting._explicit(this._depth + 1);

  // Get text style for each of 0 to 4 allowed nesting depths in JSON
  TextStyle? textStyle(BuildContext context) {
    if (Nesting._styles == null) {
      final textTheme = Theme.of(context).textTheme;
      Nesting._styles = [
        // These can't be null since they are explicitly initialized
        // in MaterialApp.textTheme
        textTheme.headlineMedium!.copyWith(
            shadows: [Shadow(color: Colors.blue.shade200, blurRadius: 10)],
            letterSpacing: -0.7),
        textTheme.titleLarge!.copyWith(
            decoration: TextDecoration.underline,
            shadows: [Shadow(color: Colors.blue.shade400, blurRadius: 5)]),
        textTheme.bodyLarge!.copyWith(
            color: Colors.blue,
            shadows: [Shadow(color: Colors.blue.shade600, blurRadius: 2)]),
        textTheme.bodyMedium!,
        textTheme.labelMedium!.copyWith(fontStyle: FontStyle.italic),
      ];
    }

    return Nesting._styles?.getRange(this._depth, this._depth + 1).firstOrNull;
  }
}

@JsonSerializable()
class ReferenceChapter {
  ReferenceChapter({required this.text, required this.nested});

  String? text;

  @JsonKey(defaultValue: false)
  bool bold = false;

  @JsonKey(defaultValue: [])
  List<ReferenceChapter> nested;

  @JsonKey(includeFromJson: false, includeToJson: false)
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

    return TextSpan(
      text: text,
      style: depth
          .textStyle(context)
          ?.copyWith(fontWeight: bold ? FontWeight.bold : null),
      children: spans.isNotEmpty ? spans : null,
    );
  }

  Widget show(BuildContext context, {Nesting depth = const Nesting()}) {
    final widgets = <Widget>[];

    // Recursively show the children
    if (this.nested.isNotEmpty) {
      // First two levels can be collapsed
      if (depth.isFirstLevel()) {
        widgets.add(Column(
          children: this
              .nested
              .map((ReferenceChapter child) =>
                  child.show(context, depth: depth.nextLevel()))
              .toList(),
        ));
      } else {
        widgets.add(Row(
          children: [
            const SizedBox(width: 16),
            Expanded(
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
            ),
            const SizedBox(width: 4),
          ],
        ));
      }
    }

    // Expansion tile by definition requires some text in header
    // so use normal tile if text was not specified
    final text = this.text;
    if (text == null) {
      return ListTile(
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

  factory ReferenceChapter.fromJson(Map<String, dynamic> json) =>
      _$ReferenceChapterFromJson(json);
  Map<String, dynamic> toJson() =>
      throw UnsupportedError('Serialization is not needed');
}

@JsonSerializable()
class ReferenceData {
  final List<ReferenceChapter> nested;

  ReferenceData({required this.nested});

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

  factory ReferenceData.fromJson(Map<String, dynamic> json) =>
      _$ReferenceDataFromJson(json);
  Map<String, dynamic> toJson() =>
      throw UnsupportedError('Serialization is not needed');
}

class Reference extends StatefulWidget {
  const Reference({super.key});

  @override
  State<Reference> createState() => _ReferenceState();
}

class _ReferenceState extends State<Reference>
    with AutomaticKeepAliveClientMixin<Reference> {
  ReferenceData? _reference;
  List<Widget>? _tiles;
  final TextEditingController _searchController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      Directory documents = await getApplicationDocumentsDirectory();
      final jsonString =
          await File(p.join(documents.path, "reference.json")).readAsString();
      final ref = ReferenceData(
          nested: (jsonDecode(jsonString) as List<dynamic>)
              .map<ReferenceChapter>((json) =>
                  ReferenceChapter.fromJson(json as Map<String, dynamic>))
              .toList());
      setState(() => this._reference = ref);
    });

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final ref = this._reference;
    if (ref == null) return const CircularProgressIndicator();

    this._tiles ??= ref.show(context);
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
