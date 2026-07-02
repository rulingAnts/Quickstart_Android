import 'dart:io';
import 'dart:typed_data';

import 'package:dekereke_core/dekereke_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wordlist_elicitation/models/consent_record.dart';
import 'package:wordlist_elicitation/services/database_service.dart';
import 'package:wordlist_elicitation/services/task_service.dart';

DekerekeRecord _record(String ref, String gloss,
        {String soundFile = '', String indonesian = ''}) =>
    DekerekeRecord([
      DekerekeValueField('Reference', ref),
      DekerekeValueField('Gloss', gloss),
      DekerekeValueField('IndonesianGloss', indonesian),
      DekerekeValueField('SoundFile', soundFile),
      const DekerekeValueField('Yohanis', ''),
    ]);

/// A task exercising every field role: a visible prompt, a playable
/// reference column, and a writable text+audio column with a suffix.
DekTaskPackage _taskPackage({List<DekerekeRecord>? records, List<TaskRecordRef>? refs}) {
  final wordlist = DekerekeDatabase(records ??
      [
        _record('0001', 'body',
            soundFile: '0001_body.wav', indonesian: 'tubuh'),
        _record('0002', 'water (fresh)',
            soundFile: '0002_water.fresh (00392).wav', indonesian: 'air'),
      ]);
  return DekTaskPackage(
    task: DekTask(
      taskId: 'task-001',
      title: 'Yohanis records his words',
      baseCheckpointId: 'checkpoint-42',
      createdAt: '2026-07-02T12:00:00Z',
      fields: const [
        TaskField(column: 'Gloss', role: TaskFieldRole.visible),
        TaskField(column: 'IndonesianGloss', role: TaskFieldRole.visible),
        TaskField(
            column: 'SoundFile', role: TaskFieldRole.playable, suffix: ''),
        TaskField(
            column: 'Yohanis',
            role: TaskFieldRole.writable,
            input: TaskInputKind.both,
            suffix: '-yoh'),
      ],
      records: refs ??
          const [
            TaskRecordRef(dkSyncId: 'aaa', reference: '0001'),
            TaskRecordRef(dkSyncId: 'bbb', reference: '0002'),
          ],
    ),
    wordlist: wordlist,
    audio: {
      '0001_body.wav': Uint8List.fromList([1, 2, 3]),
    },
    pictures: {
      'body.png': Uint8List.fromList([9, 9]),
    },
  );
}

void main() {
  late Directory tempDir;
  late TaskService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseService.databaseName = 'test_task.db';
    await DatabaseService.instance.close();
    await deleteDatabase(
        p.join(await getDatabasesPath(), DatabaseService.databaseName));
    tempDir = await Directory.systemTemp.createTemp('task_test');
    service = TaskService(baseDirectoryOverride: tempDir);
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    await deleteDatabase(
        p.join(await getDatabasesPath(), DatabaseService.databaseName));
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<String> writeTaskFile(DekTaskPackage package) async {
    final path = '${tempDir.path}/incoming.dektask';
    await File(path).writeAsBytes(encodeDekTask(package));
    return path;
  }

  group('importDekTask', () {
    test('imports entries with DkSyncIDs and activates the task', () async {
      final result = await service.importDekTask(await writeTaskFile(_taskPackage()));

      expect(result.imported, 2);
      expect(result.skippedUnusableReference, 0);
      expect(result.task.taskId, 'task-001');

      final entries = await DatabaseService.instance.getAllWordlistEntries();
      expect(entries, hasLength(2));
      expect(entries[0].dkSyncId, 'aaa');
      expect(entries[0].gloss, 'body');
      expect(entries[0].glossIndonesian, 'tubuh');
      expect(entries[1].dkSyncId, 'bbb');
      expect(entries[1].soundFile, '0002_water.fresh (00392).wav');

      final active = await service.getActiveTask();
      expect(active, isNotNull);
      expect(active!.taskId, 'task-001');
      expect(active.writableFields.single.column, 'Yohanis');
    });

    test('unpacks bundled reference audio and pictures', () async {
      await service.importDekTask(await writeTaskFile(_taskPackage()));
      expect(
          await File('${tempDir.path}/task_audio/0001_body.wav').readAsBytes(),
          [1, 2, 3]);
      expect(await File('${tempDir.path}/pictures/body.png').exists(), isTrue);
    });

    test('skips records with empty or duplicate References, reports count',
        () async {
      final package = _taskPackage(
        records: [
          _record('0001', 'body'),
          _record('', 'no reference'),
          _record('0001', 'duplicate reference'),
        ],
        refs: const [
          TaskRecordRef(dkSyncId: 'aaa', reference: '0001'),
          TaskRecordRef(dkSyncId: 'bbb', reference: ''),
          TaskRecordRef(dkSyncId: 'ccc', reference: '0001'),
        ],
      );
      final result = await service.importDekTask(await writeTaskFile(package));
      expect(result.imported, 1);
      expect(result.skippedUnusableReference, 2);
    });

    test('rejects a task whose audio column has no suffix', () async {
      final package = _taskPackage();
      final badTask = DekTask(
        taskId: package.task.taskId,
        title: package.task.title,
        baseCheckpointId: package.task.baseCheckpointId,
        createdAt: package.task.createdAt,
        fields: const [
          TaskField(
              column: 'Yohanis',
              role: TaskFieldRole.writable,
              input: TaskInputKind.audio),
        ],
        records: package.task.records,
      );
      final bad = DekTaskPackage(
          task: badTask, wordlist: package.wordlist, audio: package.audio);
      expect(
        () async => service.importDekTask(await writeTaskFile(bad)),
        throwsA(isA<FormatException>()),
      );
    });

    test('clearActiveTask returns the app to plain mode', () async {
      await service.importDekTask(await writeTaskFile(_taskPackage()));
      await DatabaseService.instance.setTaskValue('aaa', 'Yohanis', 'x');
      await service.clearActiveTask();
      expect(await service.getActiveTask(), isNull);
      expect(await DatabaseService.instance.getAllTaskValues(), isEmpty);
    });
  });

  group('task audio helpers', () {
    test('recordingFilenameFor applies the suffix rule to the SoundFile base',
        () async {
      await service.importDekTask(await writeTaskFile(_taskPackage()));
      final entries = await DatabaseService.instance.getAllWordlistEntries();
      final task = (await service.getActiveTask())!;
      final field = task.writableFields.single;

      expect(service.recordingFilenameFor(entries[0], field),
          '0001_body-yoh.wav');
      expect(service.recordingFilenameFor(entries[1], field),
          '0002_water.fresh (00392)-yoh.wav');
    });

    test('recordingFilenameFor uses the first file of a multi-file cell',
        () async {
      final package = _taskPackage(
        records: [
          _record('0005', 'go / walk', soundFile: '0005_go.wav|0005_go_alt.wav'),
        ],
        refs: const [TaskRecordRef(dkSyncId: 'eee', reference: '0005')],
      );
      await service.importDekTask(await writeTaskFile(package));
      final entry =
          (await DatabaseService.instance.getAllWordlistEntries()).single;
      final field = (await service.getActiveTask())!.writableFields.single;
      expect(service.recordingFilenameFor(entry, field), '0005_go-yoh.wav');
    });

    test('recordingFilenameFor falls back to reference+gloss naming', () async {
      final package = _taskPackage(
        records: [_record('0009', 'new word')],
        refs: const [TaskRecordRef(dkSyncId: 'fff', reference: '0009')],
      );
      await service.importDekTask(await writeTaskFile(package));
      final entry =
          (await DatabaseService.instance.getAllWordlistEntries()).single;
      final field = (await service.getActiveTask())!.writableFields.single;
      expect(service.recordingFilenameFor(entry, field), '0009new.word-yoh.wav');
    });

    test('findReferenceAudio resolves .wav and falls back to .flac (D3)',
        () async {
      await service.importDekTask(await writeTaskFile(_taskPackage()));
      expect(await service.findReferenceAudio('0001_body.wav'),
          '${tempDir.path}/task_audio/0001_body.wav');
      expect(await service.findReferenceAudio('missing.wav'), isNull);

      // A FLAC-compressed reference (the one allowed FLAC direction).
      await File('${tempDir.path}/task_audio/0002_water-phon.flac')
          .writeAsBytes([4, 4]);
      expect(await service.findReferenceAudio('0002_water-phon.wav'),
          '${tempDir.path}/task_audio/0002_water-phon.flac');
    });
  });

  group('exportDekResult', () {
    test('builds a valid .dekresult that round-trips through the core',
        () async {
      await service.importDekTask(await writeTaskFile(_taskPackage()));
      final db = DatabaseService.instance;

      await db.setTaskValue('aaa', 'Yohanis', 'bɔdi');
      await db.setTaskRecording('aaa', 'Yohanis', '0001_body-yoh.wav');
      final audioDir = Directory('${tempDir.path}/audio');
      await audioDir.create(recursive: true);
      await File('${audioDir.path}/0001_body-yoh.wav')
          .writeAsBytes(List.filled(32, 7));

      await db.insertConsentRecord(ConsentRecord(
        timestamp: DateTime(2026, 7, 2),
        deviceId: 'device-1',
        type: ConsentType.verbal,
        response: ConsentResponse.assent,
      ));

      final path = await service.exportDekResult();
      expect(path, endsWith('.dekresult'));

      final decoded = decodeDekResult(await File(path).readAsBytes());
      expect(decoded.result.taskId, 'task-001');
      expect(decoded.result.baseCheckpointId, 'checkpoint-42');
      expect(decoded.result.values.single,
          const ResultValue(dkSyncId: 'aaa', column: 'Yohanis', value: 'bɔdi'));
      expect(decoded.result.recordings.single.filename, '0001_body-yoh.wav');
      expect(decoded.audio['0001_body-yoh.wav'], List.filled(32, 7));
      expect(decoded.result.consentLog, hasLength(1));

      // The researcher-side validation must accept it.
      final task = (await service.getActiveTask())!;
      expect(validateResult(task, decoded), isEmpty);
    });

    test('drops recording rows whose WAV is missing from disk', () async {
      await service.importDekTask(await writeTaskFile(_taskPackage()));
      final db = DatabaseService.instance;
      await db.setTaskValue('bbb', 'Yohanis', 'answer');
      await db.setTaskRecording('aaa', 'Yohanis', 'gone.wav');

      final decoded =
          decodeDekResult(await File(await service.exportDekResult()).readAsBytes());
      expect(decoded.result.recordings, isEmpty);
      expect(decoded.result.values, hasLength(1));
    });

    test('replaces the previous result file', () async {
      await service.importDekTask(await writeTaskFile(_taskPackage()));
      await DatabaseService.instance.setTaskValue('aaa', 'Yohanis', 'one');
      final first = await service.exportDekResult();
      // Same-second timestamps produce the same name; ensure distinct.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final second = await service.exportDekResult();
      expect(await File(second).exists(), isTrue);
      if (first != second) {
        expect(await File(first).exists(), isFalse,
            reason: 'old result files are swept');
      }
    });

    test('throws without an active task', () async {
      expect(() => service.exportDekResult(), throwsStateError);
    });
  });
}
