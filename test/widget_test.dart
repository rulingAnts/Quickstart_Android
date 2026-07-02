import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wordlist_elicitation/models/wordlist_entry.dart';
import 'package:wordlist_elicitation/providers/wordlist_provider.dart';
import 'package:wordlist_elicitation/screens/home_screen.dart';
import 'package:wordlist_elicitation/services/database_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseService.databaseName = 'test_widget.db';
    await DatabaseService.instance.close();
    await deleteDatabase(
        p.join(await getDatabasesPath(), DatabaseService.databaseName));
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    await deleteDatabase(
        p.join(await getDatabasesPath(), DatabaseService.databaseName));
  });

  /// Pumps the home screen with a provider whose state was loaded with real
  /// async IO (via [WidgetTester.runAsync]) before entering fake-async land.
  Future<void> pumpHome(WidgetTester tester, WordlistProvider provider) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('home screen renders with an empty wordlist', (tester) async {
    final provider = WordlistProvider();
    await tester.runAsync(provider.loadWordlist);

    await pumpHome(tester, provider);

    expect(find.text('Comparative Wordlist\nElicitation Tool'), findsOneWidget);
    expect(find.text('Import Wordlist'), findsOneWidget);
    expect(find.text('Start Elicitation'), findsOneWidget);
    expect(find.text('Export Data'), findsOneWidget);
    // Nothing imported yet.
    expect(find.text('0'), findsWidgets);
  });

  testWidgets('progress card reflects imported entries', (tester) async {
    await tester.runAsync(() async {
      await DatabaseService.instance.replaceAllEntries([
        WordlistEntry(reference: '0001', gloss: 'body'),
        WordlistEntry(
          reference: '0002',
          gloss: 'head',
          localTranscription: 'kɛpa',
          isCompleted: true,
        ),
      ]);
    });

    final provider = WordlistProvider();
    await tester.runAsync(provider.loadWordlist);

    await pumpHome(tester, provider);

    expect(find.text('2'), findsOneWidget); // total
    expect(find.text('1'), findsNWidgets(2)); // completed + remaining

    // Session resume: the current entry is the first incomplete one.
    expect(provider.currentEntry!.reference, '0001');
  });
}
