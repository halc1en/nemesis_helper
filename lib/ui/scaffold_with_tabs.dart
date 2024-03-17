import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'package:nemesis_helper/model/json_data.dart';
import 'package:nemesis_helper/model/settings.dart';
import 'package:nemesis_helper/ui/screen_reference.dart';
import 'package:nemesis_helper/ui/screen_settings.dart';

class ScaffoldWithTabs extends StatelessWidget {
  const ScaffoldWithTabs({
    super.key,
    required this.ui,
    required this.error,
  });

  final UISettings ui;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: ui.tabIndex,
      child: Scaffold(
        bottomNavigationBar: Builder(builder: (context) {
          return BottomAppBar(
            padding: EdgeInsets.zero,
            color: Theme.of(context).appBarTheme.backgroundColor,
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    labelPadding: const EdgeInsets.all(3.0),
                    onTap: (int index) {
                      ui.tabIndex = index;
                    },
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorWeight: 3.0,
                    tabs: [
                      Tab(
                        icon: Transform.scale(
                            scale: 1.5,
                            child: const Icon(Icons.help_center_outlined)),
                        text: AppLocalizations.of(context).reference,
                      ),
                      Tab(
                        icon: Transform.scale(
                            scale: 1.5,
                            child: const Icon(Icons.text_snippet_outlined)),
                        text: AppLocalizations.of(context).playSession,
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(
                    thickness: 1.5, endIndent: 0.0, width: 1.5),
                IconButton(
                  color: Theme.of(context).appBarTheme.foregroundColor,
                  tooltip: AppLocalizations.of(context).settings,
                  icon: const Icon(Icons.settings),
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (BuildContext context) {
                          return Consumer<JsonData?>(
                            builder: (context, jsonData, _) {
                              return SettingsDialog(
                                supportedLanguages:
                                    jsonData?.supportedLanguages,
                                loadedModules: jsonData?.selectableModules,
                              );
                            },
                          );
                        },
                        fullscreenDialog: true));
                  },
                ),
              ],
            ),
          );
        }),
        body: Builder(builder: (context) {
          final error = this.error;
          if (error != null) return Text(error);

          return TabBarView(children: [
            Consumer<JsonData?>(
              builder: (context, jsonData, _) =>
                  Reference(ui: ui, reference: jsonData?.reference),
            ),
            const SizedBox.shrink(),
          ]);
        }),
      ),
    );
  }
}
