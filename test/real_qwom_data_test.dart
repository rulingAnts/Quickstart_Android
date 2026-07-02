import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordlist_elicitation/services/xml_service.dart';

/// Integration check against the real QWOM data file
/// (https://github.com/rulingAnts/QWOM_Data), which cannot be committed to
/// this repository for licensing reasons (CC BY-NC-SA vs AGPL).
///
/// Set the QWOM_XML environment variable or place the file at
/// ../QWOM_Data/QWOM2025-08.xml relative to this repo; otherwise the test
/// is skipped (e.g. in CI).
void main() {
  final candidates = [
    Platform.environment['QWOM_XML'],
    '../QWOM_Data/QWOM2025-08.xml',
  ].whereType<String>();

  File? qwomFile;
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      qwomFile = file;
      break;
    }
  }

  test(
    'parses the full real QWOM wordlist',
    () {
      final bytes = qwomFile!.readAsBytesSync();
      final xml = XmlImportService.decodeXmlBytes(bytes);
      final parsed = XmlImportService.parseWordlistXml(xml);

      expect(parsed.entries.length, greaterThan(900));
      expect(parsed.skippedInvalid, 0);
      expect(parsed.skippedDuplicates, 0);

      // References are unique, normalized, and sortable.
      final references = parsed.entries.map((e) => e.reference).toList();
      expect(references.toSet().length, references.length);
      expect(references.first, '0001');

      // Spot-check known content from the file.
      final body = parsed.entries.first;
      expect(body.gloss, 'body');
      expect(body.soundFile, '0001body.wav');
      expect(body.glossIndonesian, isNotNull);

      // Round-trip: export and re-parse without losing entries or fields.
      final exported = XmlImportService().exportDekerekeXml(parsed.entries);
      final reparsed = XmlImportService.parseWordlistXml(exported);
      expect(reparsed.entries.length, parsed.entries.length);
      expect(
        reparsed.entries.first.xmlFields.map((f) => f.key).toList(),
        parsed.entries.first.xmlFields.map((f) => f.key).toList(),
      );
    },
    skip: qwomFile == null
        ? 'Real QWOM data file not available (set QWOM_XML or clone '
            'QWOM_Data next to this repo)'
        : false,
  );
}
