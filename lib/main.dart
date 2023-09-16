import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nemesis_helper/ui/screen_settings.dart';
import 'package:nemesis_helper/ui/settings.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  // Wait for Flutter framework initialization
  WidgetsFlutterBinding.ensureInitialized();

  if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(250, 450));
    await windowManager.setSize(const Size(400, 700));
    await windowManager.center();
  }

  runApp(AppLoader(await SharedPreferences.getInstance()));
}

class AppLoader extends StatefulWidget {
  const AppLoader(this.preferences, {super.key});

  final SharedPreferences? preferences;

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  late UISettings _ui;

  @override
  void initState() {
    _ui = UISettings(widget.preferences);
    super.initState();
  }

  @override
  void dispose() {
    _ui.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _ui,
      child: Consumer<UISettings>(builder: (context, ui, child) {
        return MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          localizationsDelegates: const [
            LocaleNamesLocalizationsDelegate(),
            ...AppLocalizations.localizationsDelegates
          ],
          locale: ui.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
              surface: Colors.blueGrey.shade900,
              onSurface: Colors.blueGrey.shade100,
              background: Colors.blueGrey.shade900,
              onBackground: Colors.blueGrey.shade100,
            ),
          ),
          builder: (context, child) {
            final MediaQueryData data = MediaQuery.of(context);

            // Set proper localized title and show window (async, so not right away)
            windowManager.setTitle(AppLocalizations.of(context).appTitle);
            windowManager.waitUntilReadyToShow(null, () async {
              await windowManager.show();
              await windowManager.focus();
            });

            // Apply text scaling
            return MediaQuery(
              data: data.copyWith(
                  textScaleFactor: data.textScaleFactor * ui.scale,
                  alwaysUse24HourFormat: true),
              // Null will not happen since "home" is specified
              child: child ?? const Text("No MediaQuery child found"),
            );
          },
          home: App(ui),
        );
      }),
    );
  }
}

class App extends StatefulWidget {
  const App(this.ui, {super.key});

  final UISettings ui;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      initialIndex: widget.ui.tabIndex,
      child: SafeArea(
        child: Scaffold(
          bottomNavigationBar: Builder(builder: (context) {
            return BottomAppBar(
              padding: EdgeInsets.zero,
              color: Theme.of(context).appBarTheme.backgroundColor,
              child: Row(
                children: [
                  Expanded(
                    child: TabBar(
                      labelPadding: const EdgeInsets.all(4.0),
                      onTap: (int index) {
                        widget.ui.tabIndex = index;
                      },
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicatorWeight: 3.0,
                      tabs: [
                        Tab(
                          icon: const Icon(Icons.help_center_outlined),
                          text: AppLocalizations.of(context).reference,
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
                          builder: (BuildContext context) =>
                              const SettingsDialog(),
                          fullscreenDialog: true));
                    },
                  ),
                ],
              ),
            );
          }),
          body: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text("I'm a Reference"),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            child: const Icon(Icons.add),
            onPressed: () {},
          ),
        ),
      ),
    );
  }
}

class TabLabel extends StatelessWidget {
  const TabLabel(this.label, {Key? key}) : super(key: key);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label,
        softWrap: false,
        textScaleFactor: 1.0,
        style: const TextStyle(fontSize: 13));
  }
}
