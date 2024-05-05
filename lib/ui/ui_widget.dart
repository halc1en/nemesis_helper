import 'package:flutter/material.dart';

import 'package:nemesis_helper/model/json_data.dart';
import 'package:nemesis_helper/model/settings.dart';
import 'package:nemesis_helper/ui/ui_widget_json_id.dart';

abstract class UIWidget {
  factory UIWidget.fromJson(
      Map<String, dynamic> json, ReferenceData reference) {
    return switch ((json['type'] as String).toLowerCase()) {
      'json_id' => UIWidgetJsonId.fromJson(json, reference),
      String name => throw Exception("Unknown widget '$name'"),
    };
  }

  /// Will be called when Flutter builds [Widget] tree
  Widget uiWidgetBuild(BuildContext context, UISettings ui, dynamic arg);
}
