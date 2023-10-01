// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'screen_reference.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReferenceChapter _$ReferenceChapterFromJson(Map<String, dynamic> json) =>
    ReferenceChapter(
      text: json['text'] as String?,
      nested: (json['nested'] as List<dynamic>?)
              ?.map((e) => ReferenceChapter.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    )..bold = json['bold'] as bool? ?? false;

Map<String, dynamic> _$ReferenceChapterToJson(ReferenceChapter instance) =>
    <String, dynamic>{
      'text': instance.text,
      'bold': instance.bold,
      'nested': instance.nested.map((e) => e.toJson()).toList(),
    };

ReferenceData _$ReferenceDataFromJson(Map<String, dynamic> json) =>
    ReferenceData(
      nested: (json['nested'] as List<dynamic>)
          .map((e) => ReferenceChapter.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ReferenceDataToJson(ReferenceData instance) =>
    <String, dynamic>{
      'nested': instance.nested.map((e) => e.toJson()).toList(),
    };
