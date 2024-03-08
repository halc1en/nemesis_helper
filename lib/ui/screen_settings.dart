import 'package:flutter/foundation.dart';
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
    final textTheme = Theme.of(context).textTheme;
    const divider = Divider(thickness: 1.5, endIndent: 0.0, height: 1.5);

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).settings)),
      body: ListView(
        children: [
          _ModulesConfig(textTheme, loadedModules),
          divider,
          _LanguageConfig(textTheme, supportedLanguages),
          divider,
          _ScaleConfig(textTheme),
          ...(kDebugMode ? [divider, _OfflineModeConfig(textTheme)] : [])
        ],
      ),
    );
  }
}

class _ModulesConfig extends StatelessWidget {
  const _ModulesConfig(
    this.textTheme,
    this.loadedModules, {
    super.key,
  });

  final TextTheme textTheme;
  final List<Module>? loadedModules;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(AppLocalizations.of(context).modules,
          style: textTheme.bodyMedium),
      subtitle: Consumer<UISettings>(
        builder: (context, ui, child) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: (loadedModules ?? [])
              .map((module) => CheckboxListTile.adaptive(
                  tristate: false,
                  title: Text(module.description, style: textTheme.bodyMedium),
                  value:
                      ui.selectedModules?.any((m) => m == module.name) ?? false,
                  onChanged: (bool? value) {
                    if (value == true) {
                      ui.selectedModulesAdd(module.name);
                    } else {
                      ui.selectedModulesRemove(module.name);
                    }
                  }))
              .toList(),
        ),
      ),
    );
  }
}

class _LanguageConfig extends StatelessWidget {
  const _LanguageConfig(this.textTheme, this.supportedLanguages, {super.key});

  final TextTheme textTheme;
  final List<String>? supportedLanguages;

  @override
  Widget build(BuildContext context) {
    return Consumer<UISettings>(
      builder: (context, ui, child) => ListTile(
        title: Wrap(
          clipBehavior: Clip.hardEdge,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(AppLocalizations.of(context).language,
                style: textTheme.bodyMedium),
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
                          LocaleNames.of(context)?.nameOf(locale.toString()) ??
                              AppLocalizations.of(context).languageSystem,
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScaleConfig extends StatelessWidget {
  const _ScaleConfig(this.textTheme, {super.key});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Consumer<UISettings>(
      builder: (context, ui, child) => ListTile(
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(AppLocalizations.of(context).scale,
                style: textTheme.bodyMedium),
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
        subtitle: Text(AppLocalizations.of(context).scaleDescription,
            style: textTheme.labelMedium),
      ),
    );
  }
}

class _OfflineModeConfig extends StatelessWidget {
  const _OfflineModeConfig(this.textTheme, {super.key});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Consumer<UISettings>(
      builder: (context, ui, child) => ListTile(
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(AppLocalizations.of(context).offlineMode,
                style: textTheme.bodyMedium),
            Switch.adaptive(
                value: ui.offline,
                onChanged: (value) {
                  ui.offline = value;
                }),
          ],
        ),
      ),
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
          bottom: BorderSide(color: Color(0xFFBDBDBD), width: 1.5),
        ),
      ),
    );
  }
}
