import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';

import 'package:nemesis_helper/model/json_data.dart';
import 'package:nemesis_helper/model/settings.dart';

class SettingsDialog extends StatelessWidget {
  const SettingsDialog(
      {super.key,
      required this.supportedLanguages,
      required this.loadedModules});

  final List<String>? supportedLanguages;
  final List<Module>? loadedModules;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).settings),
      ),
      body: Consumer<UISettings>(builder: (context, ui, child) {
        final textTheme = Theme.of(context).textTheme;
        return ListView(children: [
          ListTile(
            title: Text(
              AppLocalizations.of(context).modules,
              style: textTheme.bodyMedium,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: loadedModules?.map((module) {
                    return CheckboxListTile.adaptive(
                        tristate: false,
                        title: Text(
                          module.description,
                          style: textTheme.bodyMedium,
                        ),
                        value:
                            ui.selectedModules?.any((m) => m == module.name) ??
                                false,
                        onChanged: (bool? value) {
                          if (value == true) {
                            ui.selectedModulesAdd(module.name);
                          } else {
                            ui.selectedModulesRemove(module.name);
                          }
                        });
                  }).toList() ??
                  [],
            ),
          ),
          const Divider(thickness: 1.5, endIndent: 0.0, height: 1.5),
          ListTile(
            title: Wrap(
              clipBehavior: Clip.hardEdge,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  AppLocalizations.of(context).language,
                  style: textTheme.bodyMedium,
                ),
                DropdownButton(
                  underline: const Underline(),
                  value: ui.locale,
                  onChanged: (Locale? v) => ui.locale = v,
                  items: <Locale?>[
                    null,
                    ...this.supportedLanguages?.map((ln) => Locale(ln)) ??
                        WidgetsBinding.instance.platformDispatcher.locales
                  ]
                      .map((Locale? locale) => DropdownMenuItem<Locale>(
                            value: locale,
                            child: Text(
                              LocaleNames.of(context)
                                      ?.nameOf(locale.toString()) ??
                                  AppLocalizations.of(context).languageSystem,
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          const Divider(thickness: 1.5, endIndent: 0.0, height: 1.5),
          ListTile(
            subtitle: Text(
              AppLocalizations.of(context).scaleDescription,
              style: textTheme.labelMedium,
            ),
            title: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  AppLocalizations.of(context).scale,
                  style: textTheme.bodyMedium,
                ),
                DropdownButton(
                  underline: const Underline(),
                  value: (ui.scale * 10).round(),
                  onChanged: (int? v) {
                    if (v != null) {
                      ui.scale = v.toDouble() / 10;
                    }
                  },
                  items: <int>[
                    for (int i = (UISettings.scaleMin * 10).round();
                        i <= (UISettings.scaleMax * 10).round();
                        i++)
                      i
                  ]
                      .map((int scale) => DropdownMenuItem<int>(
                          value: scale,
                          child: Text((scale.toDouble() / 10).toString())))
                      .toList(),
                ),
              ],
            ),
          ),
        ]);
      }),
    );
  }
}

class Underline extends StatelessWidget {
  const Underline({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.0,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFBDBDBD),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
