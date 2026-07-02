import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wordlist_elicitation/models/consent_record.dart';
import 'package:wordlist_elicitation/models/wordlist_entry.dart';
import 'package:wordlist_elicitation/services/database_service.dart';

WordlistEntry entry(String reference, String gloss) =>
    WordlistEntry(reference: reference, gloss: gloss);

Future<String> dbPath() async =>
    p.join(await getDatabasesPath(), DatabaseService.databaseName);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseService.databaseName = 'test_wordlist_elicitation.db';
    await DatabaseService.instance.close();
    await deleteDatabase(await dbPath());
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    await deleteDatabase(await dbPath());
  });

  group('inserting entries', () {
    test('auto-assigns distinct row ids (the id:0 duplicate-import bug)',
        () async {
      final db = DatabaseService.instance;
      final id1 = await db.insertWordlistEntry(entry('0001', 'body'));
      final id2 = await db.insertWordlistEntry(entry('0002', 'head'));

      expect(id1, isNot(0));
      expect(id2, isNot(id1));

      final all = await db.getAllWordlistEntries();
      expect(all.length, 2);
      expect(all.map((e) => e.id).toSet().length, 2);
    });

    test('rejects duplicate references via the unique index', () async {
      final db = DatabaseService.instance;
      await db.insertWordlistEntry(entry('0001', 'body'));
      expect(
        () => db.insertWordlistEntry(entry('0001', 'body again')),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('replaceAllEntries', () {
    test('imports a full list in one transaction', () async {
      final db = DatabaseService.instance;
      final entries =
          List.generate(500, (i) => entry('${i + 1}'.padLeft(4, '0'), 'w$i'));
      final imported = await db.replaceAllEntries(entries);
      expect(imported, 500);
      expect(await db.getTotalCount(), 500);
    });

    test('re-import does not duplicate entries', () async {
      final db = DatabaseService.instance;
      final entries = [entry('0001', 'body'), entry('0002', 'head')];
      await db.replaceAllEntries(entries);
      await db.replaceAllEntries(entries);
      await db.replaceAllEntries(entries);

      expect(await db.getTotalCount(), 2);
    });

    test('ignores in-batch duplicate references (first wins)', () async {
      final db = DatabaseService.instance;
      final imported = await db.replaceAllEntries([
        entry('0001', 'body'),
        entry('0001', 'corpse'),
        entry('0002', 'head'),
      ]);
      expect(imported, 2);
      final all = await db.getAllWordlistEntries();
      expect(all.first.gloss, 'body');
    });
  });

  group('mergeEntries', () {
    test('preserves collected data while updating wordlist fields', () async {
      final db = DatabaseService.instance;
      await db.replaceAllEntries([entry('0001', 'body')]);

      // Speaker records data.
      final saved = (await db.getAllWordlistEntries()).single.copyWith(
            localTranscription: 'bɔdi',
            audioFilename: '0001body.wav',
            isCompleted: true,
            recordedAt: DateTime(2026, 7, 1),
          );
      await db.updateWordlistEntry(saved);

      // Researcher ships an updated wordlist with a corrected gloss and a
      // brand-new entry.
      final updated = WordlistEntry(
        reference: '0001',
        gloss: 'body (whole)',
        glossIndonesian: 'tubuh',
      );
      final affected =
          await db.mergeEntries([updated, entry('0002', 'head')]);
      expect(affected, 2);

      final all = await db.getAllWordlistEntries();
      expect(all.length, 2);

      final merged = all.firstWhere((e) => e.reference == '0001');
      expect(merged.gloss, 'body (whole)'); // updated
      expect(merged.glossIndonesian, 'tubuh'); // updated
      expect(merged.localTranscription, 'bɔdi'); // preserved
      expect(merged.audioFilename, '0001body.wav'); // preserved
      expect(merged.isCompleted, true); // preserved
    });

    test('restores incoming collected data when this device has none',
        () async {
      final db = DatabaseService.instance;
      await db.replaceAllEntries([entry('0001', 'body')]);

      // Merging an exported backup that already contains a transcription.
      final fromBackup = WordlistEntry(
        reference: '0001',
        gloss: 'body',
        localTranscription: 'bɔdi',
        isCompleted: true,
      );
      await db.mergeEntries([fromBackup]);

      final restored = (await db.getAllWordlistEntries()).single;
      expect(restored.localTranscription, 'bɔdi');
      expect(restored.isCompleted, true);
    });
  });

  group('schema migration v1 -> v2', () {
    test('upgrades old databases and removes duplicate references', () async {
      // Create a database with the original v1 schema and buggy duplicates.
      final path = await dbPath();
      final v1 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE wordlist_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                reference TEXT NOT NULL,
                gloss TEXT NOT NULL,
                local_transcription TEXT,
                audio_filename TEXT,
                picture_filename TEXT,
                recorded_at TEXT,
                is_completed INTEGER DEFAULT 0
              )
            ''');
            await db.execute('''
              CREATE TABLE consent_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                device_id TEXT NOT NULL,
                type TEXT NOT NULL,
                response TEXT NOT NULL,
                verbal_consent_filename TEXT
              )
            ''');
          },
        ),
      );
      await v1.insert('wordlist_entries', {
        'reference': '0001',
        'gloss': 'body',
        'local_transcription': 'bɔdi',
        'is_completed': 1,
      });
      await v1.insert('wordlist_entries', {
        'reference': '0001',
        'gloss': 'body duplicate',
      });
      await v1.insert('wordlist_entries', {
        'reference': '0002',
        'gloss': 'head',
      });
      await v1.close();

      // Opening through the service runs the migration.
      final db = DatabaseService.instance;
      final all = await db.getAllWordlistEntries();

      expect(all.length, 2); // duplicate removed
      final body = all.firstWhere((e) => e.reference == '0001');
      expect(body.gloss, 'body'); // first occurrence kept
      expect(body.localTranscription, 'bɔdi'); // data survived

      // New columns are writable and the unique index is active.
      await db.updateWordlistEntry(
          body.copyWith(glossIndonesian: 'tubuh', soundFile: '0001body.wav'));
      expect(
        () => db.insertWordlistEntry(entry('0002', 'clash')),
        throwsA(isA<DatabaseException>()),
      );

      // Device id storage works on the migrated database.
      final deviceId = await db.getOrCreateDeviceId();
      expect(deviceId, isNotEmpty);
      expect(await db.getOrCreateDeviceId(), deviceId);
    });
  });

  group('consent records', () {
    test('stores and retrieves consent with assent gating', () async {
      final db = DatabaseService.instance;
      expect(await db.hasAssent(), false);

      await db.insertConsentRecord(ConsentRecord(
        timestamp: DateTime(2026, 7, 1, 10),
        deviceId: 'device-1',
        type: ConsentType.written,
        response: ConsentResponse.decline,
      ));
      expect(await db.hasAssent(), false);

      await db.insertConsentRecord(ConsentRecord(
        timestamp: DateTime(2026, 7, 1, 11),
        deviceId: 'device-1',
        type: ConsentType.verbal,
        response: ConsentResponse.assent,
        verbalConsentFilename: 'consent_20260701_110000.wav',
      ));
      expect(await db.hasAssent(), true);

      final latest = await db.getLatestConsentRecord();
      expect(latest!.type, ConsentType.verbal);
      expect(latest.verbalConsentFilename, 'consent_20260701_110000.wav');
      expect(latest.id, isNotNull);
    });
  });
}
