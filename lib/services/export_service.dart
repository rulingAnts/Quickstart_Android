import 'dart:io';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'xml_service.dart';
import 'database_service.dart';

class ExportService {
  final XmlImportService _xmlService = XmlImportService();
  final DatabaseService _db = DatabaseService.instance;

  /// Directory that holds the app's data (audio/, exports). Defaults to the
  /// application documents directory; injectable for tests.
  final Directory? baseDirectoryOverride;

  ExportService({this.baseDirectoryOverride});

  Future<Directory> get _baseDirectory async =>
      baseDirectoryOverride ?? await getApplicationDocumentsDirectory();

  /// Export all collected data as a ZIP archive and return its path.
  ///
  /// Layout inside the archive (no wrapping folder):
  ///   wordlist_data.xml   Dekereke XML, UTF-16 LE with BOM
  ///   audio/*.wav         all elicitation + consent recordings
  ///   consent_log.json    consent records (always present)
  ///   README.txt
  Future<String> exportData() async {
    final directory = await _baseDirectory;
    final exportDir = Directory('${directory.path}/export_temp');

    // Clean up any previous export temp data. Old export archives are only
    // removed after the new one is fully built, so a failed export never
    // destroys the last good backup.
    if (await exportDir.exists()) {
      await exportDir.delete(recursive: true);
    }
    await exportDir.create(recursive: true);

    final entries = await _db.getAllWordlistEntries();
    final consentRecords = await _db.getAllConsentRecords();

    // 1. Dekereke XML (UTF-16 LE with BOM, as Dekereke expects).
    final xmlContent = _xmlService.exportDekerekeXml(entries);
    final xmlFile = File('${exportDir.path}/wordlist_data.xml');
    await xmlFile.writeAsBytes(XmlImportService.encodeUtf16Le(xmlContent));

    // 2. Audio recordings — only files the current data actually
    // references, so recordings from a previously replaced wordlist can't
    // contaminate the archive.
    final referenced = <String>{
      for (final e in entries)
        if (e.audioFilename != null && e.audioFilename!.isNotEmpty)
          e.audioFilename!,
      for (final r in consentRecords)
        if (r.verbalConsentFilename != null) r.verbalConsentFilename!,
    };
    final audioExportDir = Directory('${exportDir.path}/audio');
    await audioExportDir.create();
    final audioSourceDir = Directory('${directory.path}/audio');
    if (await audioSourceDir.exists()) {
      await for (final file in audioSourceDir.list()) {
        if (file is File) {
          final filename = file.uri.pathSegments.last;
          if (referenced.contains(filename)) {
            await file.copy('${audioExportDir.path}/$filename');
          }
        }
      }
    }

    // 3. Consent log — always included, per the ethics requirements.
    final consentLog = {
      'consent_records': consentRecords.map((r) => r.toJson()).toList(),
    };
    final consentFile = File('${exportDir.path}/consent_log.json');
    await consentFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(consentLog),
    );

    // 4. README describing the archive.
    final completedCount = entries.where((e) => e.isCompleted).length;
    final readmeContent = '''
Wordlist Elicitation Data Export
=================================

This archive contains:
1. wordlist_data.xml - Dekereke XML (UTF-16) with collected transcriptions
2. audio/ - WAV audio recordings (16-bit), named <Reference><gloss>.wav
3. consent_log.json - Consent records from data collection

Export Date: ${DateTime.now().toIso8601String()}
Total Entries: ${entries.length}
Completed Entries: $completedCount
Consent Records: ${consentRecords.length}
''';
    final readmeFile = File('${exportDir.path}/README.txt');
    await readmeFile.writeAsString(readmeContent);

    // 5. Zip it up (contents at the archive root, not nested in a folder).
    // Build under a temporary name, then swap: earlier exports survive any
    // failure up to this point.
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final zipFilePath = '${directory.path}/wordlist_export_$timestamp.zip';
    final buildingPath = '$zipFilePath.building';

    final encoder = ZipFileEncoder();
    encoder.create(buildingPath);
    await encoder.addDirectory(exportDir, includeDirName: false);
    encoder.close();

    await _deleteOldExports(directory, except: buildingPath);
    await File(buildingPath).rename(zipFilePath);

    await exportDir.delete(recursive: true);

    return zipFilePath;
  }

  /// Deletes finished exports and stale `.building` leftovers from crashed
  /// runs, sparing the archive currently being built.
  Future<void> _deleteOldExports(Directory directory,
      {String? except}) async {
    await for (final file in directory.list()) {
      if (file is File && file.path != except) {
        final name = file.uri.pathSegments.last;
        if (name.startsWith('wordlist_export_') &&
            (name.endsWith('.zip') || name.endsWith('.zip.building'))) {
          await file.delete();
        }
      }
    }
  }
}
