import 'package:flutter/material.dart';
import 'package:nemesis_helper/ui/utils.dart';
import 'package:provider/provider.dart';

import 'package:nemesis_helper/l10n.dart';
import 'package:nemesis_helper/model/json_data.dart';
import 'package:nemesis_helper/model/settings.dart';
import 'package:nemesis_helper/ui/icons_images.dart';
import 'package:nemesis_helper/ui/settings_menu.dart';

class ScaffoldWithTabs extends StatelessWidget {
  const ScaffoldWithTabs({
    super.key,
    required this.ui,
    required this.tabs,
    required this.error,
  });

  final UISettings ui;
  final List<JsonTab>? tabs;
  final String? error;

  @override
  Widget build(BuildContext context) {
    // Make Dart null safety happy
    final tabs = this.tabs;

    return DefaultTabController(
      length: tabs?.length ?? 0,
      initialIndex: ui.tabIndex.clamp(0, tabs?.length ?? 0),
      child: Scaffold(
        bottomNavigationBar: Builder(builder: (context) {
          return BottomAppBar(
            padding: EdgeInsets.zero,
            color: Theme.of(context).appBarTheme.backgroundColor,
            child: Row(
              children: [
                // Tabs from JSON
                Expanded(
                  child: TabBar(
                    labelPadding: const EdgeInsets.all(3.0),
                    onTap: (int index) {
                      ui.tabIndex = index;
                    },
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorWeight: 3.0,
                    tabs: [
                      for (final tab in tabs ?? <JsonTab>[])
                        Tab(
                          icon: Transform.scale(
                              scale: 1.5,
                              child: (tab.icon != null)
                                  ? UiIcon(jsonIcon: tab.icon!)
                                  : (tab.iconMaterial != null)
                                      ? Icon(tab.iconMaterial)
                                      : const SizedBox.shrink()),
                          text: tab.name,
                        )
                    ],
                  ),
                ),
                const VDivider(),
                // Settings button
                _SettingButton(ui: ui),
              ],
            ),
          );
        }),
        body: Builder(builder: (context) {
          final error = this.error;
          if (error != null) return Text(error);

          return TabBarView(
            children: (tabs ?? <JsonTab>[])
                .map((tab) => tab.widget.uiWidgetBuild(context, false))
                .toList(),
          );
        }),
      ),
    );
  }
}

class _SettingButton extends StatelessWidget {
  const _SettingButton({
    super.key,
    required this.ui,
  });

  final UISettings ui;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      color: Theme.of(context).appBarTheme.foregroundColor,
      tooltip: context.l10n.settings,
      icon: const Icon(Icons.settings),
      onPressed: () {
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (BuildContext context) {
              return Consumer<JsonData?>(
                builder: (context, jsonData, _) {
                  return SettingsDialog(
                    ui: ui,
                    supportedLanguages: jsonData?.supportedLanguages,
                    loadedModules: jsonData?.selectableModules,
                  );
                },
              );
            },
            fullscreenDialog: true));
      },
    );
  }
}
