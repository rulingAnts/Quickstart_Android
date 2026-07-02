import 'dart:io';
import 'dart:typed_data';

import 'package:dekereke_core/dekereke_core.dart';
import 'package:test/test.dart';

Uint8List _fixtureBytes() => File(
        '../../test_data/dekereke_fixtures/synthetic-DkUserSettings.xml')
    .readAsBytesSync();

void main() {
  group('parsing the settings fixture', () {
    late DkUserSettings settings;

    setUpAll(() => settings = DkUserSettings.parseBytes(_fixtureBytes()));

    test('suffix mappings parse TAB-separated entries, irregular styles included',
        () {
      expect(settings.suffixMappings, const [
        SuffixMapping('Phonetic', '-phon'),
        SuffixMapping('IndonesianGloss', '-phon'),
        SuffixMapping('SpeakerB', '-spkB'),
        SuffixMapping('Irregular1', '-tf_Xhi'),
        SuffixMapping('Irregular2', '-tf-Xko'),
      ]);
      expect(settings.suffixForColumn('SpeakerB'), '-spkB');
      expect(settings.suffixForColumn('Notes'), isNull);
    });

    test('column order parses name/position/width', () {
      expect(settings.columnOrder, const [
        ColumnOrderEntry('Reference', position: 0, width: 75),
        ColumnOrderEntry('Gloss', position: 1, width: 198),
        ColumnOrderEntry('Phonetic', position: 2, width: 120),
      ]);
    });

    test('string-list settings parse', () {
      expect(settings.hiddenColumns, ['Notes']);
      expect(settings.analysisColumns, ['Phonetic']);
      expect(settings.bannedOnsets, ['r']);
      expect(settings.syllableDivision, 'sonority');
    });

    test('machine-local paths are readable', () {
      expect(settings.soundFilePath, r'C:\\Users\\Demo\\Documents\\demo_db\\audio');
      expect(settings.valueOf('praat_path'), r'C:\\Program Files\\Praat\\Praat.exe');
    });

    test('boolean presence elements are preserved as elements', () {
      expect(settings.element('postalv_affricates_as_unit'), isNotNull);
      expect(settings.element('missing_sound_files_in_red'), isNotNull);
    });
  });

  group('round-trip', () {
    test('working-format re-encode of the fixture is BYTE-IDENTICAL', () {
      final bytes = _fixtureBytes();
      expect(DkUserSettings.parseBytes(bytes).encodeWorkingFile(), bytes);
    });

    test('open+close empty style survives (speech_analyzer_path)', () {
      final settings = DkUserSettings.parseBytes(_fixtureBytes());
      expect(settings.element('speech_analyzer_path')!.xml,
          '<speech_analyzer_path></speech_analyzer_path>');
    });

    test('canonical rendering is a fixed point and UTF-8/LF', () {
      final settings = DkUserSettings.parseBytes(_fixtureBytes());
      final canonical = settings.renderCanonicalXml();
      expect(canonical, startsWith('$canonicalXmlDeclaration\n'));
      expect(canonical, isNot(contains('\r')));
      expect(DkUserSettings.parse(canonical).renderCanonicalXml(), canonical);
    });
  });

  group('shared vs machine-local split (plan §4.1)', () {
    test('local paths never appear in the shared part', () {
      final split = DkUserSettings.parseBytes(_fixtureBytes()).splitMachineLocal();
      final sharedXml = split.shared.renderCanonicalXml();
      expect(sharedXml, isNot(contains(r'C:\')));
      expect(sharedXml, contains('<sound_file_path />'),
          reason: 'structure/order preserved, value emptied');
      expect(split.local.keys.toSet(), {
        'sound_file_path',
        'acoustic_analyzer_path',
        'speech_analyzer_path',
        'praat_path',
      });
    });

    test('shared part keeps all shared settings verbatim', () {
      final split = DkUserSettings.parseBytes(_fixtureBytes()).splitMachineLocal();
      expect(split.shared.suffixMappings, hasLength(5));
      expect(split.shared.columnOrder, hasLength(3));
      expect(split.shared.hiddenColumns, ['Notes']);
    });

    test('split + merge reassembles the original file byte-identically', () {
      final bytes = _fixtureBytes();
      final settings = DkUserSettings.parseBytes(bytes);
      final split = settings.splitMachineLocal();
      final reassembled = split.shared.mergeMachineLocal(split.local);
      expect(reassembled.encodeWorkingFile(), bytes,
          reason: 'same machine must get its exact settings file back');
    });

    test('another machine merges its own local paths into the same shared part',
        () {
      final split = DkUserSettings.parseBytes(_fixtureBytes()).splitMachineLocal();
      final other = split.shared.mergeMachineLocal({
        'sound_file_path':
            DkSettingElement.text('sound_file_path', r'D:\field\audio'),
      });
      expect(other.soundFilePath, r'D:\field\audio');
      // Un-overridden local slots stay empty — no foreign paths leak in.
      expect(other.valueOf('praat_path'), '');
      // Shared config identical.
      expect(other.suffixMappings, split.shared.suffixMappings);
    });
  });

  group('mutation helpers', () {
    test('withValue replaces in place', () {
      final settings = DkUserSettings.parseBytes(_fixtureBytes())
          .withValue('syllable_division', 'manual');
      expect(settings.syllableDivision, 'manual');
      expect(settings.elements.map((e) => e.name),
          DkUserSettings.parseBytes(_fixtureBytes()).elements.map((e) => e.name),
          reason: 'element order unchanged');
    });

    test('withValue appends when absent', () {
      final settings =
          DkUserSettings.parseBytes(_fixtureBytes()).withValue('new_setting', 'x');
      expect(settings.elements.last, DkSettingElement.text('new_setting', 'x'));
    });

    test('DkSettingElement.text escapes and self-closes empties', () {
      expect(DkSettingElement.text('a', '').xml, '<a />');
      expect(DkSettingElement.text('a', 'x & y').xml, '<a>x &amp; y</a>');
    });
  });

  group('errors', () {
    test('rejects non-settings documents', () {
      expect(() => DkUserSettings.parse('<phon_data />'), throwsFormatException);
    });

    test('rejects malformed XML', () {
      expect(() => DkUserSettings.parse('<settings><a>'), throwsFormatException);
    });
  });
}
