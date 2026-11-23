import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'screens/home_screen.dart';

void main() => runApp(const GsScanNotesApp());

class GsScanNotesApp extends StatefulWidget {
  const GsScanNotesApp({super.key});

  @override
  State<GsScanNotesApp> createState() => _GsScanNotesAppState();
}

class _GsScanNotesAppState extends State<GsScanNotesApp> {
  final AppState _state = AppState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'GS Scan Notes',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF00695C),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
