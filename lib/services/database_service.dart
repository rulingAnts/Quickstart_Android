import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/wordlist_entry.dart';
import '../models/consent_record.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  /// Overridable for tests (sqflite_common_ffi uses a plain temp path).
  static String databaseName = 'wordlist_elicitation.db';

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(databaseName);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE wordlist_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reference TEXT NOT NULL,
        gloss TEXT NOT NULL,
        gloss_indonesian TEXT,
        gloss_tok_pisin TEXT,
        category TEXT,
        semantic_domain TEXT,
        sound_file TEXT,
        picture_filename TEXT,
        local_transcription TEXT,
        audio_filename TEXT,
        recorded_at TEXT,
        is_completed INTEGER DEFAULT 0,
        xml_fields TEXT
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_entries_reference ON wordlist_entries(reference)',
    );

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

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      for (final column in [
        'gloss_indonesian TEXT',
        'gloss_tok_pisin TEXT',
        'category TEXT',
        'semantic_domain TEXT',
        'sound_file TEXT',
        'xml_fields TEXT',
      ]) {
        await db.execute('ALTER TABLE wordlist_entries ADD COLUMN $column');
      }
      // Remove duplicate references (keep the lowest id) so the unique
      // index can be created.
      await db.execute('''
        DELETE FROM wordlist_entries WHERE id NOT IN (
          SELECT MIN(id) FROM wordlist_entries GROUP BY reference
        )
      ''');
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_entries_reference '
        'ON wordlist_entries(reference)',
      );
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
  }

  // Wordlist Entry CRUD operations

  Future<int> insertWordlistEntry(WordlistEntry entry) async {
    final db = await database;
    return await db.insert('wordlist_entries', entry.toMap());
  }

  /// Deletes all entries and inserts [entries] in a single transaction.
  /// Duplicate references within the batch keep the first occurrence.
  Future<int> replaceAllEntries(List<WordlistEntry> entries) async {
    final db = await database;
    var inserted = 0;
    await db.transaction((txn) async {
      await txn.delete('wordlist_entries');
      for (final entry in entries) {
        final count = await txn.insert(
          'wordlist_entries',
          entry.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (count != 0) inserted++;
      }
    });
    return inserted;
  }

  /// Upserts [entries] by reference, updating wordlist fields while
  /// preserving collected data (transcription, audio, completion state).
  /// Returns the number of entries inserted or updated.
  ///
  /// Implemented as query-then-update because Android 6-10 ship SQLite
  /// versions without ON CONFLICT DO UPDATE support.
  Future<int> mergeEntries(List<WordlistEntry> entries) async {
    final db = await database;
    var affected = 0;
    await db.transaction((txn) async {
      for (final entry in entries) {
        final existing = await txn.query(
          'wordlist_entries',
          where: 'reference = ?',
          whereArgs: [entry.reference],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert('wordlist_entries', entry.toMap(),
              conflictAlgorithm: ConflictAlgorithm.ignore);
          affected++;
        } else {
          final current = WordlistEntry.fromMap(existing.first);
          final merged = entry.copyWith(
            id: current.id,
            localTranscription: current.localTranscription,
            audioFilename: current.audioFilename,
            recordedAt: current.recordedAt,
            isCompleted: current.isCompleted,
          );
          await txn.update(
            'wordlist_entries',
            merged.toMap(),
            where: 'id = ?',
            whereArgs: [current.id],
          );
          affected++;
        }
      }
    });
    return affected;
  }

  Future<List<WordlistEntry>> getAllWordlistEntries() async {
    final db = await database;
    final result = await db.query('wordlist_entries', orderBy: 'reference ASC');
    return result.map((map) => WordlistEntry.fromMap(map)).toList();
  }

  Future<WordlistEntry?> getWordlistEntry(int id) async {
    final db = await database;
    final result = await db.query(
      'wordlist_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return WordlistEntry.fromMap(result.first);
  }

  Future<int> updateWordlistEntry(WordlistEntry entry) async {
    if (entry.id == null) {
      throw ArgumentError('Cannot update an entry without an id');
    }
    final db = await database;
    return await db.update(
      'wordlist_entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<int> deleteWordlistEntry(int id) async {
    final db = await database;
    return await db.delete(
      'wordlist_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAllWordlistEntries() async {
    final db = await database;
    await db.delete('wordlist_entries');
  }

  // Consent Record operations

  Future<int> insertConsentRecord(ConsentRecord record) async {
    final db = await database;
    return await db.insert('consent_records', record.toMap());
  }

  Future<List<ConsentRecord>> getAllConsentRecords() async {
    final db = await database;
    final result = await db.query('consent_records', orderBy: 'timestamp DESC');
    return result.map((map) => ConsentRecord.fromMap(map)).toList();
  }

  Future<ConsentRecord?> getLatestConsentRecord() async {
    final db = await database;
    final result = await db.query(
      'consent_records',
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return ConsentRecord.fromMap(result.first);
  }

  /// Whether the speaker has given (and not since withdrawn) consent.
  Future<bool> hasAssent() async {
    final latest = await getLatestConsentRecord();
    return latest?.response == ConsentResponse.assent;
  }

  // App settings

  Future<String?> getSetting(String key) async {
    final db = await database;
    final result = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return result.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Stable random identifier for this device/installation, generated once
  /// and reused for consent records.
  Future<String> getOrCreateDeviceId() async {
    final existing = await getSetting('device_id');
    if (existing != null) return existing;
    final rng = Random.secure();
    final id = List.generate(16, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await setSetting('device_id', id);
    return id;
  }

  // Utility

  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  Future<int> getCompletedCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM wordlist_entries WHERE is_completed = 1',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getTotalCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM wordlist_entries',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
