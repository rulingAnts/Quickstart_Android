/// Generates the sample task package (`test_data/sample_task/`) used to
/// smoke-test the phone app's task mode end-to-end: import the .dektask,
/// elicit, export the .dekresult.
///
/// Run from the package root:
///
///     dart tool/generate_sample_dektask.dart [output-dir]
library;

import 'dart:io';

import 'package:dekereke_core/dekereke_core.dart';

import 'wav_util.dart';

DekerekeRecord record(String ref, String gloss, String indonesian,
        {String soundFile = ''}) =>
    DekerekeRecord([
      DekerekeValueField('Reference', ref),
      DekerekeValueField('Gloss', gloss),
      DekerekeValueField('IndonesianGloss', indonesian),
      DekerekeValueField('Phonetic', ''),
      DekerekeValueField('SoundFile', soundFile),
      const DekerekeValueField('Yohanis', ''),
    ]);

void main(List<String> args) {
  final outDir = args.isNotEmpty ? args[0] : '../../test_data/sample_task';
  Directory(outDir).createSync(recursive: true);

  final wordlist = DekerekeDatabase([
    record('0001', 'body', 'tubuh', soundFile: '0001_body.wav'),
    record('0002', 'water', 'air', soundFile: '0002_water.wav'),
    record('0003', 'ear', 'telinga', soundFile: '0003_ear.wav'),
    record('0004', 'sun', 'matahari'),
    record('0005', 'go / walk', 'pergi', soundFile: '0005_go.wav'),
    record('0006', 'moon', 'bulan'),
  ]);

  final task = DekTask(
    taskId: 'sample-task-001',
    title: 'Sample task: record your words',
    baseCheckpointId: 'sample-checkpoint',
    createdAt: '2026-07-02T12:00:00Z',
    fields: const [
      TaskField(column: 'Gloss', role: TaskFieldRole.visible),
      TaskField(column: 'IndonesianGloss', role: TaskFieldRole.visible),
      TaskField(column: 'SoundFile', role: TaskFieldRole.playable, suffix: ''),
      TaskField(
          column: 'Yohanis',
          role: TaskFieldRole.writable,
          input: TaskInputKind.both,
          suffix: '-yoh'),
    ],
    records: const [
      TaskRecordRef(dkSyncId: 'sample0001', reference: '0001'),
      TaskRecordRef(dkSyncId: 'sample0002', reference: '0002'),
      TaskRecordRef(dkSyncId: 'sample0003', reference: '0003'),
      TaskRecordRef(dkSyncId: 'sample0004', reference: '0004'),
      TaskRecordRef(dkSyncId: 'sample0005', reference: '0005'),
      TaskRecordRef(dkSyncId: 'sample0006', reference: '0006'),
    ],
    consent: const {'note': 'sample task for smoke testing'},
  );

  // Distinct pitches so "did the right reference play?" is answerable by
  // ear; 0004/0006 have no reference audio on purpose (tests the
  // no-audio path).
  final package = DekTaskPackage(
    task: task,
    wordlist: wordlist,
    audio: {
      '0001_body.wav': sineWav(550),
      '0002_water.wav': sineWav(440),
      '0003_ear.wav': sineWav(330),
      '0005_go.wav': sineWav(660),
    },
  );

  File('$outDir/sample.dektask').writeAsBytesSync(encodeDekTask(package));
  stdout.writeln('Sample task written to $outDir/sample.dektask');
}
