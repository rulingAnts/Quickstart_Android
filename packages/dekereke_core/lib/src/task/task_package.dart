/// Task package formats: `.dektask` and `.dekresult` (plan §5.2).
///
/// A `.dektask` ZIP carries a delegated elicitation job to a phone:
/// `task.json` (task id, base checkpoint, field configuration, suffix
/// assignments, consent config, and the DkSyncID map — IDs travel HERE,
/// never inside the wordlist XML), `wordlist.xml` (the subset database in
/// canonical UTF-8, which the phone parser already accepts), `audio/` for
/// playable reference recordings and optional `pictures/`.
///
/// A `.dekresult` ZIP carries the collected answers back: `result.json`
/// (values + recordings keyed by DkSyncID and column, consent log) plus the
/// new recordings, already named `<base><suffix>.wav`.
///
/// Spec: `doc/task_packages.md`. Everything is deterministic: encoding the
/// same package twice yields identical bytes.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';

import '../codec/db_codec.dart';
import '../consent/consent.dart';
import '../merge/merge.dart' show IdentifiedRecord;
import '../model/database.dart';

/// How a column appears on the phone (plan §5.1).
enum TaskFieldRole { visible, playable, writable }

/// What a writable column collects.
enum TaskInputKind { text, audio, both }

final class TaskField {
  final String column;
  final TaskFieldRole role;

  /// Required for writable fields; null otherwise.
  final TaskInputKind? input;

  /// The sound-file suffix for playable columns and audio-collecting
  /// writable columns (e.g. new column `Yohanis` → `-yoh`).
  final String? suffix;

  const TaskField({
    required this.column,
    required this.role,
    this.input,
    this.suffix,
  }) : assert(role != TaskFieldRole.writable || input != null,
            'writable fields must declare an input kind');

  bool get collectsAudio =>
      role == TaskFieldRole.writable &&
      (input == TaskInputKind.audio || input == TaskInputKind.both);

  Map<String, Object> toJson() => {
        'column': column,
        'role': role.name,
        if (input != null) 'input': input!.name,
        if (suffix != null) 'suffix': suffix!,
      };

  factory TaskField.fromJson(Map<String, Object?> json) {
    final role = TaskFieldRole.values.asNameMap()[json['role']];
    if (role == null) {
      throw FormatException('Unknown task field role: ${json['role']}');
    }
    final inputName = json['input'];
    final input =
        inputName == null ? null : TaskInputKind.values.asNameMap()[inputName];
    if (inputName != null && input == null) {
      throw FormatException('Unknown task input kind: $inputName');
    }
    if (role == TaskFieldRole.writable && input == null) {
      throw FormatException(
          'Writable field "${json['column']}" is missing its input kind');
    }
    return TaskField(
      column: json['column'] as String,
      role: role,
      input: input,
      suffix: json['suffix'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TaskField &&
      other.column == column &&
      other.role == role &&
      other.input == input &&
      other.suffix == suffix;

  @override
  int get hashCode => Object.hash(column, role, input, suffix);
}

/// One row of the task's ID map: pairs the Nth record of `wordlist.xml`
/// (by position) with its DkSyncID; Reference rides along as the display
/// label only.
final class TaskRecordRef {
  final String dkSyncId;
  final String reference;

  const TaskRecordRef({required this.dkSyncId, required this.reference});

  Map<String, Object> toJson() => {'id': dkSyncId, 'reference': reference};

  factory TaskRecordRef.fromJson(Map<String, Object?> json) => TaskRecordRef(
        dkSyncId: json['id'] as String,
        reference: json['reference'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is TaskRecordRef &&
      other.dkSyncId == dkSyncId &&
      other.reference == reference;

  @override
  int get hashCode => Object.hash(dkSyncId, reference);
}

/// `task.json`.
final class DekTask {
  static const format = 'dektask';
  static const formatVersion = 1;

  final String taskId;
  final String title;

  /// Checkpoint the subset was cut from — merge-back is 3-way against it.
  final String baseCheckpointId;

  /// ISO-8601; supplied by the caller (this library computes no clocks).
  final String createdAt;

  final List<TaskField> fields;

  /// ID map, aligned by position with the records of `wordlist.xml`.
  final List<TaskRecordRef> records;

  /// Consent configuration, round-tripped verbatim (the phone app's
  /// existing consent flow interprets it).
  final Map<String, Object?> consent;

  const DekTask({
    required this.taskId,
    required this.title,
    required this.baseCheckpointId,
    required this.createdAt,
    required this.fields,
    required this.records,
    this.consent = const {},
  });

  List<TaskField> get writableFields =>
      fields.where((f) => f.role == TaskFieldRole.writable).toList();

  TaskField? fieldFor(String column) =>
      fields.firstWhereOrNull((f) => f.column == column);

  /// The consent block, schema'd (decision D11). Legacy free-form blocks
  /// parse as a disabled config with everything preserved in `extra`.
  ConsentConfig get consentConfig => ConsentConfig.fromJson(consent);

  String toJson() => const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': formatVersion,
        'taskId': taskId,
        'title': title,
        'baseCheckpointId': baseCheckpointId,
        'createdAt': createdAt,
        'fields': [for (final f in fields) f.toJson()],
        'records': [for (final r in records) r.toJson()],
        'consent': consent,
      });

  factory DekTask.fromJson(String source) {
    final json = _decodeEnvelope(source, format, formatVersion, 'task.json');
    return DekTask(
      taskId: json['taskId'] as String,
      title: json['title'] as String? ?? '',
      baseCheckpointId: json['baseCheckpointId'] as String,
      createdAt: json['createdAt'] as String? ?? '',
      fields: [
        for (final f in json['fields'] as List<Object?>)
          TaskField.fromJson(f as Map<String, Object?>)
      ],
      records: [
        for (final r in json['records'] as List<Object?>)
          TaskRecordRef.fromJson(r as Map<String, Object?>)
      ],
      consent: (json['consent'] as Map<String, Object?>?) ?? const {},
    );
  }
}

/// A full `.dektask` in memory.
final class DekTaskPackage {
  final DekTask task;

  /// The subset database (stored as canonical UTF-8 `wordlist.xml`).
  final DekerekeDatabase wordlist;

  /// Playable reference audio, keyed by bare filename.
  final Map<String, Uint8List> audio;

  /// Optional picture prompts, keyed by bare filename.
  final Map<String, Uint8List> pictures;

  /// Consent assets (`consent/` member): the researcher-recorded prompt
  /// and continuation audio the [DekTask.consentConfig] references.
  final Map<String, Uint8List> consentFiles;

  DekTaskPackage({
    required this.task,
    required this.wordlist,
    this.audio = const {},
    this.pictures = const {},
    this.consentFiles = const {},
  }) {
    if (task.records.length != wordlist.records.length) {
      throw ArgumentError(
          'ID map (${task.records.length}) and wordlist '
          '(${wordlist.records.length} records) must align');
    }
    final config = task.consentConfig;
    if (config.enabled) {
      final problems = config.validate();
      for (final file in [config.audioFile, config.continuationAudioFile]) {
        if (file != null && file.isNotEmpty && !consentFiles.containsKey(file)) {
          problems.add('Consent recording "$file" is referenced but not '
              'bundled.');
        }
      }
      if (problems.isNotEmpty) {
        throw FormatException(
            'The task\'s consent setup is incomplete:\n${problems.join('\n')}');
      }
    }
  }

  /// The wordlist records paired with their DkSyncIDs — ready to be the
  /// `base` of the merge-back (plan §5.3).
  List<IdentifiedRecord> identifiedRecords() => [
        for (final (i, record) in wordlist.records.indexed)
          IdentifiedRecord(task.records[i].dkSyncId, record),
      ];
}

/// Encodes a `.dektask` ZIP (deterministic bytes).
Uint8List encodeDekTask(DekTaskPackage package) {
  final archive = Archive();
  _addZipFile(archive, 'task.json', utf8.encode(package.task.toJson()));
  _addZipFile(archive, 'wordlist.xml', encodeCanonicalFile(package.wordlist));
  _addFileMap(archive, 'audio', package.audio);
  _addFileMap(archive, 'pictures', package.pictures);
  _addFileMap(archive, 'consent', package.consentFiles);
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

/// Decodes and validates a `.dektask` ZIP.
DekTaskPackage decodeDekTask(Uint8List bytes) {
  final entries = _readZip(bytes, kind: '.dektask');
  final taskJson = entries['task.json'];
  if (taskJson == null) {
    throw const FormatException('Not a .dektask: task.json is missing');
  }
  final wordlistXml = entries['wordlist.xml'];
  if (wordlistXml == null) {
    throw const FormatException('Not a .dektask: wordlist.xml is missing');
  }
  return DekTaskPackage(
    task: DekTask.fromJson(utf8.decode(taskJson)),
    wordlist: parseDekerekeFile(wordlistXml),
    audio: _extractDir(entries, 'audio'),
    pictures: _extractDir(entries, 'pictures'),
    consentFiles: _extractDir(entries, 'consent'),
  );
}

/// One collected cell value. The consent stamp fields (D11) are optional
/// for back-compat; when the task configures consent they are required by
/// [validateResult]'s coverage check.
final class ResultValue {
  final String dkSyncId;
  final String column;
  final String value;
  final String? receiptId;
  final String? receiptSha256;
  final String? collectedAt;

  const ResultValue({
    required this.dkSyncId,
    required this.column,
    required this.value,
    this.receiptId,
    this.receiptSha256,
    this.collectedAt,
  });

  Map<String, Object> toJson() => {
        'id': dkSyncId,
        'column': column,
        'value': value,
        if (receiptId != null) 'receiptId': receiptId!,
        if (receiptSha256 != null) 'receiptSha256': receiptSha256!,
        if (collectedAt != null) 'collectedAt': collectedAt!,
      };

  factory ResultValue.fromJson(Map<String, Object?> json) => ResultValue(
        dkSyncId: json['id'] as String,
        column: json['column'] as String,
        value: json['value'] as String? ?? '',
        receiptId: json['receiptId'] as String?,
        receiptSha256: json['receiptSha256'] as String?,
        collectedAt: json['collectedAt'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is ResultValue &&
      other.dkSyncId == dkSyncId &&
      other.column == column &&
      other.value == value &&
      other.receiptId == receiptId &&
      other.receiptSha256 == receiptSha256 &&
      other.collectedAt == collectedAt;

  @override
  int get hashCode =>
      Object.hash(dkSyncId, column, value, receiptId, receiptSha256, collectedAt);
}

/// One new recording, already named `<base><suffix>.wav`. Consent stamp
/// fields as on [ResultValue].
final class ResultRecording {
  final String dkSyncId;
  final String column;
  final String filename;
  final String? receiptId;
  final String? receiptSha256;
  final String? collectedAt;

  const ResultRecording({
    required this.dkSyncId,
    required this.column,
    required this.filename,
    this.receiptId,
    this.receiptSha256,
    this.collectedAt,
  });

  Map<String, Object> toJson() => {
        'id': dkSyncId,
        'column': column,
        'filename': filename,
        if (receiptId != null) 'receiptId': receiptId!,
        if (receiptSha256 != null) 'receiptSha256': receiptSha256!,
        if (collectedAt != null) 'collectedAt': collectedAt!,
      };

  factory ResultRecording.fromJson(Map<String, Object?> json) =>
      ResultRecording(
        dkSyncId: json['id'] as String,
        column: json['column'] as String,
        filename: json['filename'] as String,
        receiptId: json['receiptId'] as String?,
        receiptSha256: json['receiptSha256'] as String?,
        collectedAt: json['collectedAt'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is ResultRecording &&
      other.dkSyncId == dkSyncId &&
      other.column == column &&
      other.filename == filename &&
      other.receiptId == receiptId &&
      other.receiptSha256 == receiptSha256 &&
      other.collectedAt == collectedAt;

  @override
  int get hashCode => Object.hash(
      dkSyncId, column, filename, receiptId, receiptSha256, collectedAt);
}

/// `result.json`.
final class DekResult {
  static const format = 'dekresult';
  static const formatVersion = 1;

  final String taskId;
  final String baseCheckpointId;

  /// ISO-8601; supplied by the caller.
  final String completedAt;

  final List<ResultValue> values;
  final List<ResultRecording> recordings;

  /// Consent log entries, round-tripped verbatim.
  final List<Object?> consentLog;

  const DekResult({
    required this.taskId,
    required this.baseCheckpointId,
    required this.completedAt,
    required this.values,
    required this.recordings,
    this.consentLog = const [],
  });

  String toJson() => const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': formatVersion,
        'taskId': taskId,
        'baseCheckpointId': baseCheckpointId,
        'completedAt': completedAt,
        'values': [for (final v in values) v.toJson()],
        'recordings': [for (final r in recordings) r.toJson()],
        'consentLog': consentLog,
      });

  factory DekResult.fromJson(String source) {
    final json = _decodeEnvelope(source, format, formatVersion, 'result.json');
    return DekResult(
      taskId: json['taskId'] as String,
      baseCheckpointId: json['baseCheckpointId'] as String,
      completedAt: json['completedAt'] as String? ?? '',
      values: [
        for (final v in json['values'] as List<Object?>)
          ResultValue.fromJson(v as Map<String, Object?>)
      ],
      recordings: [
        for (final r in json['recordings'] as List<Object?>)
          ResultRecording.fromJson(r as Map<String, Object?>)
      ],
      consentLog: (json['consentLog'] as List<Object?>?) ?? const [],
    );
  }
}

/// A full `.dekresult` in memory.
final class DekResultPackage {
  final DekResult result;

  /// New recordings, keyed by bare filename.
  final Map<String, Uint8List> audio;

  /// Consent receipts covering the collected items (D11).
  final List<ConsentReceipt> receipts;

  /// Consent audio (spoken assents, and the prompt audio for provenance),
  /// keyed by bare filename — stored under the `consent/` member.
  final Map<String, Uint8List> consentFiles;

  const DekResultPackage({
    required this.result,
    this.audio = const {},
    this.receipts = const [],
    this.consentFiles = const {},
  });
}

/// Encodes a `.dekresult` ZIP (deterministic bytes). Each receipt is
/// written twice: canonical JSON + advisory human-readable text.
Uint8List encodeDekResult(DekResultPackage package) {
  final archive = Archive();
  _addZipFile(archive, 'result.json', utf8.encode(package.result.toJson()));
  _addFileMap(archive, 'audio', package.audio);
  final consentMembers = <String, Uint8List>{...package.consentFiles};
  for (final receipt in package.receipts) {
    consentMembers[receiptJsonMemberName(receipt)] =
        Uint8List.fromList(utf8.encode(receipt.toJsonString()));
    consentMembers[receiptTextMemberName(receipt)] =
        Uint8List.fromList(utf8.encode(receipt.renderHumanText()));
  }
  _addFileMap(archive, 'consent', consentMembers);
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

/// Decodes a `.dekresult` ZIP. Receipts are parsed from
/// `consent/receipt-*.json` with their integrity hashes verified.
DekResultPackage decodeDekResult(Uint8List bytes) {
  final entries = _readZip(bytes, kind: '.dekresult');
  final resultJson = entries['result.json'];
  if (resultJson == null) {
    throw const FormatException('Not a .dekresult: result.json is missing');
  }
  final consentEntries = _extractDir(entries, 'consent');
  final receipts = <ConsentReceipt>[];
  final consentFiles = <String, Uint8List>{};
  for (final entry in consentEntries.entries) {
    if (RegExp(r'^receipt-.+\.json$').hasMatch(entry.key)) {
      receipts.add(ConsentReceipt.fromJson(utf8.decode(entry.value)));
    } else if (!entry.key.endsWith('.txt')) {
      consentFiles[entry.key] = entry.value;
    }
  }
  return DekResultPackage(
    result: DekResult.fromJson(utf8.decode(resultJson)),
    audio: _extractDir(entries, 'audio'),
    receipts: receipts,
    consentFiles: consentFiles,
  );
}

/// Checks a result against the task it answers. Returns plain-language
/// problem strings (empty = valid).
List<String> validateResult(DekTask task, DekResultPackage package) {
  final problems = <String>[];
  final result = package.result;
  if (result.taskId != task.taskId) {
    problems.add('This result answers a different task '
        '("${result.taskId}", expected "${task.taskId}")');
  }
  if (result.baseCheckpointId != task.baseCheckpointId) {
    problems.add('Base checkpoint mismatch: result has '
        '"${result.baseCheckpointId}", task has "${task.baseCheckpointId}"');
  }
  final knownIds = {for (final r in task.records) r.dkSyncId};
  final writable = {for (final f in task.writableFields) f.column: f};
  for (final value in result.values) {
    if (!knownIds.contains(value.dkSyncId)) {
      problems.add('Value for unknown record ${value.dkSyncId} '
          '(${value.column})');
    }
    if (!writable.containsKey(value.column)) {
      problems.add('Value for non-writable column "${value.column}"');
    }
  }
  for (final recording in result.recordings) {
    if (!knownIds.contains(recording.dkSyncId)) {
      problems.add('Recording for unknown record ${recording.dkSyncId} '
          '(${recording.filename})');
    }
    final field = writable[recording.column];
    if (field == null || !field.collectsAudio) {
      problems.add('Recording for column "${recording.column}" which does '
          'not collect audio');
    }
    if (!package.audio.containsKey(recording.filename)) {
      problems.add('Recording file "${recording.filename}" is listed but '
          'missing from the package');
    }
  }

  // Consent coverage (D11, design §2.2): applies only when the task
  // configures consent; consent-off tasks and pre-consent results are
  // exempt by design.
  final consentConfig = task.consentConfig;
  if (consentConfig.enabled) {
    for (final receipt in package.receipts) {
      if (receipt.taskId != null &&
          !receiptCoversTask(receipt,
              taskId: task.taskId, baseCheckpointId: task.baseCheckpointId)) {
        problems.add('Receipt ${receipt.id} covers a different task '
            '("${receipt.taskId}").');
      }
      final assentFile = (receipt.json['response']
          as Map<String, Object?>?)?['assentFile'] as String?;
      if (assentFile != null && !package.consentFiles.containsKey(assentFile)) {
        problems.add('Receipt ${receipt.id} references spoken assent '
            '"$assentFile", which is missing from the package.');
      }
    }
    problems.addAll(validateConsentCoverage(
      receipts: package.receipts,
      items: [
        for (final v in result.values)
          StampedItem(
            description: 'The answer for word ${v.dkSyncId} (${v.column})',
            receiptId: v.receiptId,
            receiptSha256: v.receiptSha256,
            collectedAtIso: v.collectedAt,
          ),
        for (final r in result.recordings)
          StampedItem(
            description: 'Recording "${r.filename}"',
            receiptId: r.receiptId,
            receiptSha256: r.receiptSha256,
            collectedAtIso: r.collectedAt,
          ),
      ],
    ));
  }
  return problems;
}

/// Applies a result's text values to the task's base records, producing the
/// "theirs" side for the 3-way merge-back (plan §5.3): only cells in
/// (task records × writable columns) can differ from base.
List<IdentifiedRecord> applyResultValues(
    List<IdentifiedRecord> baseRecords, DekResult result) {
  final byId = {for (final v in result.values) '${v.dkSyncId} ${v.column}': v};
  if (byId.length != result.values.length) {
    throw ArgumentError('Result contains duplicate values for one cell');
  }
  return [
    for (final identified in baseRecords)
      IdentifiedRecord(
        identified.id,
        result.values
            .where((v) => v.dkSyncId == identified.id)
            .fold(identified.record, (r, v) => r.withValue(v.column, v.value)),
      ),
  ];
}

// ---- ZIP plumbing -----------------------------------------------------------

void _addZipFile(Archive archive, String path, List<int> bytes) {
  final file = ArchiveFile(path, bytes.length, bytes)
    ..lastModTime = 0
    ..compress = true;
  archive.addFile(file);
}

void _addFileMap(Archive archive, String dir, Map<String, Uint8List> files) {
  final names = files.keys.toList()..sort();
  for (final name in names) {
    if (name.contains('/') || name.contains('\\')) {
      throw ArgumentError.value(name, 'files', 'must be a bare filename');
    }
    _addZipFile(archive, '$dir/$name', files[name]!);
  }
}

Map<String, Uint8List> _readZip(Uint8List bytes, {required String kind}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: true);
  } on Object {
    throw FormatException('Not a $kind: file is not a readable ZIP');
  }
  final entries = <String, Uint8List>{};
  for (final file in archive.files) {
    if (!file.isFile) continue;
    entries[file.name] = Uint8List.fromList(file.content as List<int>);
  }
  return entries;
}

Map<String, Uint8List> _extractDir(
        Map<String, Uint8List> entries, String dir) =>
    {
      for (final entry in entries.entries)
        if (entry.key.startsWith('$dir/') && entry.key.length > dir.length + 1)
          entry.key.substring(dir.length + 1): entry.value,
    };

Map<String, Object?> _decodeEnvelope(
    String source, String format, int maxVersion, String what) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (e) {
    throw FormatException('$what is not valid JSON: ${e.message}');
  }
  if (decoded is! Map<String, Object?> || decoded['format'] != format) {
    throw FormatException('$what is not a $format file');
  }
  final version = decoded['version'];
  if (version is! int || version > maxVersion) {
    throw FormatException(
        '$what version $version is newer than supported ($maxVersion) — '
        'update the app');
  }
  return decoded;
}
