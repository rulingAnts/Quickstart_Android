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
    DatabaseService.databaseName = 'probe_merge2.db';
    await DatabaseService.instance.close();
    await deleteDatabase(await dbPath());
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    await deleteDatabase(await dbPath());
  });

  test('probe merge internals', () async {
    final db = DatabaseService.instance;
    await db.replaceAllEntries(
        [WordlistEntry(reference: '0001', gloss: 'body')]);

    final raw = await (await db.database).query('wordlist_entries');
    // ignore: avoid_print
    print('PROBE after replaceAll rows=$raw');

    final handle = await db.database;
    final existing = await handle.query(
      'wordlist_entries',
      where: 'reference = ?',
      whereArgs: ['0001'],
      limit: 1,
    );
    // ignore: avoid_print
    print('PROBE existing=$existing');

    final fromBackup = WordlistEntry(
      reference: '0001',
      gloss: 'body',
      localTranscription: 'bɔdi',
      isCompleted: true,
    );
    final n = await db.mergeEntries([fromBackup]);
    // ignore: avoid_print
    print('PROBE mergeEntries affected=$n');

    final after = await (await db.database).query('wordlist_entries');
    // ignore: avoid_print
    print('PROBE after merge rows=$after');
  });
}
