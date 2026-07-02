import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';
import '../models/wordlist_entry.dart';
import 'database_service.dart';

/// Result of a wordlist import.
class ImportResult {
  final int imported;
  final int skippedInvalid; // records missing Reference or Gloss
  final int skippedDuplicates; // records whose Reference was already seen

  const ImportResult({
    required this.imported,
    this.skippedInvalid = 0,
    this.skippedDuplicates = 0,
  });
}

/// Imports and exports wordlists in the Dekereke XML format.
///
/// The real format (e.g. the QWOM data file) is UTF-16 little-endian with a
/// `<phon_data>` root containing `<data_form>` records:
///
/// ```xml
/// <phon_data>
///   <data_form>
///     <Reference>0001</Reference>
///     <Gloss>body</Gloss>
///     <SoundFile>0001body.wav</SoundFile>
///     <Phonetic />
///     ...
///   </data_form>
/// </phon_data>
/// ```
///
/// A simplified `<Wordlist>/<Entry>` structure is also accepted for
/// hand-made test files.
class XmlImportService {
  final DatabaseService _db = DatabaseService.instance;

  /// Parse a Dekereke XML file and import it into the database.
  ///
  /// When [merge] is true, existing collected data (transcriptions, audio,
  /// completion state) is preserved and only the wordlist fields are
  /// updated; otherwise all existing entries are replaced.
  Future<ImportResult> importDekerekeXml(String filePath,
      {bool merge = false}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final xmlString = decodeXmlBytes(await file.readAsBytes());
    final parsed = parseWordlistXml(xmlString);

    if (parsed.entries.isEmpty) {
      throw const FormatException(
        'No wordlist entries found. Expected Dekereke XML with '
        '<data_form> records (or <Entry> records) containing '
        '<Reference> and <Gloss>.',
      );
    }

    final imported = merge
        ? await _db.mergeEntries(parsed.entries)
        : await _db.replaceAllEntries(parsed.entries);

    return ImportResult(
      imported: imported,
      skippedInvalid: parsed.skippedInvalid,
      skippedDuplicates: parsed.skippedDuplicates,
    );
  }

  /// Decodes XML file bytes, honoring a UTF-16 LE/BE or UTF-8 BOM.
  /// Dekereke files are UTF-16 LE; files without a BOM are sniffed for
  /// UTF-16 byte patterns and otherwise decoded as UTF-8.
  static String decodeXmlBytes(Uint8List bytes) {
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return _decodeUtf16(bytes.sublist(2), littleEndian: true);
      }
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return _decodeUtf16(bytes.sublist(2), littleEndian: false);
      }
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }
    // No BOM: an XML file starting '<' as UTF-16 has a zero byte next to it.
    if (bytes.length >= 2) {
      if (bytes[0] == 0x3C && bytes[1] == 0x00) {
        return _decodeUtf16(bytes, littleEndian: true);
      }
      if (bytes[0] == 0x00 && bytes[1] == 0x3C) {
        return _decodeUtf16(bytes, littleEndian: false);
      }
    }
    return utf8.decode(bytes);
  }

  static String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
    final byteData = Uint8List.fromList(bytes);
    final data = ByteData.sublistView(byteData);
    final codeUnits = List<int>.generate(
      byteData.length ~/ 2,
      (i) => data.getUint16(i * 2, littleEndian ? Endian.little : Endian.big),
    );
    return String.fromCharCodes(codeUnits);
  }

  /// Encodes [text] as UTF-16 little-endian with a BOM, the encoding
  /// Dekereke reads and writes.
  static Uint8List encodeUtf16Le(String text) {
    final codeUnits = text.codeUnits;
    final bytes = Uint8List(2 + codeUnits.length * 2);
    bytes[0] = 0xFF;
    bytes[1] = 0xFE;
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < codeUnits.length; i++) {
      data.setUint16(2 + i * 2, codeUnits[i], Endian.little);
    }
    return bytes;
  }

  /// Parses wordlist XML into entries without touching the database.
  static ParsedWordlist parseWordlistXml(String xmlString) {
    final document = XmlDocument.parse(xmlString);

    // Real Dekereke format first, then the simplified test format.
    var records = document.findAllElements('data_form').toList();
    if (records.isEmpty) {
      records = document.findAllElements('Entry').toList();
    }

    final entries = <WordlistEntry>[];
    final seenReferences = <String>{};
    var skippedInvalid = 0;
    var skippedDuplicates = 0;

    for (final record in records) {
      final reference =
          _normalizeReference(_elementText(record, 'Reference') ?? '');
      final gloss = (_elementText(record, 'Gloss') ?? '').trim();

      if (reference.isEmpty || gloss.isEmpty) {
        skippedInvalid++;
        continue;
      }
      if (!seenReferences.add(reference)) {
        skippedDuplicates++;
        continue;
      }

      // Preserve every child element (name + text) in order for round-trip
      // export, with the normalized reference.
      final fields = <MapEntry<String, String>>[];
      for (final child in record.childElements) {
        final value = child.name.local == 'Reference'
            ? reference
            : child.innerText.trim();
        fields.add(MapEntry(child.name.local, value));
      }

      final imageFile = _elementText(record, 'Image_File');
      final picture = _elementText(record, 'Picture');
      final pictureFilename = (imageFile != null && imageFile.isNotEmpty)
          ? imageFile
          : (picture != null && picture.isNotEmpty ? picture : null);

      // Accept previously collected data when re-importing an export.
      final transcription = _firstNonEmpty(
          [_elementText(record, 'Phonetic'), _elementText(record, 'LocalWord')]);

      entries.add(WordlistEntry(
        reference: reference,
        gloss: gloss,
        glossIndonesian: _emptyToNull(_elementText(record, 'GlossIndonesian')),
        glossTokPisin: _emptyToNull(_elementText(record, 'GlossTokPisin')),
        category: _emptyToNull(_elementText(record, 'Category')),
        semanticDomain: _emptyToNull(_elementText(record, 'SemanticDomain')),
        soundFile: _emptyToNull(_elementText(record, 'SoundFile')),
        pictureFilename: pictureFilename,
        localTranscription: transcription,
        isCompleted: transcription != null,
        xmlFieldsJson: WordlistEntry.encodeXmlFields(fields),
      ));
    }

    return ParsedWordlist(
      entries: entries,
      skippedInvalid: skippedInvalid,
      skippedDuplicates: skippedDuplicates,
    );
  }

  /// Builds Dekereke XML for [entries], preserving each entry's original
  /// fields and updating `<Phonetic>` with the collected transcription and
  /// `<SoundFile>` with the recorded audio filename.
  ///
  /// Returns the XML as a string; use [encodeUtf16Le] when writing it to a
  /// file so Dekereke can read it.
  String exportDekerekeXml(List<WordlistEntry> entries) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="utf-16" standalone="yes"');

    builder.element('phon_data', nest: () {
      for (final entry in entries) {
        builder.element('data_form', nest: () {
          final fields = entry.xmlFields;
          if (fields.isNotEmpty) {
            var hasPhonetic = false;
            var hasSoundFile = false;
            for (final field in fields) {
              var value = field.value;
              if (field.key == 'Phonetic') {
                hasPhonetic = true;
                value = entry.localTranscription ?? value;
              } else if (field.key == 'SoundFile') {
                hasSoundFile = true;
                value = entry.audioFilename ?? value;
              }
              builder.element(field.key, nest: value);
            }
            if (!hasPhonetic &&
                (entry.localTranscription?.isNotEmpty ?? false)) {
              builder.element('Phonetic', nest: entry.localTranscription);
            }
            if (!hasSoundFile && (entry.audioFilename?.isNotEmpty ?? false)) {
              builder.element('SoundFile', nest: entry.audioFilename);
            }
          } else {
            // Entry without preserved fields (e.g. simplified import):
            // emit the core Dekereke fields.
            builder.element('Reference', nest: entry.reference);
            builder.element('Gloss', nest: entry.gloss);
            builder.element('Phonetic', nest: entry.localTranscription ?? '');
            builder.element('SoundFile',
                nest: entry.audioFilename ?? entry.soundFile ?? '');
            builder.element('Image_File', nest: entry.pictureFilename ?? '');
          }
        });
      }
    });

    final xml =
        builder.buildDocument().toXmlString(pretty: true, indent: '\t');
    // Dekereke writes CRLF line endings.
    return xml.replaceAll('\n', '\r\n');
  }

  static String? _elementText(XmlElement parent, String tagName) {
    for (final child in parent.childElements) {
      if (child.name.local == tagName) return child.innerText.trim();
    }
    return null;
  }

  static String? _emptyToNull(String? value) =>
      (value == null || value.isEmpty) ? null : value;

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// Pads numeric references to 4 digits ("1" -> "0001") so ordering and
  /// audio filenames are consistent; non-numeric references pass through.
  static String _normalizeReference(String reference) {
    final trimmed = reference.trim();
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      return trimmed.padLeft(4, '0');
    }
    return trimmed;
  }
}

/// Entries parsed from a wordlist XML document, with skip counts.
class ParsedWordlist {
  final List<WordlistEntry> entries;
  final int skippedInvalid;
  final int skippedDuplicates;

  const ParsedWordlist({
    required this.entries,
    required this.skippedInvalid,
    required this.skippedDuplicates,
  });
}
