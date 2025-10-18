import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'xml_service.dart';
import 'database_service.dart';

class ExportService {
  final XmlImportService _xmlService = XmlImportService();
  final DatabaseService _db = DatabaseService.instance;

  /// Export all collected data as a ZIP archive
  Future<String> exportData() async {
    final directory = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${directory.path}/export_temp');
    
    // Clean up any previous export
    if (await exportDir.exists()) {
      await exportDir.delete(recursive: true);
    }
    await exportDir.create(recursive: true);

    // 1. Export Dekereke XML
    final entries = await _db.getAllWordlistEntries();
    final xmlContent = await _xmlService.exportDekerekeXml(entries);
    final xmlFile = File('${exportDir.path}/wordlist_data.xml');
  // Write XML as UTF-8 (standard, widely compatible). Ensure XML header matches.
  await xmlFile.writeAsString(xmlContent, encoding: utf8);

    // 2. Copy audio files
    final audioExportDir = Directory('${exportDir.path}/audio');
    await audioExportDir.create();
    final audioSourceDir = Directory('${directory.path}/audio');
    
    if (await audioSourceDir.exists()) {
      await for (final file in audioSourceDir.list()) {
        if (file is File && file.path.endsWith('.wav')) {
          final filename = file.path.split('/').last;
          await file.copy('${audioExportDir.path}/$filename');
        }
      }
    }

    // 3. Export consent log
    final consentRecords = await _db.getAllConsentRecords();
    if (consentRecords.isNotEmpty) {
      final consentLog = {
        'consent_records': consentRecords.map((r) => r.toJson()).toList(),
      };
      final consentFile = File('${exportDir.path}/consent_log.json');
      await consentFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(consentLog),
      );

      // Copy verbal consent audio if exists
      for (final record in consentRecords) {
        if (record.verbalConsentFilename != null) {
          final consentAudioFile = File(
            '${directory.path}/audio/${record.verbalConsentFilename}',
          );
          if (await consentAudioFile.exists()) {
            await consentAudioFile.copy(
              '${exportDir.path}/${record.verbalConsentFilename}',
            );
          }
        }
      }
    }

    // 4. Create README for the export
    final readmeContent = '''
Wordlist Elicitation Data Export
=================================

This archive contains:
1. wordlist_data.xml - Dekereke XML format with collected transcriptions
2. audio/ - Directory with all WAV audio recordings (16-bit)
3. consent_log.json - Consent records from data collection
${consentRecords.any((r) => r.verbalConsentFilename != null) ? '4. Verbal consent audio files\n' : ''}
Export Date: ${DateTime.now().toIso8601String()}
Total Entries: ${entries.length}
Completed Entries: ${entries.where((e) => e.isCompleted).length}
''';
    final readmeFile = File('${exportDir.path}/README.txt');
    await readmeFile.writeAsString(readmeContent);

    // 5. Create ZIP archive
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final zipFileName = 'wordlist_export_$timestamp.zip';
    final zipFilePath = '${directory.path}/$zipFileName';
    
    final encoder = ZipFileEncoder();
    encoder.create(zipFilePath);
    encoder.addDirectory(exportDir);
    encoder.close();

    // Clean up temporary directory
    await exportDir.delete(recursive: true);

    return zipFilePath;
  }
}
