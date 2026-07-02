import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wordlist_elicitation/models/consent_record.dart';
import 'package:wordlist_elicitation/models/wordlist_entry.dart';
import 'package:wordlist_elicitation/services/database_service.dart';
import 'package:wordlist_elicitation/services/export_service.dart';
import 'package:wordlist_elicitation/services/xml_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseService.databaseName = 'test_export.db';
    await DatabaseService.instance.close();
    await deleteDatabase(
        p.join(await getDatabasesPath(), DatabaseService.databaseName));
    tempDir = await Directory.systemTemp.createTemp('export_test');
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    await deleteDatabase(
        p.join(await getDatabasesPath(), DatabaseService.databaseName));
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('export produces a flat ZIP with XML, audio, consent log, README',
      () async {
    final db = DatabaseService.instance;
    await db.replaceAllEntries([
      WordlistEntry(
        reference: '0001',
        gloss: 'body',
        soundFile: '0001body.wav',
      ),
    ]);
    final saved = (await db.getAllWordlistEntries()).single.copyWith(
          localTranscription: 'bɔdi',
          audioFilename: '0001body.wav',
          isCompleted: true,
        );
    await db.updateWordlistEntry(saved);

    await db.insertConsentRecord(ConsentRecord(
      timestamp: DateTime(2026, 7, 1),
      deviceId: 'device-1',
      type: ConsentType.written,
      response: ConsentResponse.assent,
    ));

    // Simulate a recorded WAV file, plus leftovers that must NOT be
    // exported: a recording from a replaced wordlist and an unsaved take
    // in the temp directory.
    final audioDir = Directory('${tempDir.path}/audio');
    await audioDir.create(recursive: true);
    await File('${audioDir.path}/0001body.wav')
        .writeAsBytes(List.filled(64, 1));
    await File('${audioDir.path}/9999stale.wav')
        .writeAsBytes(List.filled(64, 2));
    final tmpTakes = Directory('${audioDir.path}/tmp');
    await tmpTakes.create();
    await File('${tmpTakes.path}/0001body.wav')
        .writeAsBytes(List.filled(64, 3));

    final service = ExportService(baseDirectoryOverride: tempDir);
    final zipPath = await service.exportData();

    expect(await File(zipPath).exists(), true);

    final archive =
        ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    final names = archive.files.map((f) => f.name).toSet();

    // Contents are at the archive root, not nested in export_temp/.
    expect(names, contains('wordlist_data.xml'));
    expect(names, contains('audio/0001body.wav'));
    expect(names, contains('consent_log.json'));
    expect(names, contains('README.txt'));
    expect(names.any((n) => n.startsWith('export_temp')), false);

    // Unreferenced recordings and unsaved temp takes stay out.
    expect(names.any((n) => n.contains('9999stale')), false);
    expect(names.any((n) => n.contains('tmp')), false);

    // The XML is UTF-16 LE with BOM and carries the collected data.
    final xmlBytes = archive.files
        .firstWhere((f) => f.name == 'wordlist_data.xml')
        .content as List<int>;
    expect(xmlBytes[0], 0xFF);
    expect(xmlBytes[1], 0xFE);
    final xml = XmlImportService.decodeXmlBytes(
        Uint8List.fromList(xmlBytes));
    final reparsed = XmlImportService.parseWordlistXml(xml);
    expect(reparsed.entries.single.localTranscription, 'bɔdi');
    expect(reparsed.entries.single.soundFile, '0001body.wav');

    // Consent log holds the record.
    final consentBytes = archive.files
        .firstWhere((f) => f.name == 'consent_log.json')
        .content as List<int>;
    final consent = jsonDecode(utf8.decode(consentBytes));
    expect(consent['consent_records'], hasLength(1));
    expect(consent['consent_records'][0]['consent_response'], 'assent');

    // The temp directory is cleaned up afterwards.
    expect(await Directory('${tempDir.path}/export_temp').exists(), false);
  });

  test('consent log is included even when empty', () async {
    await DatabaseService.instance
        .replaceAllEntries([WordlistEntry(reference: '0001', gloss: 'body')]);

    final service = ExportService(baseDirectoryOverride: tempDir);
    final zipPath = await service.exportData();

    final archive =
        ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    final consentFile =
        archive.files.firstWhere((f) => f.name == 'consent_log.json');
    final consent =
        jsonDecode(utf8.decode(consentFile.content as List<int>));
    expect(consent['consent_records'], isEmpty);
  });

  test('old export archives are replaced, not accumulated', () async {
    await DatabaseService.instance
        .replaceAllEntries([WordlistEntry(reference: '0001', gloss: 'body')]);

    final service = ExportService(baseDirectoryOverride: tempDir);
    final first = await service.exportData();
    // Ensure a different timestamp for the second archive name.
    await Future.delayed(const Duration(seconds: 1));
    final second = await service.exportData();

    expect(await File(second).exists(), true);
    if (first != second) {
      expect(await File(first).exists(), false);
    }
  });
}
