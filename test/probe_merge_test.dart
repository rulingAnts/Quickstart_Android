import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wordlist_elicitation/models/wordlist_entry.dart';
import 'package:wordlist_elicitation/services/database_service.dart';

Future<String> dbPath() async =>
    p.join(await getDatabasesPath(), DatabaseService.databaseName);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseService.databaseName = 'probe_merge.db';
    await DatabaseService.instance.close();
    await deleteDatabase(await dbPath());
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    await deleteDatabase(await dbPath());
  });

  test('probe merge isCompleted', () async {
    final db = DatabaseService.instance;
    await db.replaceAllEntries(
        [WordlistEntry(reference: '0001', gloss: 'body')]);

    final fromBackup = WordlistEntry(
      reference: '0001',
      gloss: 'body',
      localTranscription: 'bɔdi',
      isCompleted: true,
    );
    await db.mergeEntries([fromBackup]);

    final restored = (await db.getAllWordlistEntries()).single;
    // ignore: avoid_print
    print('PROBE restored.localTranscription=${restored.localTranscription} '
        'isCompleted=${restored.isCompleted} recordedAt=${restored.recordedAt}');
  });
}
