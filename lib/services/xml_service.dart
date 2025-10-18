import 'dart:io';
import 'package:xml/xml.dart';
import '../utils/logger.dart';
import '../models/wordlist_entry.dart';
import 'database_service.dart';

class XmlImportService {
  final DatabaseService _db = DatabaseService.instance;

  /// Parse Dekereke XML format and import to database
  Future<int> importDekerekeXml(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final xmlString = await file.readAsString();
    final document = XmlDocument.parse(xmlString);

    // Clear existing entries before import
    await _db.deleteAllWordlistEntries();

    int importCount = 0;

    // Parse XML structure - adapt based on actual Dekereke format
    // This is a basic implementation that should be adjusted based on actual XML structure
    final entries = document.findAllElements('Entry');

    for (final entryElement in entries) {
      try {
        final reference = _getElementText(entryElement, 'Reference') ?? '';
        final gloss = _getElementText(entryElement, 'Gloss') ?? '';
        final pictureFilename = _getElementText(entryElement, 'Picture');

        if (reference.isEmpty || gloss.isEmpty) {
          continue; // Skip invalid entries
        }

        final entry = WordlistEntry(
          id: 0, // Auto-increment
          reference: reference.padLeft(4, '0'), // Ensure 4-digit format
          gloss: gloss,
          pictureFilename: pictureFilename,
        );

        await _db.insertWordlistEntry(entry);
        importCount++;
      } catch (e, st) {
        Log.w('Error parsing entry', e, st);
        // Continue with next entry
      }
    }

    return importCount;
  }

  String? _getElementText(XmlElement parent, String tagName) {
    final element = parent.findElements(tagName).firstOrNull;
    return element?.innerText.trim();
  }

  /// Export to Dekereke XML format
  Future<String> exportDekerekeXml(List<WordlistEntry> entries) async {
  final builder = XmlBuilder();
  // Match the file write encoding (UTF-8)
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    
    builder.element('Wordlist', nest: () {
      for (final entry in entries) {
        builder.element('Entry', nest: () {
          builder.element('Reference', nest: entry.reference);
          builder.element('Gloss', nest: entry.gloss);
          
          if (entry.localTranscription != null && entry.localTranscription!.isNotEmpty) {
            builder.element('LocalWord', nest: entry.localTranscription);
          }
          
          if (entry.audioFilename != null && entry.audioFilename!.isNotEmpty) {
            builder.element('SoundFile', nest: entry.audioFilename);
          }
          
          if (entry.pictureFilename != null && entry.pictureFilename!.isNotEmpty) {
            builder.element('Picture', nest: entry.pictureFilename);
          }
        });
      }
    });

    return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  }
}
