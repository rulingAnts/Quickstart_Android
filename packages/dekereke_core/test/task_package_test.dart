import 'dart:convert';
import 'dart:typed_data';

import 'package:dekereke_core/dekereke_core.dart';
import 'package:test/test.dart';

DekerekeRecord record(String ref, String gloss, {String soundFile = ''}) =>
    DekerekeRecord([
      DekerekeValueField('Reference', ref),
      DekerekeValueField('Gloss', gloss),
      DekerekeValueField('SoundFile', soundFile),
      const DekerekeValueField('Yohanis', ''),
    ]);

DekTaskPackage samplePackage() {
  final wordlist = DekerekeDatabase([
    record('0001', 'body', soundFile: '0001_body.wav'),
    record('0002', 'water (fresh)', soundFile: '0002_water.fresh (00392).wav'),
  ]);
  final task = DekTask(
    taskId: 'task-001',
    title: 'Yohanis records his pronunciation',
    baseCheckpointId: 'checkpoint-42',
    createdAt: '2026-07-02T12:00:00Z',
    fields: const [
      TaskField(column: 'Gloss', role: TaskFieldRole.visible),
      TaskField(
          column: 'SoundFile', role: TaskFieldRole.playable, suffix: ''),
      TaskField(
          column: 'Yohanis',
          role: TaskFieldRole.writable,
          input: TaskInputKind.both,
          suffix: '-yoh'),
    ],
    records: const [
      TaskRecordRef(dkSyncId: 'aaa', reference: '0001'),
      TaskRecordRef(dkSyncId: 'bbb', reference: '0002'),
    ],
    consent: const {'mode': 'audio', 'script': 'May we record you?'},
  );
  return DekTaskPackage(
    task: task,
    wordlist: wordlist,
    audio: {
      '0001_body.wav': Uint8List.fromList([1, 2, 3]),
      '0002_water.fresh (00392).wav': Uint8List.fromList([4, 5]),
    },
    pictures: {
      'body.png': Uint8List.fromList([9]),
    },
  );
}

DekResultPackage sampleResult() {
  const result = DekResult(
    taskId: 'task-001',
    baseCheckpointId: 'checkpoint-42',
    completedAt: '2026-07-03T09:00:00Z',
    values: [
      ResultValue(dkSyncId: 'aaa', column: 'Yohanis', value: 'bɔdi'),
    ],
    recordings: [
      ResultRecording(
          dkSyncId: 'aaa', column: 'Yohanis', filename: '0001_body-yoh.wav'),
    ],
    consentLog: [
      {'speaker': 'Yohanis', 'consented': true},
    ],
  );
  return DekResultPackage(
    result: result,
    audio: {
      '0001_body-yoh.wav': Uint8List.fromList([7, 7, 7]),
    },
  );
}

void main() {
  group('.dektask round-trip', () {
    test('encode → decode preserves everything', () {
      final package = samplePackage();
      final decoded = decodeDekTask(encodeDekTask(package));

      expect(decoded.task.taskId, 'task-001');
      expect(decoded.task.title, package.task.title);
      expect(decoded.task.baseCheckpointId, 'checkpoint-42');
      expect(decoded.task.createdAt, '2026-07-02T12:00:00Z');
      expect(decoded.task.fields, package.task.fields);
      expect(decoded.task.records, package.task.records);
      expect(decoded.task.consent, package.task.consent);
      expect(decoded.wordlist, package.wordlist);
      expect(decoded.audio.keys.toSet(), package.audio.keys.toSet());
      expect(decoded.audio['0001_body.wav'], [1, 2, 3]);
      expect(decoded.pictures['body.png'], [9]);
    });

    test('encoding is deterministic', () {
      expect(encodeDekTask(samplePackage()), encodeDekTask(samplePackage()));
    });

    test('wordlist inside the ZIP is canonical UTF-8 (phone-parseable)', () {
      final bytes = encodeDekTask(samplePackage());
      final decoded = decodeDekTask(bytes);
      // Same parse path the phone app import uses.
      expect(decoded.wordlist.records.first.gloss, 'body');
      expect(decoded.wordlist.records[1].soundFileCell,
          '0002_water.fresh (00392).wav');
    });

    test('identifiedRecords pairs wordlist rows with the ID map by position',
        () {
      final identified = samplePackage().identifiedRecords();
      expect(identified.map((r) => r.id), ['aaa', 'bbb']);
      expect(identified[1].record.reference, '0002');
    });

    test('rejects ID map / wordlist misalignment', () {
      final package = samplePackage();
      expect(
          () => DekTaskPackage(
                task: package.task,
                wordlist: DekerekeDatabase([record('0001', 'only one')]),
              ),
          throwsArgumentError);
    });

    test('rejects garbage, missing task.json, foreign format, future version',
        () {
      expect(() => decodeDekTask(Uint8List.fromList([1, 2, 3])),
          throwsFormatException);

      final empty = encodeDekResult(sampleResult()); // has no task.json
      expect(() => decodeDekTask(empty), throwsFormatException);

      final tampered = samplePackage();
      final json = jsonDecode(tampered.task.toJson()) as Map<String, Object?>;
      json['version'] = 999;
      expect(() => DekTask.fromJson(jsonEncode(json)), throwsFormatException);
    });

    test('writable fields must declare an input kind', () {
      expect(
          () => TaskField.fromJson(
              const {'column': 'X', 'role': 'writable'}),
          throwsFormatException);
    });
  });

  group('.dekresult round-trip', () {
    test('encode → decode preserves everything', () {
      final package = sampleResult();
      final decoded = decodeDekResult(encodeDekResult(package));
      expect(decoded.result.taskId, 'task-001');
      expect(decoded.result.completedAt, '2026-07-03T09:00:00Z');
      expect(decoded.result.values, package.result.values);
      expect(decoded.result.recordings, package.result.recordings);
      expect(decoded.result.consentLog, package.result.consentLog);
      expect(decoded.audio['0001_body-yoh.wav'], [7, 7, 7]);
    });

    test('encoding is deterministic', () {
      expect(encodeDekResult(sampleResult()), encodeDekResult(sampleResult()));
    });
  });

  group('validateResult', () {
    test('valid result has no problems', () {
      expect(validateResult(samplePackage().task, sampleResult()), isEmpty);
    });

    test('catches task mismatch, unknown records, non-writable columns, '
        'missing files', () {
      final task = samplePackage().task;
      final bad = DekResultPackage(
        result: const DekResult(
          taskId: 'other-task',
          baseCheckpointId: 'other-checkpoint',
          completedAt: '',
          values: [
            ResultValue(dkSyncId: 'zzz', column: 'Yohanis', value: 'x'),
            ResultValue(dkSyncId: 'aaa', column: 'Gloss', value: 'hacked'),
          ],
          recordings: [
            ResultRecording(
                dkSyncId: 'aaa', column: 'Gloss', filename: 'nope.wav'),
            ResultRecording(
                dkSyncId: 'aaa', column: 'Yohanis', filename: 'missing.wav'),
          ],
        ),
      );
      final problems = validateResult(task, bad);
      expect(problems, hasLength(7));
      expect(problems.join('\n'), contains('different task'));
      expect(problems.join('\n'), contains('checkpoint mismatch'));
      expect(problems.join('\n'), contains('unknown record zzz'));
      expect(problems.join('\n'), contains('non-writable column "Gloss"'));
      expect(problems.join('\n'), contains('does not collect audio'));
      expect(problems.join('\n'), contains('missing from the package'));
    });
  });

  group('merge-back (plan §5.3)', () {
    test('result values become the theirs side; researcher edits elsewhere '
        'auto-merge; same-cell edit conflicts', () {
      final package = samplePackage();
      final base = package.identifiedRecords();

      // Speaker filled Yohanis for record aaa (phone side).
      final theirs = applyResultValues(base, sampleResult().result);
      expect(theirs[0].record.valueOf('Yohanis'), 'bɔdi');
      expect(theirs[1].record.valueOf('Yohanis'), '');

      // Researcher meanwhile edited Gloss of bbb (non-task cell) — clean.
      final ours = [
        base[0],
        IdentifiedRecord(
            base[1].id, base[1].record.withValue('Gloss', 'water (spring)')),
      ];
      final clean = merge3(base: base, ours: ours, theirs: theirs);
      expect(clean.isClean, isTrue);
      expect(clean.records[0].record.valueOf('Yohanis'), 'bɔdi');
      expect(clean.records[1].record.valueOf('Gloss'), 'water (spring)');

      // Researcher edited the exact task cell too — that one conflicts.
      final oursConflicting = [
        IdentifiedRecord(
            base[0].id, base[0].record.withValue('Yohanis', 'researcher')),
        base[1],
      ];
      final conflicted =
          merge3(base: base, ours: oursConflicting, theirs: theirs);
      expect(conflicted.conflicts.single.fieldName, 'Yohanis');
      expect(conflicted.conflicts.single.theirValue, 'bɔdi');
    });

    test('applyResultValues rejects duplicate cell values', () {
      final base = samplePackage().identifiedRecords();
      const dupe = DekResult(
        taskId: 't',
        baseCheckpointId: 'c',
        completedAt: '',
        values: [
          ResultValue(dkSyncId: 'aaa', column: 'Yohanis', value: 'x'),
          ResultValue(dkSyncId: 'aaa', column: 'Yohanis', value: 'y'),
        ],
        recordings: [],
      );
      expect(() => applyResultValues(base, dupe), throwsArgumentError);
    });
  });

  group('suffix integration', () {
    test('recording filename follows the verified suffix rule', () {
      final task = samplePackage().task;
      final yohanis = task.fieldFor('Yohanis')!;
      expect(yohanis.collectsAudio, isTrue);
      expect(suffixedSoundFile('0001_body.wav', yohanis.suffix!),
          '0001_body-yoh.wav');
    });
  });
}
