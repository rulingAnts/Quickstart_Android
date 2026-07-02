import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'providers/wordlist_provider.dart';

void main() {
  runApp(const WordlistElicitationApp());
}

class WordlistElicitationApp extends StatelessWidget {
  const WordlistElicitationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WordlistProvider()),
      ],
      child: MaterialApp(
        title: 'Wordlist Elicitation Tool',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          // High contrast for fieldwork environments
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'), // English
          Locale('id'), // Indonesian
          Locale('es'), // Spanish
          Locale('fr'), // French
          Locale('pt'), // Portuguese
          // Add more locales as needed
        ],
        home: const HomeScreen(),
      ),
    );
  }
}
