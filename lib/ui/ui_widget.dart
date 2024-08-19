import 'package:flutter/material.dart';

import 'package:nemesis_helper/model/json_data.dart';
import 'package:nemesis_helper/ui/ui_widget_authenticate.dart';
import 'package:nemesis_helper/ui/ui_widget_json_id.dart';

abstract class UIWidget {
  factory UIWidget.fromJson(
      Map<String, dynamic> json, ReferenceData reference) {
    return switch ((json['type'] as String).toLowerCase()) {
      'json_id' => UIWidgetJsonId.fromJson(json, reference),
      'authenticate' => UIWidgetAuthenticate.fromJson(json, reference),
      String name => throw Exception("Unknown widget '$name'"),
    };
  }

  /// Will be called when Flutter builds [Widget] tree
  ///
  /// Set [insideScrollable] when [UIWidget] is nested inside a scrollable
  /// widget.  In this case it should not create scrollables itself (or a
  /// complex solution with [CustomScrollView] would be needed)
  Widget uiWidgetBuild(BuildContext context, bool insideScrollable);
}
