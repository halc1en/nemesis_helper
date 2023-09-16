import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';

import 'package:nemesis_helper/ui/settings.dart';

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).settings),
      ),
      body: Consumer<UISettings>(builder: (context, ui, child) {
        return ListView(children: [
          ListTile(
            title: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(AppLocalizations.of(context).language),
                DropdownButton(
                  underline: const Underline(),
                  value: ui.locale,
                  onChanged: (Locale? v) => ui.locale = v,
                  items: <Locale?>[
                    null,
                    ...WidgetsBinding.instance.window.locales
                  ]
                      .map((Locale? locale) => DropdownMenuItem<Locale>(
                          value: locale,
                          child: Text(LocaleNames.of(context)
                                  ?.nameOf(locale.toString()) ??
                              AppLocalizations.of(context).languageSystem)))
                      .toList(),
                ),
              ],
            ),
          ),
          ListTile(
            subtitle: Text(AppLocalizations.of(context).scaleDescription),
            title: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(AppLocalizations.of(context).scale),
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
