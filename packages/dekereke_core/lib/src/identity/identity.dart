/// Record identity (plan §4.2).
///
/// `<Reference>` cannot be a key (duplicates and blanks are legal and occur
/// in real databases), so identity lives OUTSIDE the XML in a synced sidecar
/// map `DkSyncID → fingerprint` that Dekereke never sees. At every watched
/// save the map is *re-bound* to the file's records down a ladder of
/// independent signals; IDs are restored, never re-minted, whenever any
/// signal matches.
library;

import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';

import '../codec/db_codec.dart';
import '../model/database.dart';

/// Multi-signal fingerprint of one record at one point in time.
final class RecordFingerprint {
  /// SHA-256 (hex) of the record's canonical rendering — the strongest
  /// signal: matches iff nothing in the record changed.
  final String contentHash;

  /// The raw `<SoundFile>` cell; survives edits to any other field and is
  /// the natural anchor for audio-bearing records. Empty when absent.
  final String soundFile;

  final String reference;
  final String gloss;

  /// Index among the file's records when the fingerprint was taken.
  final int position;

  const RecordFingerprint({
    required this.contentHash,
    required this.soundFile,
    required this.reference,
    required this.gloss,
    required this.position,
  });

  factory RecordFingerprint.of(DekerekeRecord record, int position) =>
      RecordFingerprint(
        contentHash: recordContentHash(record),
        soundFile: record.soundFileCell,
        reference: record.reference,
        gloss: record.gloss,
        position: position,
      );

  Map<String, Object> toJson() => {
        'contentHash': contentHash,
        'soundFile': soundFile,
        'reference': reference,
        'gloss': gloss,
        'position': position,
      };

  factory RecordFingerprint.fromJson(Map<String, Object?> json) =>
      RecordFingerprint(
        contentHash: json['contentHash'] as String,
        soundFile: json['soundFile'] as String? ?? '',
        reference: json['reference'] as String? ?? '',
        gloss: json['gloss'] as String? ?? '',
        position: json['position'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is RecordFingerprint &&
      other.contentHash == contentHash &&
      other.soundFile == soundFile &&
      other.reference == reference &&
      other.gloss == gloss &&
      other.position == position;

  @override
  int get hashCode =>
      Object.hash(contentHash, soundFile, reference, gloss, position);
}

/// SHA-256 hex of the record's canonical rendering (`renderRecordCanonical`
/// — the same bytes history stores, so identical content always hashes
/// identically across machines).
String recordContentHash(DekerekeRecord record) =>
    sha256.convert(utf8.encode(renderRecordCanonical(record))).toString();

/// One `DkSyncID → fingerprint` binding.
final class IdentityEntry {
  final String id;
  final RecordFingerprint fingerprint;

  const IdentityEntry(this.id, this.fingerprint);

  Map<String, Object> toJson() => {'id': id, ...fingerprint.toJson()};

  factory IdentityEntry.fromJson(Map<String, Object?> json) =>
      IdentityEntry(json['id'] as String, RecordFingerprint.fromJson(json));

  @override
  bool operator ==(Object other) =>
      other is IdentityEntry &&
      other.id == id &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(id, fingerprint);
}

/// The sidecar identity map (`.deksync/identity.json`), versioned and
/// synced like everything else. Dekereke never reads or writes it; nothing
/// done in its UI can damage it.
final class IdentityMap {
  static const format = 'deksync-identity';
  static const version = 1;

  /// Entries in record (position) order.
  final List<IdentityEntry> entries;

  const IdentityMap(this.entries);

  const IdentityMap.empty() : entries = const [];

  IdentityEntry? byId(String id) =>
      entries.firstWhereOrNull((e) => e.id == id);

  /// Deterministic JSON (2-space indent, entries in position order) so the
  /// synced file diffs cleanly and hashes stably.
  String toJson() => const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': version,
        'records': [for (final entry in entries) entry.toJson()],
      });

  factory IdentityMap.fromJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('Identity map is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?> || decoded['format'] != format) {
      throw const FormatException('Not a $format file');
    }
    final fileVersion = decoded['version'];
    if (fileVersion is! int || fileVersion > version) {
      throw FormatException(
          'Identity map version $fileVersion is newer than supported '
          '($version) — update the app');
    }
    final records = decoded['records'];
    if (records is! List) {
      throw const FormatException('Identity map has no records list');
    }
    return IdentityMap([
      for (final record in records)
        IdentityEntry.fromJson(record as Map<String, Object?>),
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is IdentityMap &&
      const ListEquality<IdentityEntry>().equals(other.entries, entries);

  @override
  int get hashCode => const ListEquality<IdentityEntry>().hash(entries);
}

/// How a record's ID was restored (ladder rung), or that it is new.
enum MatchRung {
  /// Exact content hash — nothing changed (covers ~99% of records each save).
  contentHash,

  /// Same `<SoundFile>` cell — fields edited, audio anchor intact.
  soundFile,

  /// Same Reference + Gloss — audio anchor changed too.
  referenceGloss,

  /// Same file position — everything else changed; low confidence, so
  /// [BoundRecord.needsReview] is set for a plain-language repair prompt.
  position,

  /// No signal matched: a genuinely new record with a freshly minted ID.
  minted,
}

/// One record of the new save, bound to its DkSyncID.
final class BoundRecord {
  final String id;

  /// Index of the record in the reconciled database.
  final int position;

  final MatchRung rung;

  /// Set when this record's content duplicates another record that kept an
  /// existing ID — the copy in a duplicated-row situation.
  final String? nearDuplicateOfId;

  /// True for low-confidence bindings (currently: the position rung) that
  /// the Companion should surface as a plain-language repair prompt.
  final bool needsReview;

  const BoundRecord({
    required this.id,
    required this.position,
    required this.rung,
    this.nearDuplicateOfId,
    this.needsReview = false,
  });
}

/// Result of re-binding an [IdentityMap] to a freshly saved database.
final class ReconcileResult {
  /// The new authoritative map: every current record, bound or minted, with
  /// refreshed fingerprints, in record order. Vanished entries are NOT in
  /// it — they are reported in [vanished] instead.
  final IdentityMap updated;

  /// One entry per record of the new save, in record order.
  final List<BoundRecord> records;

  /// Entries whose record no longer exists. Deletions are never implicit:
  /// these become explicit, user-confirmed deletions at sync time
  /// (plan §4.2b); until confirmed they simply stay out of the map.
  final List<IdentityEntry> vanished;

  const ReconcileResult({
    required this.updated,
    required this.records,
    required this.vanished,
  });

  List<BoundRecord> get minted =>
      records.where((r) => r.rung == MatchRung.minted).toList();

  List<BoundRecord> get needingReview =>
      records.where((r) => r.needsReview).toList();
}

final _random = Random.secure();

/// Mints a fresh DkSyncID: 32 lowercase hex characters (128 random bits).
String mintDkSyncId() {
  final buffer = StringBuffer();
  for (var i = 0; i < 8; i++) {
    buffer.write(_random.nextInt(0x10000).toRadixString(16).padLeft(4, '0'));
  }
  return buffer.toString();
}

/// Re-binds [previous] to [records] down the ladder (plan §4.2):
/// content hash → SoundFile → Reference+Gloss → position. IDs are restored
/// whenever any signal matches; unmatched records get fresh IDs from
/// [mintId]; unmatched previous entries are reported as [ReconcileResult.vanished].
///
/// Deterministic: within a rung, candidates pairing on the same signal value
/// are zipped in position order (so in a duplicated-row situation the copy
/// closest to the original's old position keeps the ID and the other copy is
/// minted fresh and flagged [BoundRecord.nearDuplicateOfId]).
ReconcileResult reconcileIdentity(
  IdentityMap previous,
  List<DekerekeRecord> records, {
  String Function() mintId = mintDkSyncId,
}) {
  final fingerprints = [
    for (var i = 0; i < records.length; i++) RecordFingerprint.of(records[i], i),
  ];

  // recordIndex -> (entry, rung); filled rung by rung.
  final bindings = <int, (IdentityEntry, MatchRung)>{};
  var unmatchedOld = List.of(previous.entries);

  void runRung(MatchRung rung, String? Function(RecordFingerprint) signal) {
    // Group unmatched old entries by signal value.
    final oldBySignal = <String, List<IdentityEntry>>{};
    for (final entry in unmatchedOld) {
      final value = signal(entry.fingerprint);
      if (value != null) oldBySignal.putIfAbsent(value, () => []).add(entry);
    }
    // Old entries with the same signal, in stored-position order.
    for (final group in oldBySignal.values) {
      group.sortBy<num>((e) => e.fingerprint.position);
    }
    final consumed = <IdentityEntry>{};
    for (var i = 0; i < fingerprints.length; i++) {
      if (bindings.containsKey(i)) continue;
      final value = signal(fingerprints[i]);
      if (value == null) continue;
      final candidates = oldBySignal[value];
      if (candidates == null || candidates.isEmpty) continue;
      final entry = candidates.removeAt(0);
      consumed.add(entry);
      bindings[i] = (entry, rung);
    }
    unmatchedOld = unmatchedOld.where((e) => !consumed.contains(e)).toList();
  }

  runRung(MatchRung.contentHash, (f) => f.contentHash);
  runRung(MatchRung.soundFile, (f) => f.soundFile.isEmpty ? null : f.soundFile);
  runRung(
      MatchRung.referenceGloss,
      (f) => (f.reference.isEmpty && f.gloss.isEmpty)
          ? null
          : '${f.reference} ${f.gloss}');
  runRung(MatchRung.position, (f) => f.position.toString());

  // Content hashes of records that kept an existing ID — used to flag
  // minted records that are near-duplicates of surviving ones.
  final boundHashes = <String, String>{}; // contentHash -> bound id
  bindings.forEach((index, binding) {
    boundHashes.putIfAbsent(fingerprints[index].contentHash, () => binding.$1.id);
  });

  final bound = <BoundRecord>[];
  final updatedEntries = <IdentityEntry>[];
  for (var i = 0; i < fingerprints.length; i++) {
    final fingerprint = fingerprints[i];
    final binding = bindings[i];
    if (binding != null) {
      final (entry, rung) = binding;
      bound.add(BoundRecord(
        id: entry.id,
        position: i,
        rung: rung,
        needsReview: rung == MatchRung.position,
      ));
      updatedEntries.add(IdentityEntry(entry.id, fingerprint));
    } else {
      final id = mintId();
      bound.add(BoundRecord(
        id: id,
        position: i,
        rung: MatchRung.minted,
        nearDuplicateOfId: boundHashes[fingerprint.contentHash],
      ));
      updatedEntries.add(IdentityEntry(id, fingerprint));
    }
  }

  return ReconcileResult(
    updated: IdentityMap(updatedEntries),
    records: bound,
    vanished: unmatchedOld,
  );
}
