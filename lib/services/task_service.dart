import 'dart:io';
import 'dart:typed_data';

import 'package:dekereke_core/dekereke_core.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/wordlist_entry.dart';
import 'database_service.dart';

/// Result of importing a `.dektask` package.
class TaskImportResult {
  final int imported;

  /// Records skipped because their Reference was empty or duplicated —
  /// this app keys entries by Reference (unique index), so the researcher
  /// must renumber before delegating such records.
  final int skippedUnusableReference;

  final DekTask task;

  const TaskImportResult({
    required this.imported,
    required this.skippedUnusableReference,
    required this.task,
  });
}

/// Task mode (plan §5.4): imports `.dektask` packages built by the
/// Companion, stores the task configuration and its wordlist subset, and
/// exports the collected answers as a `.dekresult`.
///
/// The task's DkSyncID map travels in `task.json` and is stored per entry;
/// results are keyed on it, never on Reference (decision D2).
class TaskService {
  final DatabaseService _db = DatabaseService.instance;

  /// Directory that holds the app's data. Defaults to the application
  /// documents directory; injectable for tests.
  final Directory? baseDirectoryOverride;

  TaskService({this.baseDirectoryOverride});

  static const activeTaskSettingKey = 'active_task_json';

  Future<Directory> get _baseDirectory async =>
      baseDirectoryOverride ?? await getApplicationDocumentsDirectory();

  /// The active task, or null when the app is in plain-wordlist mode (or
  /// the stored task is unreadable).
  Future<DekTask?> getActiveTask() async {
    final json = await _db.getSetting(activeTaskSettingKey);
    if (json == null || json.isEmpty) return null;
    try {
      return DekTask.fromJson(json);
    } on FormatException {
      return null;
    }
  }

  /// Leaves task mode (used when a plain XML wordlist is imported over a
  /// task). Collected task data is cleared with it.
  Future<void> clearActiveTask() async {
    await _db.setSetting(activeTaskSettingKey, '');
    await _db.clearTaskData();
  }

  /// Imports a `.dektask` file: validates it, replaces the wordlist with
  /// the task's subset (entries keep their DkSyncIDs), stores the task
  /// config, and unpacks bundled reference audio and pictures.
  Future<TaskImportResult> importDekTask(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }
    final package = decodeDekTask(await file.readAsBytes());
    final task = package.task;

    // Audio-collecting fields must carry the suffix their recordings are
    // named with; a task without one cannot be collected faithfully.
    for (final field in task.writableFields) {
      if (field.collectsAudio && (field.suffix == null || field.suffix!.isEmpty)) {
        throw FormatException(
            'This task\'s column "${field.column}" collects audio but has '
            'no recording suffix — ask for a corrected task file.');
      }
    }

    final entries = <WordlistEntry>[];
    final seenReferences = <String>{};
    var skipped = 0;
    for (final identified in package.identifiedRecords()) {
      final record = identified.record;
      final reference = record.reference;
      if (reference.isEmpty || !seenReferences.add(reference)) {
        // This app keys entries by Reference (unique index); the ID map
        // makes the gap visible to the researcher on merge-back.
        skipped++;
        continue;
      }
      final valueFields = [
        for (final field in record.fields)
          if (field is DekerekeValueField) MapEntry(field.name, field.value),
      ];
      entries.add(WordlistEntry(
        reference: reference,
        gloss: record.gloss,
        glossIndonesian: _emptyToNull(record.valueOf('GlossIndonesian') ??
            record.valueOf('IndonesianGloss')),
        glossTokPisin: _emptyToNull(record.valueOf('GlossTokPisin')),
        category: _emptyToNull(record.valueOf('Category')),
        semanticDomain: _emptyToNull(record.valueOf('SemanticDomain')),
        soundFile: _emptyToNull(record.soundFileCell),
        pictureFilename: _emptyToNull(record.valueOf('Image_File') ??
            record.valueOf('Picture')),
        xmlFieldsJson: WordlistEntry.encodeXmlFields(valueFields),
        dkSyncId: identified.id,
      ));
    }
    if (entries.isEmpty) {
      throw const FormatException(
          'The task contains no usable records (every record needs a '
          'unique reference number).');
    }

    final imported = await _db.replaceAllEntries(entries);
    await _db.clearTaskData();
    await _db.setSetting(activeTaskSettingKey, task.toJson());

    await _unpackFiles(package.audio, 'task_audio', clearFirst: true);
    await _unpackFiles(package.pictures, 'pictures');

    return TaskImportResult(
      imported: imported,
      skippedUnusableReference: skipped,
      task: task,
    );
  }

  Future<void> _unpackFiles(Map<String, List<int>> files, String dirName,
      {bool clearFirst = false}) async {
    final base = await _baseDirectory;
    final dir = Directory('${base.path}/$dirName');
    if (clearFirst && await dir.exists()) {
      await dir.delete(recursive: true);
    }
    if (files.isEmpty) return;
    await dir.create(recursive: true);
    for (final entry in files.entries) {
      await File('${dir.path}/${entry.key}').writeAsBytes(entry.value);
    }
  }

  /// Full path of a bundled reference audio file for [playableFilename]
  /// (the suffix-rule WAV name). The Companion may bundle it as `.wav` or
  /// FLAC-compressed as `.flac` (decision D3's one exception); both are
  /// resolved. Returns null when the task didn't bundle it.
  Future<String?> findReferenceAudio(String playableFilename) async {
    final base = await _baseDirectory;
    final dir = '${base.path}/task_audio';
    final candidates = [
      '$dir/$playableFilename',
      if (playableFilename.toLowerCase().endsWith('.wav'))
        '$dir/${playableFilename.substring(0, playableFilename.length - 4)}.flac',
    ];
    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }
    return null;
  }

  /// The filename a recording for [entry]'s writable [field] must have:
  /// `<SoundFile base minus .wav><suffix>.wav` (16-bit mono WAV, D3).
  /// Falls back to the app's reference+gloss naming when the record has no
  /// SoundFile base.
  String recordingFilenameFor(WordlistEntry entry, TaskField field) {
    final cellFiles = splitSoundFileCell(entry.soundFile ?? '');
    final base = cellFiles.isNotEmpty ? cellFiles.first : entry.recordingFilename;
    return suffixedSoundFile(base, field.suffix!);
  }

  /// Builds and writes the `.dekresult` archive; returns its path.
  ///
  /// Includes every collected value and recording, plus the consent log.
  /// The recordings' WAV bytes are read from the app's audio directory.
  Future<String> exportDekResult() async {
    final task = await getActiveTask();
    if (task == null) {
      throw StateError('No task is active');
    }
    final base = await _baseDirectory;

    final values = [
      for (final row in await _db.getAllTaskValues())
        ResultValue(
          dkSyncId: row['dk_sync_id'] as String,
          column: row['column_name'] as String,
          value: row['value'] as String,
        ),
    ];
    final recordings = <ResultRecording>[];
    final audio = <String, Uint8List>{};
    for (final row in await _db.getAllTaskRecordings()) {
      final filename = row['filename'] as String;
      final file = File('${base.path}/audio/$filename');
      if (!await file.exists()) {
        // A recording row without its WAV (e.g. cleared storage) must not
        // produce a result that fails validation on the researcher's side.
        continue;
      }
      recordings.add(ResultRecording(
        dkSyncId: row['dk_sync_id'] as String,
        column: row['column_name'] as String,
        filename: filename,
      ));
      audio[filename] = await file.readAsBytes();
    }

    final consentRecords = await _db.getAllConsentRecords();
    final result = DekResult(
      taskId: task.taskId,
      baseCheckpointId: task.baseCheckpointId,
      completedAt: DateTime.now().toIso8601String(),
      values: values,
      recordings: recordings,
      consentLog: [for (final r in consentRecords) r.toJson()],
    );
    final package = DekResultPackage(result: result, audio: audio);

    final problems = validateResult(task, package);
    if (problems.isNotEmpty) {
      throw StateError(
          'The collected data does not match the task:\n${problems.join('\n')}');
    }

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final path = '${base.path}/task_result_$timestamp.dekresult';
    final buildingPath = '$path.building';
    await File(buildingPath).writeAsBytes(encodeDekResult(package));
    await _deleteOldResults(base, except: buildingPath);
    await File(buildingPath).rename(path);
    return path;
  }

  Future<void> _deleteOldResults(Directory directory,
      {String? except}) async {
    await for (final file in directory.list()) {
      if (file is File && file.path != except) {
        final name = file.uri.pathSegments.last;
        if (name.startsWith('task_result_') &&
            (name.endsWith('.dekresult') ||
                name.endsWith('.dekresult.building'))) {
          await file.delete();
        }
      }
    }
  }

  static String? _emptyToNull(String? value) =>
      (value == null || value.isEmpty) ? null : value;
}
