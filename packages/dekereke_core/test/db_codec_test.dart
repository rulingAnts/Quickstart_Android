import 'dart:io';
import 'dart:typed_data';

import 'package:dekereke_core/dekereke_core.dart';
import 'package:test/test.dart';

/// Format-faithful synthetic fixture (see test_data/dekereke_fixtures/README).
final _fixturePath = 'test_data/dekereke_fixtures/synthetic_db.xml';

Uint8List _fixtureBytes() {
  // Tests run with CWD = package root; the fixtures live at the repo root.
  final path = '../../$_fixturePath';
  return File(path).readAsBytesSync();
}

void main() {
  group('parsing the synthetic fixture', () {
    late DekerekeDatabase db;

    setUpAll(() => db = parseDekerekeFile(_fixtureBytes()));

    test('finds all five records, in file order', () {
      final records = db.records;
      expect(records, hasLength(5));
      expect(records.map((r) => r.gloss), [
        'body',
        'water (fresh)',
        'water (in river)',
        'ear',
        'go / walk',
      ]);
    });

    test('duplicate References are preserved, not collapsed', () {
      final refs = db.records.map((r) => r.reference).toList();
      expect(refs, ['0001', '0002', '0002', '', '0005']);
    });

    test('missing Reference is an empty *present* field, not absent', () {
      final ear = db.records[3];
      expect(ear.reference, '');
      expect(ear.hasField('Reference'), isTrue);
    });

    test('presence-only boolean tags are present-and-empty value fields', () {
      final body = db.records[0];
      expect(body.hasField('loan'), isTrue);
      expect(body.valueOf('loan'), '');
      // Absent on other records: presence is the datum.
      expect(db.records[1].hasField('loan'), isFalse);
      expect(db.records[4].hasField('Confirmed'), isTrue);
    });

    test('meaningful double space in a value survives untrimmed', () {
      expect(db.records[1].valueOf('Notes'), 'double  space preserved');
    });

    test('filenames with spaces and parentheses survive', () {
      expect(db.records[1].soundFileCell, '0002_water.fresh (00392).wav');
    });

    test('nested qvp fragment is preserved as a fragment field', () {
      final water = db.records[1];
      final fragment = water.fields
          .whereType<DekerekeFragmentField>()
          .singleWhere((f) => f.name == 'qvp_acoustic_data_');
      expect(fragment.xml, contains('<vowel_token>'));
      expect(fragment.xml, contains('<f2>1387.2</f2>'));
      // Canonical fragments use LF newlines and preserve structure verbatim.
      expect(fragment.xml, isNot(contains('\r')));
      expect(
          fragment.xml,
          '<qvp_acoustic_data_>\n'
          '\t\t\t<vowel_token>\n'
          '\t\t\t\t<vowel>a</vowel>\n'
          '\t\t\t\t<f1>702.5</f1>\n'
          '\t\t\t\t<f2>1387.2</f2>\n'
          '\t\t\t</vowel_token>\n'
          '\t\t</qvp_acoustic_data_>');
    });

    test('field order within a record is preserved', () {
      expect(db.records[0].fields.map((f) => f.name).toList(), [
        'Reference',
        'Gloss',
        'IndonesianGloss',
        'Category',
        'Phonetic',
        'SpeakerB',
        'Notes',
        'SoundFile',
        'loan',
      ]);
    });
  });

  group('round-trip guarantees', () {
    test('working-format re-encode of the fixture is BYTE-IDENTICAL', () {
      final bytes = _fixtureBytes();
      final reEncoded = encodeWorkingFile(parseDekerekeFile(bytes));
      expect(reEncoded, bytes,
          reason: 'encodeWorkingFile(parseDekerekeFile(x)) must reproduce '
              'Dekereke-written files exactly');
    });

    test('canonical form is a fixed point', () {
      final db = parseDekerekeFile(_fixtureBytes());
      final canonical = renderCanonicalXml(db);
      final reparsed = parseDekerekeXml(canonical);
      expect(renderCanonicalXml(reparsed), canonical);
      expect(reparsed, db);
    });

    test('canonical form is UTF-8/LF with a utf-8 declaration', () {
      final canonical = renderCanonicalXml(parseDekerekeFile(_fixtureBytes()));
      expect(canonical, startsWith('$canonicalXmlDeclaration\n'));
      expect(canonical, isNot(contains('\r')));
      expect(canonical, endsWith('</phon_data>\n'));
      final encoded = encodeCanonicalFile(parseDekerekeFile(_fixtureBytes()));
      expect(encoded.sublist(0, 3), isNot([0xEF, 0xBB, 0xBF]),
          reason: 'canonical form must not carry a BOM');
    });

    test('working format differs from canonical only by declaration/newlines/encoding', () {
      final db = parseDekerekeFile(_fixtureBytes());
      final canonical = renderCanonicalXml(db);
      final working = renderWorkingXml(db);
      expect(
          working.replaceAll('\r\n', '\n'),
          canonical.replaceFirst('encoding="utf-8"', 'encoding="utf-16"'));
    });

    test('canonical bytes parse back identically (phone-app import path)', () {
      final db = parseDekerekeFile(_fixtureBytes());
      final viaCanonicalFile = parseDekerekeFile(encodeCanonicalFile(db));
      expect(viaCanonicalFile, db);
    });
  });

  group('normalizations', () {
    test('<x></x> normalizes to <x /> in record fields', () {
      final db = parseDekerekeXml(
          '<phon_data><data_form><Notes></Notes></data_form></phon_data>');
      expect(renderRecordCanonical(db.records.single), contains('<Notes />'));
    });

    test('one pass reaches the fixed point for foreign layouts', () {
      const foreign = '<?xml version="1.0"?>\n'
          '<phon_data>\n'
          '  <data_form><Reference>7</Reference>\n'
          '      <Gloss>sun</Gloss></data_form>\n'
          '</phon_data>';
      final once = renderCanonicalXml(parseDekerekeXml(foreign));
      final twice = renderCanonicalXml(parseDekerekeXml(once));
      expect(twice, once);
      expect(once, contains('\t\t<Reference>7</Reference>\n'));
    });

    test('empty database renders self-closed root', () {
      expect(renderCanonicalXml(const DekerekeDatabase([])),
          '$canonicalXmlDeclaration\n<phon_data />\n');
    });
  });

  group('escaping', () {
    test('special characters round-trip through canonical and working forms', () {
      final record = DekerekeRecord(const [
        DekerekeValueField('Reference', '0001'),
        DekerekeValueField('Notes', 'a & b < c > d "quoted" \'single\''),
        DekerekeValueField('Multiline', 'line1\nline2\rline3'),
      ]);
      final db = DekerekeDatabase([record]);

      final viaCanonical = parseDekerekeXml(renderCanonicalXml(db));
      expect(viaCanonical.records.single, record);

      final viaWorking = parseDekerekeFile(encodeWorkingFile(db));
      expect(viaWorking.records.single, record,
          reason: 'escaped CR/LF must survive the CRLF conversion');
    });

    test('text escaping matches the pinned policy', () {
      expect(escapeXmlText('a & b < c > d\r\n'),
          'a &amp; b &lt; c &gt; d&#xD;&#xA;');
    });
  });

  group('unknown content preservation', () {
    test('unknown flat and nested tags survive verbatim', () {
      const source = '<?xml version="1.0" encoding="utf-8" standalone="yes"?>\n'
          '<phon_data>\n'
          '\t<data_form>\n'
          '\t\t<Reference>0009</Reference>\n'
          '\t\t<FutureColumn>value</FutureColumn>\n'
          '\t\t<future_nested attr="x">\n'
          '\t\t\t<inner>1</inner>\n'
          '\t\t</future_nested>\n'
          '\t</data_form>\n'
          '</phon_data>\n';
      final db = parseDekerekeXml(source);
      expect(renderCanonicalXml(db), source);
    });

    test('attribute quote style and self-closing style are preserved', () {
      const source = '<?xml version="1.0" encoding="utf-8" standalone="yes"?>\n'
          '<phon_data>\n'
          '\t<data_form>\n'
          '\t\t<frag a=\'single\' b="double"><open></open><closed /></frag>\n'
          '\t</data_form>\n'
          '</phon_data>\n';
      expect(renderCanonicalXml(parseDekerekeXml(source)), source);
    });

    test('comments inside records and under the root are preserved', () {
      const source = '<?xml version="1.0" encoding="utf-8" standalone="yes"?>\n'
          '<phon_data>\n'
          '\t<!-- top-level comment -->\n'
          '\t<data_form>\n'
          '\t\t<Reference>0001</Reference>\n'
          '\t\t<!-- in-record comment -->\n'
          '\t</data_form>\n'
          '</phon_data>\n';
      expect(renderCanonicalXml(parseDekerekeXml(source)), source);
    });

    test('unknown top-level elements are preserved', () {
      const source = '<?xml version="1.0" encoding="utf-8" standalone="yes"?>\n'
          '<phon_data>\n'
          '\t<future_metadata version="2" />\n'
          '\t<data_form>\n'
          '\t\t<Reference>0001</Reference>\n'
          '\t</data_form>\n'
          '</phon_data>\n';
      expect(renderCanonicalXml(parseDekerekeXml(source)), source);
    });
  });

  group('errors', () {
    test('rejects non-phon_data documents', () {
      expect(() => parseDekerekeXml('<Wordlist><Entry /></Wordlist>'),
          throwsFormatException);
    });

    test('rejects malformed XML', () {
      expect(() => parseDekerekeXml('<phon_data><data_form>'),
          throwsFormatException);
    });

    test('rejects loose text where Dekereke could not have written it', () {
      expect(() => parseDekerekeXml('<phon_data>loose</phon_data>'),
          throwsFormatException);
      expect(
          () => parseDekerekeXml(
              '<phon_data><data_form>loose<Reference>1</Reference></data_form></phon_data>'),
          throwsFormatException);
    });
  });

  group('record model helpers', () {
    test('withValue replaces in place, preserving order', () {
      final record = DekerekeRecord(const [
        DekerekeValueField('Reference', '0001'),
        DekerekeValueField('Phonetic', 'a'),
        DekerekeValueField('Notes', ''),
      ]);
      final updated = record.withValue('Phonetic', 'b');
      expect(updated.fields.map((f) => f.name), ['Reference', 'Phonetic', 'Notes']);
      expect(updated.valueOf('Phonetic'), 'b');
      expect(record.valueOf('Phonetic'), 'a', reason: 'original is immutable');
    });

    test('withValue appends when absent', () {
      final record = DekerekeRecord(const [DekerekeValueField('Reference', '1')]);
      final updated = record.withValue('Gloss', 'sun');
      expect(updated.fields.last, const DekerekeValueField('Gloss', 'sun'));
    });

    test('valueOf distinguishes absent (null) from empty ("")', () {
      final record = DekerekeRecord(const [DekerekeValueField('Notes', '')]);
      expect(record.valueOf('Notes'), '');
      expect(record.valueOf('Phonetic'), isNull);
    });
  });
}
