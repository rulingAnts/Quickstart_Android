import 'package:flutter/material.dart';

import 'screens/health_screen.dart';
import 'screens/placeholder_screen.dart';

void main() {
  runApp(const CompanionApp());
}

/// Dekereke Companion — desktop scaffold (backlog #4, plan §3).
///
/// The Health check screen is already functional (it runs
/// `dekereke_core`'s parser and health rules against a real database
/// file); History (P1) and Sync (P2) are placeholders that state what
/// they will do. No git/VCS vocabulary anywhere, per the requirements.
class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dekereke Companion',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const CompanionHome(),
    );
  }
}

class CompanionHome extends StatefulWidget {
  const CompanionHome({super.key});

  @override
  State<CompanionHome> createState() => _CompanionHomeState();
}

class _CompanionHomeState extends State<CompanionHome> {
  int _selected = 0;

  static const _destinations = [
    NavigationRailDestination(
      icon: Icon(Icons.health_and_safety_outlined),
      selectedIcon: Icon(Icons.health_and_safety),
      label: Text('Health check'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history),
      label: Text('History'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.sync_outlined),
      selectedIcon: Icon(Icons.sync),
      label: Text('Sync'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final body = switch (_selected) {
      0 => const HealthScreen(),
      1 => const PlaceholderScreen(
          icon: Icons.history,
          title: 'History',
          description:
              'Every time you save in Dekereke, the Companion will keep a '
              'checkpoint automatically — like "Saved by Seth, 3 words '
              'changed" — and let you bring back the whole database or a '
              'single word from any point in time. It will also tidy away '
              'Dekereke\'s DK-Backup files.\n\nComing in the next phase.',
        ),
      _ => const PlaceholderScreen(
          icon: Icons.sync,
          title: 'Sync',
          description:
              'Share a database with colleagues: your changes and theirs '
              'are combined word by word, disagreements are shown in plain '
              'language for you to settle, and recordings travel along. '
              'Colleagues join with a one-time invite link — no accounts '
              'needed.\n\nComing after History.',
        ),
    };

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selected,
            onDestinationSelected: (index) =>
                setState(() => _selected = index),
            labelType: NavigationRailLabelType.all,
            destinations: _destinations,
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}
