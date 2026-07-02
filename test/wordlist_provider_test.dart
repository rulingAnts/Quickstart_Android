import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wordlist_elicitation/models/wordlist_entry.dart';
import 'package:wordlist_elicitation/providers/wordlist_provider.dart';
import 'package:wordlist_elicitation/services/database_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseService.databaseName = 'test_provider.db';
    await DatabaseService.instance.close();
    await deleteDatabase(
        p.join(await getDatabasesPath(), DatabaseService.databaseName));
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    await deleteDatabase(
        p.join(await getDatabasesPath(), DatabaseService.databaseName));
  });

  Future<void> seed(List<WordlistEntry> entries) =>
      DatabaseService.instance.replaceAllEntries(entries);

  group('WordlistProvider', () {
    test('loads entries ordered by reference', () async {
      await seed([
        WordlistEntry(reference: '0002', gloss: 'head'),
        WordlistEntry(reference: '0001', gloss: 'body'),
      ]);

      final provider = WordlistProvider();
      await provider.loadWordlist();

      expect(provider.totalCount, 2);
      expect(provider.entries[0].reference, '0001');
      expect(provider.currentEntry!.reference, '0001');
    });

    test('resumes at the first incomplete entry', () async {
      await seed([
        WordlistEntry(reference: '0001', gloss: 'body'),
        WordlistEntry(reference: '0002', gloss: 'head'),
        WordlistEntry(reference: '0003', gloss: 'eye'),
      ]);
      final db = DatabaseService.instance;
      final all = await db.getAllWordlistEntries();
      await db.updateWordlistEntry(all[0].copyWith(
        localTranscription: 'bɔdi',
        isCompleted: true,
      ));

      final provider = WordlistProvider();
      await provider.loadWordlist();

      expect(provider.currentIndex, 1);
      expect(provider.currentEntry!.reference, '0002');
      expect(provider.completedCount, 1);
    });

    test('navigation respects bounds', () async {
      await seed([
        WordlistEntry(reference: '0001', gloss: 'body'),
        WordlistEntry(reference: '0002', gloss: 'head'),
      ]);
      final provider = WordlistProvider();
      await provider.loadWordlist();

      expect(provider.hasPrevious, false);
      provider.previousEntry();
      expect(provider.currentIndex, 0);

      provider.nextEntry();
      expect(provider.currentIndex, 1);
      expect(provider.hasNext, false);
      provider.nextEntry();
      expect(provider.currentIndex, 1);
    });

    test('markCurrentAsCompleted persists and preserves existing audio',
        () async {
      await seed([WordlistEntry(reference: '0001', gloss: 'body')]);
      final provider = WordlistProvider();
      await provider.loadWordlist();

      await provider.markCurrentAsCompleted(
        transcription: 'bɔdi',
        audioFilename: '0001body.wav',
      );

      var stored =
          (await DatabaseService.instance.getAllWordlistEntries()).single;
      expect(stored.localTranscription, 'bɔdi');
      expect(stored.audioFilename, '0001body.wav');
      expect(stored.isCompleted, true);

      // Saving again with a changed transcription but no new audio keeps
      // the earlier recording.
      await provider.markCurrentAsCompleted(transcription: 'bɔːdi');
      stored =
          (await DatabaseService.instance.getAllWordlistEntries()).single;
      expect(stored.localTranscription, 'bɔːdi');
      expect(stored.audioFilename, '0001body.wav');
    });

    test('clearWordlist empties the database and state', () async {
      await seed([WordlistEntry(reference: '0001', gloss: 'body')]);
      final provider = WordlistProvider();
      await provider.loadWordlist();

      await provider.clearWordlist();
      expect(provider.totalCount, 0);
      expect(provider.currentEntry, isNull);
      expect(await DatabaseService.instance.getTotalCount(), 0);
    });
  });
}
