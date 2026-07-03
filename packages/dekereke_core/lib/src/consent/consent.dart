/// Consent system core (decision D11; full design: docs/CONSENT_DESIGN.md).
///
/// FlexText's two-axis model — ask (text/audio) × confirm
/// (yesno/record/signature) — adapted so consent covers a SCOPE: one
/// ceremony per voice × per task, never per recording. Receipts are
/// tamper-evident (canonical-JSON content hash + per-device hash chain +
/// audio hashes + playback evidence) and every collected item stamps the
/// receipt that covered it.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Canonical JSON: recursively key-sorted maps, no whitespace — the byte
/// form receipts are hashed over. Deterministic across devices.
String canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) => switch (value) {
      Map<String, Object?>() => {
          for (final key in value.keys.toList()..sort())
            key: _canonicalize(value[key]),
        },
      List<Object?>() => [for (final item in value) _canonicalize(item)],
      _ => value,
    };

String sha256OfText(String text) =>
    sha256.convert(utf8.encode(text)).toString();

// ---- Configuration -----------------------------------------------------------

enum ConsentAskMode { text, audio }

enum ConsentConfirmMode { yesno, record, signature }

enum ContinuationPolicy { none, perDay, perSession }

enum SpeakerNameRequirement { off, optional, required }

/// The `consent` block of `task.json`, schema'd (unknown keys pass
/// through untouched for forward compatibility). An empty config (no ask,
/// no confirm) means the ceremony is skipped entirely.
final class ConsentConfig {
  final List<ConsentAskMode> ask;
  final List<ConsentConfirmMode> confirm;

  /// Written statement (required when [ask] contains text).
  final String message;

  /// `consent/` member name of the prompt recording (required when [ask]
  /// contains audio).
  final String? audioFile;

  /// Frozen scope wording — the researcher's precision tool (D11).
  final String scopeStatement;

  /// The in-app "someone new is speaking" button (D11; default enabled).
  final bool reconsentButton;

  /// Optional time-based prompts; default none (D11).
  final ContinuationPolicy continuation;
  final String? continuationMessage;
  final String? continuationAudioFile;

  final SpeakerNameRequirement speakerName;

  /// Unrecognized keys, preserved verbatim.
  final Map<String, Object?> extra;

  const ConsentConfig({
    this.ask = const [],
    this.confirm = const [],
    this.message = '',
    this.audioFile,
    this.scopeStatement = '',
    this.reconsentButton = true,
    this.continuation = ContinuationPolicy.none,
    this.continuationMessage,
    this.continuationAudioFile,
    this.speakerName = SpeakerNameRequirement.optional,
    this.extra = const {},
  });

  bool get enabled => ask.isNotEmpty || confirm.isNotEmpty;

  static const _knownKeys = {
    'ask',
    'confirm',
    'message',
    'audioFile',
    'scopeStatement',
    'reconsentButton',
    'continuation',
    'continuationMessage',
    'continuationAudioFile',
    'speakerName',
  };

  /// Tolerant parse: a legacy free-form map (none of our keys) becomes a
  /// disabled config carrying everything in [extra].
  factory ConsentConfig.fromJson(Map<String, Object?> json) {
    List<T> parseModes<T extends Enum>(Object? value, List<T> all) => [
          if (value is List)
            for (final name in value)
              if (all.asNameMap()[name] case final T mode?) mode,
        ];
    return ConsentConfig(
      ask: parseModes(json['ask'], ConsentAskMode.values),
      confirm: parseModes(json['confirm'], ConsentConfirmMode.values),
      message: json['message'] as String? ?? '',
      audioFile: json['audioFile'] as String?,
      scopeStatement: json['scopeStatement'] as String? ?? '',
      reconsentButton: json['reconsentButton'] as bool? ?? true,
      continuation: ContinuationPolicy.values
              .asNameMap()[json['continuation']] ??
          ContinuationPolicy.none,
      continuationMessage: json['continuationMessage'] as String?,
      continuationAudioFile: json['continuationAudioFile'] as String?,
      speakerName: SpeakerNameRequirement.values
              .asNameMap()[json['speakerName']] ??
          SpeakerNameRequirement.optional,
      extra: {
        for (final entry in json.entries)
          if (!_knownKeys.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  Map<String, Object?> toJson() => {
        if (ask.isNotEmpty) 'ask': [for (final m in ask) m.name],
        if (confirm.isNotEmpty) 'confirm': [for (final m in confirm) m.name],
        if (message.isNotEmpty) 'message': message,
        if (audioFile != null) 'audioFile': audioFile,
        if (scopeStatement.isNotEmpty) 'scopeStatement': scopeStatement,
        'reconsentButton': reconsentButton,
        if (continuation != ContinuationPolicy.none)
          'continuation': continuation.name,
        if (continuationMessage != null)
          'continuationMessage': continuationMessage,
        if (continuationAudioFile != null)
          'continuationAudioFile': continuationAudioFile,
        'speakerName': speakerName.name,
        ...extra,
      };

  /// Coherence problems, in plain language (empty = valid). Mirrors the
  /// FlexText rules plus the D11 additions.
  List<String> validate() {
    if (!enabled) return const [];
    final problems = <String>[];
    if (ask.isEmpty) {
      problems.add('Consent asks for a response but presents no statement '
          '(enable a text or audio ask).');
    }
    if (confirm.isEmpty) {
      problems.add('Consent presents a statement but captures no response '
          '(enable yes/no, recorded assent, or signature).');
    }
    if (ask.contains(ConsentAskMode.text) && message.trim().isEmpty) {
      problems.add('The text ask is enabled but no consent message is set.');
    }
    if (ask.contains(ConsentAskMode.audio) &&
        (audioFile == null || audioFile!.isEmpty)) {
      problems.add('The audio ask is enabled but no prompt recording is '
          'bundled.');
    }
    if (continuation != ContinuationPolicy.none) {
      if (ask.contains(ConsentAskMode.text) &&
          (continuationMessage == null || continuationMessage!.trim().isEmpty)) {
        problems.add('Repeat prompts are enabled but no short continuation '
            'message is set.');
      }
      if (ask.contains(ConsentAskMode.audio) &&
          (continuationAudioFile == null || continuationAudioFile!.isEmpty)) {
        problems.add('Repeat prompts are enabled but no short continuation '
            'recording is bundled.');
      }
    }
    return problems;
  }

  @override
  bool operator ==(Object other) =>
      other is ConsentConfig &&
      canonicalJson(other.toJson()) == canonicalJson(toJson());

  @override
  int get hashCode => canonicalJson(toJson()).hashCode;
}

// ---- Receipts ----------------------------------------------------------------

enum ConsentReceiptKind { ceremony, continuation, withdrawal }

/// One consent event, tamper-evident. The canonical JSON is the artifact;
/// this class wraps it with typed access. `contentSha256` = SHA-256 of the
/// canonical JSON with that field removed; stamped items carry
/// `receiptId + receiptSha256`, so a post-hoc edit orphans every stamp.
final class ConsentReceipt {
  static const format = 'deksync-consent-receipt';
  static const version = 1;

  final Map<String, Object?> json;

  ConsentReceipt._(this.json);

  /// Builds a receipt and seals it with its content hash. [timestampIso]
  /// etc. are caller-supplied (this library computes no clocks).
  factory ConsentReceipt.build({
    required String id,
    required ConsentReceiptKind kind,
    String? refersTo,
    String? refersToSha256,
    String? prevReceiptSha256,
    String? taskId,
    String? baseCheckpointId,
    String? wordlistFingerprint,
    String? wordlistDescription,
    required String scopeStatement,
    required List<ConsentAskMode> promptModes,
    required String promptMessage,
    String? promptAudioFile,
    String? promptAudioSha256,
    bool? playbackCompleted,
    int? playCount,
    required List<ConsentConfirmMode> responseTypes,
    String? signatureName,
    String? assentFile,
    String? assentSha256,
    String? speakerName,
    required String timestampIso,
    required String timestampLocal,
    required String timezone,
    required String deviceId,
    required String appVersion,
    required String platform,
  }) {
    final map = <String, Object?>{
      'format': format,
      'version': version,
      'id': id,
      'kind': kind.name,
      if (refersTo != null) 'refersTo': refersTo,
      if (refersToSha256 != null) 'refersToSha256': refersToSha256,
      if (prevReceiptSha256 != null) 'prevReceiptSha256': prevReceiptSha256,
      'scope': {
        if (taskId != null) 'taskId': taskId,
        if (baseCheckpointId != null) 'baseCheckpointId': baseCheckpointId,
        if (wordlistFingerprint != null)
          'wordlistFingerprint': wordlistFingerprint,
        if (wordlistDescription != null)
          'wordlistDescription': wordlistDescription,
        'statement': scopeStatement,
      },
      'prompt': {
        'modes': [for (final m in promptModes) m.name],
        'message': promptMessage,
        if (promptAudioFile != null) 'audioFile': promptAudioFile,
        if (promptAudioSha256 != null) 'audioSha256': promptAudioSha256,
        if (playbackCompleted != null)
          'playback': {
            'completed': playbackCompleted,
            if (playCount != null) 'playCount': playCount,
          },
      },
      'response': {
        'types': [for (final m in responseTypes) m.name],
        if (signatureName != null) 'signatureName': signatureName,
        if (assentFile != null) 'assentFile': assentFile,
        if (assentSha256 != null) 'assentSha256': assentSha256,
      },
      if (speakerName != null) 'speakerName': speakerName,
      'timestamp': {
        'iso': timestampIso,
        'local': timestampLocal,
        'timezone': timezone,
      },
      'device': {
        'deviceId': deviceId,
        'appVersion': appVersion,
        'platform': platform,
      },
      'context': {'ipAddress': 'unavailable', 'approxLocation': 'unavailable'},
    };
    map['contentSha256'] = sha256OfText(canonicalJson(map));
    return ConsentReceipt._(map);
  }

  /// Parses and structurally validates; [verifyHash] (default true) also
  /// checks the content hash — a mismatch means the receipt was edited.
  factory ConsentReceipt.fromJson(String source, {bool verifyHash = true}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('Consent receipt is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?> || decoded['format'] != format) {
      throw const FormatException('Not a $format file');
    }
    final fileVersion = decoded['version'];
    if (fileVersion is! int || fileVersion > version) {
      throw FormatException('Consent receipt version $fileVersion is newer '
          'than supported ($version) — update the app');
    }
    if (decoded['id'] is! String ||
        ConsentReceiptKind.values.asNameMap()[decoded['kind']] == null) {
      throw const FormatException('Consent receipt is missing id or kind');
    }
    final receipt = ConsentReceipt._(decoded);
    if (verifyHash && !receipt.verifyContentHash()) {
      throw FormatException(
          'Consent receipt ${receipt.id} failed its integrity check — the '
          'file does not match the hash it was sealed with.');
    }
    return receipt;
  }

  String get id => json['id'] as String;

  ConsentReceiptKind get kind =>
      ConsentReceiptKind.values.asNameMap()[json['kind']]!;

  String? get refersTo => json['refersTo'] as String?;
  String? get refersToSha256 => json['refersToSha256'] as String?;
  String? get prevReceiptSha256 => json['prevReceiptSha256'] as String?;
  String get contentSha256 => json['contentSha256'] as String? ?? '';

  Map<String, Object?> get _scope =>
      (json['scope'] as Map<String, Object?>?) ?? const {};
  String? get taskId => _scope['taskId'] as String?;
  String? get baseCheckpointId => _scope['baseCheckpointId'] as String?;
  String get scopeStatement => _scope['statement'] as String? ?? '';

  String? get speakerName => json['speakerName'] as String?;

  String get timestampIso =>
      ((json['timestamp'] as Map<String, Object?>?) ?? const {})['iso']
          as String? ??
      '';

  /// True when the JSON matches the hash it was sealed with.
  bool verifyContentHash() {
    final claimed = json['contentSha256'];
    if (claimed is! String) return false;
    final without = Map<String, Object?>.of(json)..remove('contentSha256');
    return sha256OfText(canonicalJson(without)) == claimed;
  }

  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(_canonicalize(json));

  /// Deterministic human rendering — advisory only; the JSON is canonical.
  String renderHumanText() {
    final buffer = StringBuffer()
      ..writeln('CONSENT RECEIPT (${kind.name})')
      ..writeln('Receipt id: $id')
      ..writeln('When: $timestampIso');
    if (speakerName != null) buffer.writeln('Speaker: $speakerName');
    if (refersTo != null) buffer.writeln('Refers to receipt: $refersTo');
    buffer
      ..writeln()
      ..writeln('What this covers:')
      ..writeln('  $scopeStatement');
    if (taskId != null) buffer.writeln('  Task: $taskId');
    final prompt = (json['prompt'] as Map<String, Object?>?) ?? const {};
    final message = prompt['message'] as String? ?? '';
    if (message.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('The statement presented:')
        ..writeln('  $message');
    }
    if (prompt['audioFile'] != null) {
      buffer.writeln('  (spoken statement: ${prompt['audioFile']}, '
          'sha256 ${prompt['audioSha256'] ?? 'unrecorded'})');
    }
    final response = (json['response'] as Map<String, Object?>?) ?? const {};
    buffer
      ..writeln()
      ..writeln('How agreement was given: '
          '${(response['types'] as List?)?.join(', ') ?? 'n/a'}');
    if (response['signatureName'] != null) {
      buffer.writeln('  Signed name: ${response['signatureName']}');
    }
    if (response['assentFile'] != null) {
      buffer.writeln('  Spoken assent: ${response['assentFile']} '
          '(sha256 ${response['assentSha256'] ?? 'unrecorded'})');
    }
    buffer
      ..writeln()
      ..writeln('---')
      ..writeln('Generated from receipt-$id.json (sha256 $contentSha256).')
      ..writeln('The JSON file is the authoritative record.');
    return buffer.toString();
  }
}

// ---- Bundle validation ---------------------------------------------------------

/// A stamped, collected item to check for coverage.
final class StampedItem {
  final String description; // plain-language, e.g. 'recording "x.wav"'
  final String? receiptId;
  final String? receiptSha256;
  final String? collectedAtIso;

  const StampedItem({
    required this.description,
    this.receiptId,
    this.receiptSha256,
    this.collectedAtIso,
  });
}

/// Checks a bundle of receipts + stamped items against the design's
/// "covering receipt" definition (CONSENT_DESIGN.md §2.2). Returns
/// plain-language problems; empty = covered. Chain `prev` links are
/// verified only between receipts present in the bundle (the full chain
/// lives on the device / in the archive).
List<String> validateConsentCoverage({
  required List<ConsentReceipt> receipts,
  required List<StampedItem> items,
}) {
  final problems = <String>[];
  final byId = <String, ConsentReceipt>{};

  for (final receipt in receipts) {
    if (!receipt.verifyContentHash()) {
      problems.add('Receipt ${receipt.id} failed its integrity check.');
      continue;
    }
    byId[receipt.id] = receipt;
  }

  // Referential links (continuation/withdrawal → ceremony).
  for (final receipt in byId.values) {
    if (receipt.kind == ConsentReceiptKind.ceremony) continue;
    final target = receipt.refersTo == null ? null : byId[receipt.refersTo];
    if (target == null) {
      problems.add('Receipt ${receipt.id} (${receipt.kind.name}) refers to '
          'a receipt that is not in this package.');
    } else {
      if (target.kind != ConsentReceiptKind.ceremony) {
        problems.add('Receipt ${receipt.id} (${receipt.kind.name}) must '
            'refer to a ceremony, not a ${target.kind.name}.');
      }
      if (receipt.refersToSha256 != null &&
          receipt.refersToSha256 != target.contentSha256) {
        problems.add('Receipt ${receipt.id} refers to ceremony '
            '${target.id}, but that ceremony\'s content has changed since.');
      }
    }
  }

  // Withdrawals, for the collected-before-withdrawal check.
  final withdrawalsByCeremony = <String, ConsentReceipt>{};
  for (final receipt in byId.values) {
    if (receipt.kind == ConsentReceiptKind.withdrawal &&
        receipt.refersTo != null) {
      withdrawalsByCeremony[receipt.refersTo!] = receipt;
    }
  }

  for (final item in items) {
    if (item.receiptId == null) {
      problems.add('${item.description} carries no consent stamp although '
          'consent is configured for this task.');
      continue;
    }
    final receipt = byId[item.receiptId];
    if (receipt == null) {
      problems.add('${item.description} is stamped with receipt '
          '${item.receiptId}, which is not in this package.');
      continue;
    }
    if (item.receiptSha256 != null &&
        item.receiptSha256 != receipt.contentSha256) {
      problems.add('${item.description} was stamped against a different '
          'version of receipt ${receipt.id} — the receipt has been altered '
          'since collection.');
      continue;
    }
    if (receipt.kind == ConsentReceiptKind.withdrawal) {
      problems.add('${item.description} is stamped with a WITHDRAWAL '
          'receipt (${receipt.id}) — a withdrawal never covers collection.');
      continue;
    }
    final ceremonyId = receipt.kind == ConsentReceiptKind.ceremony
        ? receipt.id
        : receipt.refersTo;
    final withdrawal =
        ceremonyId == null ? null : withdrawalsByCeremony[ceremonyId];
    if (withdrawal != null) {
      if (item.collectedAtIso == null) {
        problems.add('${item.description} was collected under consent that '
            'was later withdrawn, and carries no collection time — cannot '
            'verify it predates the withdrawal.');
      } else if (item.collectedAtIso!.compareTo(withdrawal.timestampIso) > 0) {
        problems.add('${item.description} was collected AFTER consent was '
            'withdrawn (${withdrawal.timestampIso}).');
      }
    }
  }

  // Prev-chain spot check within the bundle.
  final byHash = {
    for (final receipt in byId.values) receipt.contentSha256: receipt,
  };
  for (final receipt in byId.values) {
    final prev = receipt.prevReceiptSha256;
    if (prev != null && !byHash.containsKey(prev)) {
      // Not an error: the chain predecessor may live outside this bundle.
      continue;
    }
  }

  return problems;
}

/// Scope match between a receipt and a task result (design §2.2 rule 4).
bool receiptCoversTask(ConsentReceipt receipt,
        {required String taskId, required String baseCheckpointId}) =>
    receipt.taskId == taskId &&
    (receipt.baseCheckpointId == null ||
        receipt.baseCheckpointId == baseCheckpointId);

/// Groups receipts for export naming: `consent/receipt-<id>.json` + `.txt`.
String receiptJsonMemberName(ConsentReceipt receipt) =>
    'receipt-${receipt.id}.json';

String receiptTextMemberName(ConsentReceipt receipt) =>
    'receipt-${receipt.id}.txt';
