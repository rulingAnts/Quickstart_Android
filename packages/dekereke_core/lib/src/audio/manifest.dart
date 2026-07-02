/// Audio manifest (plan §4.4).
///
/// The repo never stores audio blobs — it stores `audio-manifest.json`
/// mapping `filename → {sha256, bytes}`; blobs live in R2, content-addressed
/// by hash (immune to the spaces/parens real filenames contain). The
/// manifest's history IS the audio folder's history, and the first manifest
/// build doubles as a dedupe report across Seth's divergent folder copies.
///
/// Merge semantics mirror the record merge: one-sided changes win,
/// same-file re-records on both sides conflict (policy: keep both, rename
/// the incoming one visibly), removals are never implicit.
library;

import 'dart:convert';

import 'package:collection/collection.dart';

import '../merge/merge.dart' show MergeSide;

/// Content identity of one audio file.
final class AudioFileStat {
  /// Lowercase hex SHA-256 of the file bytes (the R2 storage key).
  final String sha256;
  final int bytes;

  const AudioFileStat({required this.sha256, required this.bytes});

  Map<String, Object> toJson() => {'sha256': sha256, 'bytes': bytes};

  factory AudioFileStat.fromJson(Map<String, Object?> json) => AudioFileStat(
        sha256: json['sha256'] as String,
        bytes: json['bytes'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is AudioFileStat && other.sha256 == sha256 && other.bytes == bytes;

  @override
  int get hashCode => Object.hash(sha256, bytes);

  @override
  String toString() => 'AudioFileStat($sha256, $bytes bytes)';
}

/// `audio-manifest.json`: filename → content identity.
final class AudioManifest {
  static const format = 'deksync-audio-manifest';
  static const version = 1;

  final Map<String, AudioFileStat> files;

  const AudioManifest(this.files);

  const AudioManifest.empty() : files = const {};

  /// Deterministic JSON: filenames sorted (code-unit order), 2-space
  /// indent — identical folders always produce identical bytes, so the
  /// manifest diffs cleanly and change-gates on content.
  String toJson() {
    final sorted = files.keys.toList()..sort();
    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': version,
      'files': {for (final name in sorted) name: files[name]!.toJson()},
    });
  }

  factory AudioManifest.fromJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('Audio manifest is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?> || decoded['format'] != format) {
      throw const FormatException('Not a $format file');
    }
    final fileVersion = decoded['version'];
    if (fileVersion is! int || fileVersion > version) {
      throw FormatException(
          'Audio manifest version $fileVersion is newer than supported '
          '($version) — update the app');
    }
    final files = decoded['files'];
    if (files is! Map<String, Object?>) {
      throw const FormatException('Audio manifest has no files map');
    }
    return AudioManifest({
      for (final entry in files.entries)
        entry.key:
            AudioFileStat.fromJson(entry.value as Map<String, Object?>),
    });
  }

  /// Filenames grouped by content hash with more than one name — the
  /// dedupe report (plan: the first manifest build doubles as one).
  Map<String, List<String>> duplicateGroups() {
    final byHash = <String, List<String>>{};
    for (final entry in files.entries) {
      byHash.putIfAbsent(entry.value.sha256, () => []).add(entry.key);
    }
    return {
      for (final e in byHash.entries)
        if (e.value.length > 1) e.key: (e.value..sort()),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is AudioManifest &&
      const MapEquality<String, AudioFileStat>().equals(other.files, files);

  @override
  int get hashCode => const MapEquality<String, AudioFileStat>().hash(files);
}

/// What changed between two manifests (sorted filename lists).
final class ManifestDiff {
  final List<String> added;
  final List<String> removed;
  final List<String> changed;

  const ManifestDiff({
    required this.added,
    required this.removed,
    required this.changed,
  });

  bool get isEmpty => added.isEmpty && removed.isEmpty && changed.isEmpty;
}

ManifestDiff diffManifests(AudioManifest from, AudioManifest to) {
  final added = <String>[];
  final removed = <String>[];
  final changed = <String>[];
  for (final name in to.files.keys) {
    final before = from.files[name];
    if (before == null) {
      added.add(name);
    } else if (before != to.files[name]) {
      changed.add(name);
    }
  }
  for (final name in from.files.keys) {
    if (!to.files.containsKey(name)) removed.add(name);
  }
  return ManifestDiff(
      added: added..sort(), removed: removed..sort(), changed: changed..sort());
}

/// Same filename re-recorded (different content) on both sides.
final class AudioConflict {
  final String filename;
  final AudioFileStat? baseStat;
  final AudioFileStat ourStat;
  final AudioFileStat theirStat;

  const AudioConflict({
    required this.filename,
    required this.baseStat,
    required this.ourStat,
    required this.theirStat,
  });
}

/// A file removed on one side (or both) — awaiting explicit confirmation.
final class PendingAudioRemoval {
  final String filename;
  final MergeSide removedBy;

  /// The surviving content (base content when both removed).
  final AudioFileStat stat;

  /// The surviving side re-recorded it since base: remove-vs-re-record.
  final bool modifiedBySurvivingSide;

  const PendingAudioRemoval({
    required this.filename,
    required this.removedBy,
    required this.stat,
    this.modifiedBySurvivingSide = false,
  });
}

/// Result of [mergeManifests].
final class AudioMergeResult {
  /// Merged manifest. Conflicted filenames provisionally hold OUR stat
  /// (resolve with [resolveKeepBoth] per the plan's policy); files under a
  /// one-sided pending removal are still included.
  final AudioManifest merged;

  final List<AudioConflict> conflicts;
  final List<PendingAudioRemoval> pendingRemovals;

  final List<String> addedByOurs;
  final List<String> addedByTheirs;

  const AudioMergeResult({
    required this.merged,
    required this.conflicts,
    required this.pendingRemovals,
    required this.addedByOurs,
    required this.addedByTheirs,
  });

  bool get isClean => conflicts.isEmpty && pendingRemovals.isEmpty;
}

/// Three-way manifest merge, mirroring the record merge's semantics.
AudioMergeResult mergeManifests({
  required AudioManifest base,
  required AudioManifest ours,
  required AudioManifest theirs,
}) {
  final merged = <String, AudioFileStat>{};
  final conflicts = <AudioConflict>[];
  final pendingRemovals = <PendingAudioRemoval>[];
  final addedByOurs = <String>[];
  final addedByTheirs = <String>[];

  final names = <String>{
    ...ours.files.keys,
    ...theirs.files.keys,
    ...base.files.keys,
  }.toList()
    ..sort();

  for (final name in names) {
    final b = base.files[name];
    final o = ours.files[name];
    final t = theirs.files[name];

    if (o != null && t != null) {
      if (o == t) {
        merged[name] = o;
        if (b == null) {
          addedByOurs.add(name);
          addedByTheirs.add(name);
        }
      } else if (b == o) {
        merged[name] = t; // theirs re-recorded
      } else if (b == t) {
        merged[name] = o; // ours re-recorded
      } else {
        merged[name] = o;
        conflicts.add(AudioConflict(
            filename: name, baseStat: b, ourStat: o, theirStat: t));
      }
    } else if (o != null) {
      merged[name] = o;
      if (b == null) {
        addedByOurs.add(name);
      } else {
        pendingRemovals.add(PendingAudioRemoval(
          filename: name,
          removedBy: MergeSide.theirs,
          stat: o,
          modifiedBySurvivingSide: b != o,
        ));
      }
    } else if (t != null) {
      merged[name] = t;
      if (b == null) {
        addedByTheirs.add(name);
      } else {
        pendingRemovals.add(PendingAudioRemoval(
          filename: name,
          removedBy: MergeSide.ours,
          stat: t,
          modifiedBySurvivingSide: b != t,
        ));
      }
    } else {
      // In base only: removed on both sides — agreed, reported, not merged.
      pendingRemovals.add(PendingAudioRemoval(
        filename: name,
        removedBy: MergeSide.both,
        stat: b!,
      ));
    }
  }

  return AudioMergeResult(
    merged: AudioManifest(merged),
    conflicts: conflicts,
    pendingRemovals: pendingRemovals,
    addedByOurs: addedByOurs,
    addedByTheirs: addedByTheirs,
  );
}

/// Applies the plan's re-record conflict policy: OUR file keeps the
/// original name, THEIR content enters under [incomingName] (visibly
/// renamed by the caller, e.g. `0002_water (from Chris).wav`).
///
/// Throws [ArgumentError] if [incomingName] is already taken by different
/// content.
AudioManifest resolveKeepBoth(
    AudioManifest manifest, AudioConflict conflict, String incomingName) {
  final existing = manifest.files[incomingName];
  if (existing != null && existing != conflict.theirStat) {
    throw ArgumentError.value(incomingName, 'incomingName',
        'already present with different content');
  }
  return AudioManifest({
    ...manifest.files,
    conflict.filename: conflict.ourStat,
    incomingName: conflict.theirStat,
  });
}

/// Removes files whose one-sided pending removal the user confirmed.
AudioManifest applyConfirmedRemovals(
        AudioManifest manifest, Set<String> confirmedFilenames) =>
    AudioManifest({
      for (final entry in manifest.files.entries)
        if (!confirmedFilenames.contains(entry.key)) entry.key: entry.value,
    });
