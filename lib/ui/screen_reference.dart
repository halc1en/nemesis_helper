import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

part 'screen_reference.g.dart';

@JsonSerializable()
class ReferenceChapter {
  String? text;

  @JsonKey(defaultValue: false)
  bool bold = false;

  List<ReferenceChapter>? nested;

  @JsonKey(includeFromJson: false, includeToJson: false)
  List<TextStyle>? _styles;

  ReferenceChapter({required this.text, required this.nested});

  // Get text style for each of 0 to 4 allowed nesting depths in JSON
  TextStyle? textStyle(BuildContext context, int depth) {
    if (this._styles == null) {
      final textTheme = Theme.of(context).textTheme;
      this._styles = [
        // These can't be null since they are explicitly initialized
        // in MaterialApp.textTheme
        textTheme.headlineMedium!.copyWith(
            shadows: [Shadow(color: Colors.blue.shade200, blurRadius: 10)]),
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

    return this._styles?.getRange(depth, depth + 1).firstOrNull;
  }

  // Rich text is used at depth >=2 to allow words in bold
  InlineSpan showRichText(BuildContext context, {int depth = 0}) {
    final spans = <InlineSpan>[];

    // Recursively show the children
    final nested = this.nested;
    if (nested != null) {
      spans.addAll(nested.map((ReferenceChapter child) =>
          child.showRichText(context, depth: depth + 1)));
    }

    return TextSpan(
      text: text,
      style: textStyle(context, depth)
          ?.copyWith(fontWeight: bold ? FontWeight.bold : null),
      children: spans.isNotEmpty ? spans : null,
    );
  }

  Widget show(BuildContext context, {int depth = 0}) {
    final widgets = <Widget>[];

    // Recursively show the children
    final nested = this.nested;
    if (nested != null) {
      // First two levels can be collapsed
      if (depth == 0) {
        widgets.add(Column(
          children: nested
              .map((ReferenceChapter child) =>
                  child.show(context, depth: depth + 1))
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
                  children: nested
                      .map((ReferenceChapter child) =>
                          child.showRichText(context, depth: depth + 1))
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
      return ExpansionTile(
        initiallyExpanded: true,
        maintainState: true,
        shape: const Border.fromBorderSide(BorderSide.none),
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(text, style: textStyle(context, depth)),
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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      Directory documents = await getApplicationDocumentsDirectory();
      final jsonString =
          await File(join(documents.path, "reference.json")).readAsString();
      setState(() {
        _reference = ReferenceData(
          nested: (jsonDecode(jsonString) as List<dynamic>)
              .map<ReferenceChapter>((json) =>
                  ReferenceChapter.fromJson(json as Map<String, dynamic>))
              .toList(),
        );
      });
    });

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final ref = _reference;
    if (ref == null) return const CircularProgressIndicator();

    this._tiles ??= ref.show(context);
    return ListView(
      children: this._tiles!,
    );
  }
}
