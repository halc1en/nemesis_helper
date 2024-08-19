// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'package:nemesis_helper/db_cached.dart';
import 'package:nemesis_helper/l10n.dart';
import 'package:nemesis_helper/model/account.dart';
import 'package:nemesis_helper/model/json_data.dart';
import 'package:nemesis_helper/model/settings.dart';
import 'package:nemesis_helper/ui/scaffold_with_tabs.dart';

bool useWindowManager() {
  return !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);
}

void main() async {
  // Wait for Flutter framework initialization
  WidgetsFlutterBinding.ensureInitialized();

  SharedPreferences.setPrefix('');
  final sharedPreferences = SharedPreferences.getInstance();

  final supabaseInit = Supabase.initialize(
    url: 'https://crkiyacenvzsbetbmmyg.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNya2l5YWNlbnZ6c2JldGJtbXlnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDE3NzUyODMsImV4cCI6MjAxNzM1MTI4M30.dlpo_aVZ57dF_lOKd3WqW53iNycHTvG7jnz7SfszmK0',
  );

  if (useWindowManager()) {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(250, 450));
    await windowManager.setSize(const Size(400, 700));
    await windowManager.center();
  }

  await supabaseInit;
  runApp(AppLoader(await sharedPreferences));
}

class AppLoader extends StatefulWidget {
  const AppLoader(this.preferences, {super.key});

  final SharedPreferences? preferences;

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  late UISettings _ui;
  late Authentication _auth;
  late Future<DbCached> _db;
  Future<JsonData?>? _jsonDataFuture;

  @override
  void initState() {
    this._ui = UISettings(widget.preferences);
    this._auth = Authentication();

    // Start loading JSONs
    this._db = DbCached.build(this._ui);

    super.initState();
  }

  @override
  void dispose() {
    this._ui.dispose();
    this._auth.dispose();
    super.dispose();
  }

  Future<JsonData?> _loadJsonData(
      BuildContext context, Future<DbCached> dbFuture) async {
    final db = await dbFuture;
    final jsonData = await JsonData.fromJson(
        // ignore: use_build_context_synchronously
        context,
        this._ui,
        "data",
        db.openJson,
        db.openImage);

    // Update modules list for settings screen
    if (this._ui.selectedModules == null) {
      this._ui.selectedModulesSet(
          jsonData.selectableModules.map((m) => m.name).toList());
    }

    db.collectGarbage();

    return jsonData;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _ui,
      child: ChangeNotifierProvider.value(
        value: _auth,
        child: Consumer<UISettings>(builder: (context, ui, child) {
          const exo2Style = TextStyle(fontFamily: "Exo2", height: 1.3);
          const exo2textTheme = TextTheme(
            labelSmall: exo2Style,
            labelMedium: exo2Style,
            labelLarge: exo2Style,
            bodySmall: exo2Style,
            bodyMedium: exo2Style,
            bodyLarge: exo2Style,
            titleSmall: exo2Style,
            titleMedium: exo2Style,
            titleLarge: exo2Style,
            headlineSmall: exo2Style,
            headlineMedium: exo2Style,
            headlineLarge: exo2Style,
            displaySmall: exo2Style,
            displayMedium: exo2Style,
            displayLarge: exo2Style,
          );

          /* Make sure that App is rebuilt after reloading database */
          return FutureBuilder(
            future: this._jsonDataFuture,
            builder: (context, snapshot) {
              // If user changed UI settings we might need to reload JSON
              // (e.g. when language changed)
              if (snapshot.connectionState == ConnectionState.none ||
                  this._ui.reloadJson &&
                      snapshot.connectionState == ConnectionState.done) {
                SchedulerBinding.instance.addPostFrameCallback((_) {
                  final jsonFuture = _loadJsonData(context, this._db);
                  setState(() {
                    this._ui.reloadJson = false;
                    this._jsonDataFuture = jsonFuture;
                  });
                });
              }

              String? error;
              if (snapshot.hasError) {
                error = '${snapshot.error}\n${snapshot.stackTrace}';
              }

              final JsonData? jsonData = snapshot.data;

              return MaterialApp(
                onGenerateTitle: (context) => context.l10n.appTitle,
                localizationsDelegates: const [
                  LocaleNamesLocalizationsDelegate(),
                  ...AppLocalizations.localizationsDelegates
                ],
                locale: ui.locale,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: ThemeData(
                  useMaterial3: true,
                  visualDensity: VisualDensity.adaptivePlatformDensity
                      .copyWith(vertical: VisualDensity.compact.vertical),
                  brightness: Brightness.dark,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.blue,
                    brightness: Brightness.dark,
                    surface: Colors.blueGrey.shade900,
                    onSurface: Colors.blueGrey.shade100,
                  ),
                  primaryTextTheme: exo2textTheme,
                  textTheme: exo2textTheme,
                  listTileTheme:
                      const ListTileThemeData().copyWith(dense: true),
                  expansionTileTheme: const ExpansionTileThemeData().copyWith(
                    expandedAlignment: Alignment.centerLeft,
                    collapsedShape:
                        const Border.fromBorderSide(BorderSide.none),
                    shape: const Border.fromBorderSide(BorderSide.none),
                  ),
                ),
                builder: (context, child) {
                  final MediaQueryData data = MediaQuery.of(context);

                  if (useWindowManager()) {
                    // Set proper localized title and show window (async, so not right away)
                    windowManager.setTitle(context.l10n.appTitle);
                    windowManager.waitUntilReadyToShow(null, () async {
                      await windowManager.show();
                      await windowManager.focus();
                    });
                  }

                  // Apply text scaling
                  return MediaQuery(
                    data:
                        data.copyWith(textScaler: TextScaler.linear(ui.scale)),

                    // [JsonData] is accessed from settings screen which
                    // is on different Route so provider should be inserted
                    // here rather than in `home`.
                    child: ChangeNotifierProvider<JsonData?>.value(
                        value: jsonData,
                        // Null will not happen since "home" is specified
                        child:
                            child ?? const Text("No MediaQuery child found")),
                  );
                },
                home: SafeArea(
                  child: ChangeNotifierProvider.value(
                    value: _auth,
                    child: ScaffoldWithTabs(
                        ui: ui, tabs: jsonData?.tabs, error: error),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
