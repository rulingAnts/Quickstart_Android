/// Generates the P0 verification kit (see `test_data/p0_test_kit/`):
/// a disposable Dekereke TestDB with planted probe tags, a matching
/// settings file, an Update-From-File probe, and audible test WAVs —
/// everything `CHECKLIST.md` walks through on the Windows VM.
///
/// Run from the package root:
///
///     dart tool/generate_p0_kit.dart [output-dir]
///
/// Output defaults to `../../test_data/p0_test_kit`. Deterministic: the
/// same inputs always produce byte-identical files.
library;

import 'dart:io';

import 'package:dekereke_core/dekereke_core.dart';

import 'wav_util.dart';

DekerekeRecord record(
  String ref,
  String gloss, {
  String indonesian = '',
  String category = 'N',
  String phonetic = '',
  String speakerB = '',
  String notes = '',
  String soundFile = '',
  List<DekerekeField> extras = const [],
}) =>
    DekerekeRecord([
      DekerekeValueField('Reference', ref),
      DekerekeValueField('Gloss', gloss),
      DekerekeValueField('IndonesianGloss', indonesian),
      DekerekeValueField('Category', category),
      DekerekeValueField('Phonetic', phonetic),
      DekerekeValueField('SpeakerB', speakerB),
      DekerekeValueField('Notes', notes),
      DekerekeValueField('SoundFile', soundFile),
      ...extras,
    ]);

void main(List<String> args) {
  final outDir = args.isNotEmpty ? args[0] : '../../test_data/p0_test_kit';
  Directory(outDir).createSync(recursive: true);
  Directory('$outDir/audio').createSync(recursive: true);

  // ---- TestDB.xml ----------------------------------------------------------
  // Records deliberately NOT in Reference order (0001, 0003, 0002, …):
  // whether a save re-sorts the file is exactly P0 #3.
  final db = DekerekeDatabase([
    record(
      '0001',
      'body',
      indonesian: 'tubuh',
      phonetic: 'bɔdi',
      notes: 'Probe record: has an unknown FLAT tag below',
      soundFile: '0001_body.wav',
      extras: const [
        // P0 #1a: unknown flat tag — does it show in the grid? survive save?
        DekerekeValueField('ProbeFlatTag', 'PROBE-FLAT-SURVIVES'),
      ],
    ),
    record(
      '0003',
      'ear',
      indonesian: 'telinga',
      phonetic: 'ɛnɔ',
      notes: 'ORDER PROBE: this record comes BEFORE 0002 in the file',
    ),
    record(
      '0002',
      'water',
      indonesian: 'air',
      phonetic: 'ɸaʔɛ',
      notes: 'Probe record: has an unknown NESTED tag below',
      extras: const [
        // P0 #1b: unknown nested structure, mimicking how QuickVPlot nests
        // its own <qvp_acoustic_data_> inside records.
        DekerekeFragmentField(
          'probe_nested_data',
          '<probe_nested_data>\n'
              '\t\t\t<probe_child>PROBE-NESTED-SURVIVES</probe_child>\n'
              '\t\t</probe_nested_data>',
        ),
        // Booleans are presence-only tags; check one survives too.
        DekerekeValueField('Confirmed', ''),
      ],
    ),
    record(
      '0004',
      'sun',
      indonesian: 'matahari',
      notes: 'RECORDER TARGET: SoundFile is empty on purpose (P0 #6)',
    ),
    record(
      '0005',
      'go / walk',
      indonesian: 'pergi',
      category: 'V',
      notes: 'SEPARATOR PROBE: pipe between two files (P0 #7)',
      soundFile: '0005_go.wav|0005_go_alt.wav',
    ),
    record(
      '0006',
      'moon',
      indonesian: 'bulan',
      notes: 'SEPARATOR PROBE: comma between two files (P0 #7)',
      soundFile: '0006_moon.wav, 0006_moon_alt.wav',
    ),
  ]);
  File('$outDir/TestDB.xml').writeAsBytesSync(encodeWorkingFile(db));

  // ---- TestDB-update.xml ---------------------------------------------------
  // Fed to Tools > Update Current Data From File: modifies 0003 and appends
  // 0007 — records 0001/0002 (the probe carriers) are deliberately absent,
  // so after the update their probes must still be in the database (P0 #1c).
  final update = DekerekeDatabase([
    record(
      '0003',
      'ear',
      indonesian: 'telinga',
      phonetic: 'ɛnɔː',
      notes: 'UPDATED-VIA-UPDATE-FROM-FILE',
    ),
    record(
      '0007',
      'star',
      indonesian: 'bintang',
      notes: 'NEW record appended by Update From File',
    ),
  ]);
  File('$outDir/TestDB-update.xml').writeAsBytesSync(encodeWorkingFile(update));

  // ---- TestDB-DkUserSettings.xml -------------------------------------------
  // Suffix mappings for the recorder/suffix tests. Machine-local paths are
  // left empty — the checklist has Dekereke's own UI set the audio folder.
  final settings = DkUserSettings([
    DkSettingElement.text('sound_file_path', ''),
    const DkSettingElement(
      'column_to_sound_file_suffix_mappings',
      '<column_to_sound_file_suffix_mappings>\n'
          '\t\t<column_to_sound_file_suffix_mapping>Phonetic\t-phon</column_to_sound_file_suffix_mapping>\n'
          '\t\t<column_to_sound_file_suffix_mapping>SpeakerB\t-spkB</column_to_sound_file_suffix_mapping>\n'
          '\t</column_to_sound_file_suffix_mappings>',
    ),
  ]);
  File('$outDir/TestDB-DkUserSettings.xml')
      .writeAsBytesSync(settings.encodeWorkingFile());

  // ---- Audible test WAVs (16-bit mono, distinct pitches) --------------------
  // Distinct tones so "which file played?" is answerable by ear (P0 #7).
  const tones = {
    '0001_body.wav': 550.0, // ~C#5
    '0001_body-phon.wav': 700.0, // suffix-column playback check
    '0005_go.wav': 440.0, // A4  (first of the pipe pair)
    '0005_go_alt.wav': 880.0, // A5  (second of the pipe pair)
    '0006_moon.wav': 330.0, // E4  (first of the comma pair)
    '0006_moon_alt.wav': 660.0, // E5  (second of the comma pair)
  };
  tones.forEach((name, frequency) {
    File('$outDir/audio/$name').writeAsBytesSync(sineWav(frequency));
  });

  stdout.writeln('P0 kit written to $outDir');
}
