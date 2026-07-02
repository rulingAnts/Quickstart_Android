import 'dart:io';

import 'package:dekereke_core/dekereke_core.dart';
import 'package:test/test.dart';

DekerekeRecord record(String ref, String gloss,
        {String soundFile = '', String phonetic = '', String speakerB = ''}) =>
    DekerekeRecord([
      DekerekeValueField('Reference', ref),
      DekerekeValueField('Gloss', gloss),
      DekerekeValueField('Phonetic', phonetic),
      DekerekeValueField('SpeakerB', speakerB),
      DekerekeValueField('SoundFile', soundFile),
    ]);

DkUserSettings settingsWithSuffixes() => const DkUserSettings([
      DkSettingElement(
        'column_to_sound_file_suffix_mappings',
        '<column_to_sound_file_suffix_mappings>'
            '<column_to_sound_file_suffix_mapping>Phonetic\t-phon</column_to_sound_file_suffix_mapping>'
            '<column_to_sound_file_suffix_mapping>SpeakerB\t-spkB</column_to_sound_file_suffix_mapping>'
            '</column_to_sound_file_suffix_mappings>',
      ),
    ]);

List<HealthIssue> ofKind(List<HealthIssue> issues, HealthIssueKind kind) =>
    issues.where((i) => i.kind == kind).toList();

void main() {
  test('healthy database with matching folder produces no findings', () {
    final db = DekerekeDatabase([
      record('0001', 'body', soundFile: '0001_body.wav', phonetic: 'bɔdi'),
      record('0002', 'water'),
    ]);
    final issues = checkDatabaseHealth(
      db,
      audioFilenames: ['0001_body.wav', '0001_body-phon.wav'],
      settings: settingsWithSuffixes(),
    );
    expect(issues, isEmpty);
  });

  test('duplicate References are one finding listing every twin', () {
    final db = DekerekeDatabase([
      record('0002', 'water (fresh)'),
      record('0001', 'body'),
      record('0002', 'water (in river)'),
    ]);
    final issues = checkDatabaseHealth(db);
    final duplicates = ofKind(issues, HealthIssueKind.duplicateReference);
    expect(duplicates, hasLength(1));
    expect(duplicates.single.recordPositions, [0, 2]);
    expect(duplicates.single.severity, HealthSeverity.problem);
    expect(duplicates.single.message, contains('water (fresh)'));
    expect(duplicates.single.message, contains('water (in river)'));
  });

  test('empty Reference flagged per record', () {
    final db = DekerekeDatabase([
      record('', 'ear'),
      record('0001', 'body'),
    ]);
    final issues = checkDatabaseHealth(db);
    final empties = ofKind(issues, HealthIssueKind.emptyReference);
    expect(empties.single.recordPositions, [0]);
    expect(empties.single.message, contains('"ear"'));
  });

  test('SoundFile that does not start with the Reference is flagged', () {
    final db = DekerekeDatabase([
      record('0001', 'body', soundFile: '0002_wrong.wav'),
      record('0002', 'water', soundFile: '0002_water.wav'),
    ]);
    final issues = checkDatabaseHealth(db);
    final mismatches =
        ofKind(issues, HealthIssueKind.soundFileReferenceMismatch);
    expect(mismatches.single.filename, '0002_wrong.wav');
    expect(mismatches.single.reference, '0001');
  });

  test('multi-file cells are checked per file', () {
    final db = DekerekeDatabase([
      record('0005', 'go', soundFile: '0005_go.wav|9999_alt.wav'),
    ]);
    final issues = checkDatabaseHealth(db);
    final mismatches =
        ofKind(issues, HealthIssueKind.soundFileReferenceMismatch);
    expect(mismatches.single.filename, '9999_alt.wav');
  });

  group('folder rules', () {
    test('missing audio file is a problem', () {
      final db = DekerekeDatabase([
        record('0001', 'body', soundFile: '0001_body.wav'),
      ]);
      final issues = checkDatabaseHealth(db, audioFilenames: const <String>[]);
      final missing = ofKind(issues, HealthIssueKind.missingAudioFile);
      expect(missing.single.filename, '0001_body.wav');
      expect(missing.single.severity, HealthSeverity.problem);
    });

    test('missing suffix file only expected when the mapped column has data',
        () {
      final db = DekerekeDatabase([
        // Phonetic filled → -phon variant expected.
        record('0001', 'body', soundFile: '0001_body.wav', phonetic: 'bɔdi'),
        // SpeakerB empty → no -spkB expectation.
        record('0002', 'water', soundFile: '0002_water.wav'),
      ]);
      final issues = checkDatabaseHealth(
        db,
        audioFilenames: ['0001_body.wav', '0002_water.wav'],
        settings: settingsWithSuffixes(),
      );
      final missing = ofKind(issues, HealthIssueKind.missingSuffixFile);
      expect(missing.single.filename, '0001_body-phon.wav');
      expect(missing.single.severity, HealthSeverity.warning);
    });

    test('orphaned files are reported once each, sorted', () {
      final db = DekerekeDatabase([
        record('0001', 'body', soundFile: '0001_body.wav', phonetic: 'x'),
      ]);
      final issues = checkDatabaseHealth(
        db,
        audioFilenames: [
          '0001_body.wav',
          '0001_body-phon.wav', // accounted via suffix mapping
          'zz_stray.wav',
          'aa_stray.wav',
        ],
        settings: settingsWithSuffixes(),
      );
      final orphans = ofKind(issues, HealthIssueKind.orphanedAudioFile);
      expect(orphans.map((o) => o.filename), ['aa_stray.wav', 'zz_stray.wav']);
    });

    test('suffix variants count as accounted even without column data', () {
      // A -spkB file exists though SpeakerB is empty: it must NOT show up
      // as an orphan (the mapping explains it), and emptiness of the
      // column must not demand it either.
      final db = DekerekeDatabase([
        record('0001', 'body', soundFile: '0001_body.wav'),
      ]);
      final issues = checkDatabaseHealth(
        db,
        audioFilenames: ['0001_body.wav', '0001_body-spkB.wav'],
        settings: settingsWithSuffixes(),
      );
      expect(issues, isEmpty);
    });

    test('folder rules are skipped without a folder listing', () {
      final db = DekerekeDatabase([
        record('0001', 'body', soundFile: '0001_body.wav'),
      ]);
      expect(checkDatabaseHealth(db), isEmpty);
    });
  });

  test('the synthetic fixture yields exactly its planted problems', () {
    final db = parseDekerekeFile(
        File('../../test_data/dekereke_fixtures/synthetic_db.xml')
            .readAsBytesSync());
    final issues = checkDatabaseHealth(db);
    expect(ofKind(issues, HealthIssueKind.duplicateReference), hasLength(1),
        reason: 'two 0002 records');
    expect(ofKind(issues, HealthIssueKind.emptyReference), hasLength(1),
        reason: 'the ear record');
  });
}
