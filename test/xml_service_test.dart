import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordlist_elicitation/models/wordlist_entry.dart';
import 'package:wordlist_elicitation/services/xml_service.dart';

/// A minimal but faithful excerpt of the real QWOM Dekereke file
/// (phon_data/data_form, full field set, empty self-closed fields).
const String dekerekeXml = '''
<?xml version="1.0" encoding="utf-8" standalone="yes" ?>
<phon_data>
	<data_form>
		<Reference>0001</Reference>
		<CAWL>1</CAWL>
		<InPictureDictionary>X</InPictureDictionary>
		<Picture />
		<Category>N</Category>
		<Gloss>body</Gloss>
		<SoundFile>0001body.wav</SoundFile>
		<Image_File>0001body.png</Image_File>
		<Instructions />
		<GlossTokPisin>bodi</GlossTokPisin>
		<GlossIndonesian>tubuh, badan</GlossIndonesian>
		<Phonetic />
		<SemanticDomain>Body parts</SemanticDomain>
		<Notes />
		<InstructionsIndonesian />
		<InstructionsTokPisin />
	</data_form>
	<data_form>
		<Reference>0002</Reference>
		<CAWL>2</CAWL>
		<InPictureDictionary />
		<Picture />
		<Category>N</Category>
		<Gloss>skin (human)</Gloss>
		<SoundFile>0002skin.wav</SoundFile>
		<Image_File />
		<Instructions />
		<GlossTokPisin>skin</GlossTokPisin>
		<GlossIndonesian>kulit</GlossIndonesian>
		<Phonetic />
		<SemanticDomain>Body parts</SemanticDomain>
		<Notes />
		<InstructionsIndonesian />
		<InstructionsTokPisin />
	</data_form>
</phon_data>
''';

const String legacyXml = '''
<?xml version="1.0" encoding="utf-8"?>
<Wordlist>
  <Entry>
    <Reference>1</Reference>
    <Gloss>body</Gloss>
    <Picture>body.jpg</Picture>
  </Entry>
  <Entry>
    <Reference>2</Reference>
    <Gloss>head</Gloss>
  </Entry>
</Wordlist>
''';

void main() {
  group('parseWordlistXml (real Dekereke format)', () {
    test('parses data_form records with all fields', () {
      final parsed = XmlImportService.parseWordlistXml(dekerekeXml);

      expect(parsed.entries.length, 2);
      expect(parsed.skippedInvalid, 0);
      expect(parsed.skippedDuplicates, 0);

      final body = parsed.entries[0];
      expect(body.reference, '0001');
      expect(body.gloss, 'body');
      expect(body.glossIndonesian, 'tubuh, badan');
      expect(body.glossTokPisin, 'bodi');
      expect(body.category, 'N');
      expect(body.semanticDomain, 'Body parts');
      expect(body.soundFile, '0001body.wav');
      expect(body.pictureFilename, '0001body.png');
      expect(body.localTranscription, isNull);
      expect(body.isCompleted, false);

      // Entries carry no explicit id, so SQLite can auto-assign row ids.
      expect(body.id, isNull);

      final skin = parsed.entries[1];
      expect(skin.gloss, 'skin (human)');
      expect(skin.soundFile, '0002skin.wav');
      expect(skin.pictureFilename, isNull); // Image_File empty
    });

    test('preserves all original XML fields in order for round-trip', () {
      final parsed = XmlImportService.parseWordlistXml(dekerekeXml);
      final fields = parsed.entries[0].xmlFields;

      expect(fields.map((f) => f.key).toList(), [
        'Reference',
        'CAWL',
        'InPictureDictionary',
        'Picture',
        'Category',
        'Gloss',
        'SoundFile',
        'Image_File',
        'Instructions',
        'GlossTokPisin',
        'GlossIndonesian',
        'Phonetic',
        'SemanticDomain',
        'Notes',
        'InstructionsIndonesian',
        'InstructionsTokPisin',
      ]);
      expect(fields[1].value, '1'); // CAWL
      expect(fields[3].value, ''); // empty Picture preserved
    });

    test('skips duplicate references, keeping the first occurrence', () {
      const xml = '''
<phon_data>
  <data_form><Reference>0001</Reference><Gloss>body</Gloss></data_form>
  <data_form><Reference>0001</Reference><Gloss>corpse</Gloss></data_form>
  <data_form><Reference>0002</Reference><Gloss>head</Gloss></data_form>
</phon_data>
''';
      final parsed = XmlImportService.parseWordlistXml(xml);
      expect(parsed.entries.length, 2);
      expect(parsed.skippedDuplicates, 1);
      expect(parsed.entries[0].gloss, 'body');
    });

    test('skips records missing Reference or Gloss', () {
      const xml = '''
<phon_data>
  <data_form><Reference>0001</Reference><Gloss>body</Gloss></data_form>
  <data_form><Reference></Reference><Gloss>head</Gloss></data_form>
  <data_form><Reference>0003</Reference><Gloss></Gloss></data_form>
  <data_form><Gloss>eye</Gloss></data_form>
</phon_data>
''';
      final parsed = XmlImportService.parseWordlistXml(xml);
      expect(parsed.entries.length, 1);
      expect(parsed.skippedInvalid, 3);
    });

    test('re-importing an export restores transcriptions', () {
      const xml = '''
<phon_data>
  <data_form>
    <Reference>0001</Reference>
    <Gloss>body</Gloss>
    <Phonetic>bɔdi</Phonetic>
    <SoundFile>0001body.wav</SoundFile>
  </data_form>
</phon_data>
''';
      final parsed = XmlImportService.parseWordlistXml(xml);
      expect(parsed.entries.single.localTranscription, 'bɔdi');
      expect(parsed.entries.single.isCompleted, true);
    });
  });

  group('parseWordlistXml (legacy sample format)', () {
    test('parses Entry records and pads references to 4 digits', () {
      final parsed = XmlImportService.parseWordlistXml(legacyXml);
      expect(parsed.entries.length, 2);
      expect(parsed.entries[0].reference, '0001');
      expect(parsed.entries[0].pictureFilename, 'body.jpg');
      expect(parsed.entries[1].reference, '0002');
    });
  });

  group('UTF-16 handling', () {
    test('decodes UTF-16 LE bytes with BOM (real Dekereke encoding)', () {
      final bytes = XmlImportService.encodeUtf16Le(dekerekeXml);
      final decoded = XmlImportService.decodeXmlBytes(bytes);
      expect(decoded, dekerekeXml);

      final parsed = XmlImportService.parseWordlistXml(decoded);
      expect(parsed.entries.length, 2);
    });

    test('decodes UTF-16 BE bytes with BOM', () {
      final content = '<a>bɔdi</a>'; // includes IPA open o
      final codeUnits = content.codeUnits;
      final bytes = <int>[0xFE, 0xFF];
      for (final unit in codeUnits) {
        bytes.add((unit >> 8) & 0xFF);
        bytes.add(unit & 0xFF);
      }
      final decoded =
          XmlImportService.decodeXmlBytes(Uint8List.fromList(bytes));
      expect(decoded, content);
    });

    test('decodes BOM-less UTF-16 LE by sniffing the leading "<"', () {
      final content = '<a>x</a>';
      final bytes = <int>[];
      for (final unit in content.codeUnits) {
        bytes.add(unit & 0xFF);
        bytes.add((unit >> 8) & 0xFF);
      }
      final decoded =
          XmlImportService.decodeXmlBytes(Uint8List.fromList(bytes));
      expect(decoded, content);
    });

    test('decodes plain UTF-8 with and without BOM', () {
      final plain = XmlImportService.decodeXmlBytes(
          Uint8List.fromList(utf8.encode('<a>ɸaju</a>')));
      expect(plain, '<a>ɸaju</a>');

      final withBom = XmlImportService.decodeXmlBytes(
          Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('<a>x</a>')]));
      expect(withBom, '<a>x</a>');
    });

    test('encodeUtf16Le starts with an LE BOM', () {
      final bytes = XmlImportService.encodeUtf16Le('x');
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xFE);
      expect(bytes[2], 'x'.codeUnitAt(0));
      expect(bytes[3], 0);
    });
  });

  group('exportDekerekeXml', () {
    test('round-trips all fields and fills Phonetic and SoundFile', () {
      final parsed = XmlImportService.parseWordlistXml(dekerekeXml);
      final collected = parsed.entries[0].copyWith(
        localTranscription: 'bɔdi',
        audioFilename: '0001body.wav',
        isCompleted: true,
      );

      final service = XmlImportService();
      final exported =
          service.exportDekerekeXml([collected, parsed.entries[1]]);

      // Structure and metadata match Dekereke.
      expect(exported, contains('<phon_data>'));
      expect(exported, contains('<data_form>'));
      expect(exported, contains('encoding="utf-16"'));
      expect(exported, contains('\r\n'));

      // Re-parse the export: everything survives.
      final reparsed = XmlImportService.parseWordlistXml(exported);
      expect(reparsed.entries.length, 2);

      final body = reparsed.entries[0];
      expect(body.localTranscription, 'bɔdi');
      expect(body.soundFile, '0001body.wav');
      expect(body.glossIndonesian, 'tubuh, badan');
      expect(body.semanticDomain, 'Body parts');

      // Original field order is preserved.
      expect(
        body.xmlFields.map((f) => f.key).toList(),
        parsed.entries[0].xmlFields.map((f) => f.key).toList(),
      );

      // The untouched entry keeps its empty Phonetic.
      final skin = reparsed.entries[1];
      expect(skin.localTranscription, isNull);
      expect(skin.glossIndonesian, 'kulit');
    });

    test('exports entries without preserved fields using core field set', () {
      final entry = WordlistEntry(
        reference: '0001',
        gloss: 'body',
        localTranscription: 'bɔdi',
        audioFilename: '0001body.wav',
        isCompleted: true,
      );

      final exported = XmlImportService().exportDekerekeXml([entry]);
      final reparsed = XmlImportService.parseWordlistXml(exported);

      expect(reparsed.entries.single.reference, '0001');
      expect(reparsed.entries.single.localTranscription, 'bɔdi');
      expect(reparsed.entries.single.soundFile, '0001body.wav');
    });

    test('export bytes are valid UTF-16 for IPA transcriptions', () {
      final entry = WordlistEntry(
        reference: '0001',
        gloss: 'water',
        localTranscription: 'ɸaʔɛ̃ũ', // IPA with combining marks
        isCompleted: true,
      );
      final service = XmlImportService();
      final bytes =
          XmlImportService.encodeUtf16Le(service.exportDekerekeXml([entry]));
      final decoded = XmlImportService.decodeXmlBytes(bytes);
      final reparsed = XmlImportService.parseWordlistXml(decoded);
      expect(reparsed.entries.single.localTranscription, 'ɸaʔɛ̃ũ');
    });
  });
}
