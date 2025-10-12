import 'dart:io';
import 'package:xml/xml.dart';
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

    // Parse XML structure using actual Dekereke format
    // Root element is <phon_data> and row elements are <data_form>
    final entries = document.findAllElements('data_form');

    for (final entryElement in entries) {
      try {
        final reference = _getElementText(entryElement, 'Reference') ?? '';
        final gloss = _getElementText(entryElement, 'Gloss') ?? '';
        // Try Image_File first (actual QWOM format), fallback to Picture for compatibility
        final pictureFilename = _getElementText(entryElement, 'Image_File') ?? 
                               _getElementText(entryElement, 'Picture');

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
      } catch (e) {
        print('Error parsing entry: $e');
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
    builder.processing('xml', 'version="1.0" encoding="UTF-16"');
    
    builder.element('phon_data', nest: () {
      for (final entry in entries) {
        builder.element('data_form', nest: () {
          builder.element('Reference', nest: entry.reference);
          builder.element('Gloss', nest: entry.gloss);
          
          if (entry.localTranscription != null && entry.localTranscription!.isNotEmpty) {
            builder.element('LocalWord', nest: entry.localTranscription);
          }
          
          if (entry.audioFilename != null && entry.audioFilename!.isNotEmpty) {
            builder.element('SoundFile', nest: entry.audioFilename);
          }
          
          if (entry.pictureFilename != null && entry.pictureFilename!.isNotEmpty) {
            builder.element('Image_File', nest: entry.pictureFilename);
          }
        });
      }
    });

    // Generate XML with LF endings, then convert to CRLF for Dekereke format
    final xmlString = builder.buildDocument().toXmlString(pretty: true, indent: '  ');
    return xmlString.replaceAll('\n', '\r\n');
  }
}
