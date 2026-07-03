/// Database health panel rules (plan §4.2): "Reference lint".
///
/// Audio naming leans on Reference even though identity does not, so the
/// Companion continuously flags the states Dekereke lets a database drift
/// into. Every finding carries plain-language rendering data; severities
/// let the UI sort real breakage above tidiness.
library;

import '../model/database.dart';
import '../model/sound_file.dart';
import '../settings/settings.dart';

enum HealthSeverity {
  /// Something will misbehave in Dekereke or sync (e.g. duplicate
  /// References make exports/updates ambiguous).
  problem,

  /// Worth fixing but nothing breaks today.
  warning,
}

enum HealthIssueKind {
  duplicateReference,
  emptyReference,
  soundFileReferenceMismatch,
  orphanedAudioFile,
  missingAudioFile,
  missingSuffixFile,
}

/// One finding, with everything a plain-language list row needs.
final class HealthIssue {
  final HealthIssueKind kind;
  final HealthSeverity severity;

  /// Positions (indexes into the record list) of the records involved;
  /// empty for folder-level findings like orphaned files.
  final List<int> recordPositions;

  /// Reference label(s) for display (may be empty/duplicated — that can be
  /// exactly the finding).
  final String reference;

  /// Filename involved, when the finding is about audio.
  final String? filename;

  /// Plain-language, user-facing sentence.
  final String message;

  const HealthIssue({
    required this.kind,
    required this.severity,
    required this.recordPositions,
    required this.reference,
    this.filename,
    required this.message,
  });

  @override
  String toString() => 'HealthIssue(${kind.name}: $message)';
}

/// Runs every rule against a database, the audio folder's filenames, and
/// (optionally) the settings' suffix mappings. Pure and deterministic:
/// findings come out in rule order, then record order.
///
/// [audioFilenames] is the flat list of files in the audio folder (bare
/// names); pass null when no folder is available (folder rules are
/// skipped). [settings] contributes the column→suffix mappings for the
/// missing-suffix-file rule; null skips it.
List<HealthIssue> checkDatabaseHealth(
  DekerekeDatabase db, {
  Iterable<String>? audioFilenames,
  DkUserSettings? settings,
}) {
  final records = db.records;
  final issues = <HealthIssue>[];

  // --- Duplicate References --------------------------------------------------
  final byReference = <String, List<int>>{};
  for (var i = 0; i < records.length; i++) {
    final ref = records[i].reference;
    if (ref.isNotEmpty) byReference.putIfAbsent(ref, () => []).add(i);
  }
  for (final entry in byReference.entries) {
    if (entry.value.length > 1) {
      final glosses =
          entry.value.map((i) => '"${records[i].gloss}"').join(', ');
      issues.add(HealthIssue(
        kind: HealthIssueKind.duplicateReference,
        severity: HealthSeverity.problem,
        recordPositions: entry.value,
        reference: entry.key,
        message: 'Reference ${entry.key} is used by ${entry.value.length} '
            'words ($glosses) — exports and updates cannot tell them apart.',
      ));
    }
  }

  // --- Empty References --------------------------------------------------------
  for (var i = 0; i < records.length; i++) {
    if (records[i].reference.isEmpty) {
      issues.add(HealthIssue(
        kind: HealthIssueKind.emptyReference,
        severity: HealthSeverity.problem,
        recordPositions: [i],
        reference: '',
        message: 'Word "${records[i].gloss}" has no reference number.',
      ));
    }
  }

  // --- SoundFile ↔ Reference mismatch -----------------------------------------
  // Convention: the base filename starts with the record's Reference.
  for (var i = 0; i < records.length; i++) {
    final record = records[i];
    if (record.reference.isEmpty) continue;
    for (final file in splitSoundFileCell(record.soundFileCell)) {
      if (!file.startsWith(record.reference)) {
        issues.add(HealthIssue(
          kind: HealthIssueKind.soundFileReferenceMismatch,
          severity: HealthSeverity.warning,
          recordPositions: [i],
          reference: record.reference,
          filename: file,
          message: 'Word ${record.reference} "${record.gloss}" points at '
              '"$file", which does not start with its reference number.',
        ));
      }
    }
  }

  if (audioFilenames != null) {
    final folder = audioFilenames.toSet();

    // Filenames the database accounts for: every SoundFile cell entry plus
    // its suffix variants (from settings when given).
    final suffixes = <String>[
      for (final mapping in settings?.suffixMappings ?? const <SuffixMapping>[])
        mapping.suffix,
    ];
    final accounted = <String>{};
    for (final record in records) {
      for (final file in splitSoundFileCell(record.soundFileCell)) {
        accounted.add(file);
        for (final suffix in suffixes) {
          accounted.add(suffixedSoundFile(file, suffix));
        }
      }
    }

    // --- Missing audio files (cell names a file that isn't there) -------------
    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      for (final file in splitSoundFileCell(record.soundFileCell)) {
        if (!folder.contains(file)) {
          issues.add(HealthIssue(
            kind: HealthIssueKind.missingAudioFile,
            severity: HealthSeverity.problem,
            recordPositions: [i],
            reference: record.reference,
            filename: file,
            message: 'Word ${record.reference.isEmpty ? '"${record.gloss}"' : record.reference} '
                'expects recording "$file", but the file is not in the '
                'audio folder.',
          ));
        }
      }
    }

    // --- Missing suffix files (mapped column, base exists, variant absent) ----
    if (suffixes.isNotEmpty) {
      for (var i = 0; i < records.length; i++) {
        final record = records[i];
        for (final file in splitSoundFileCell(record.soundFileCell)) {
          if (!folder.contains(file)) continue; // already reported above
          for (final mapping in settings!.suffixMappings) {
            final variant = suffixedSoundFile(file, mapping.suffix);
            final columnValue = record.valueOf(mapping.column);
            // Only expect the suffix file when the mapped column has data.
            if (columnValue != null &&
                columnValue.isNotEmpty &&
                !folder.contains(variant)) {
              issues.add(HealthIssue(
                kind: HealthIssueKind.missingSuffixFile,
                severity: HealthSeverity.warning,
                recordPositions: [i],
                reference: record.reference,
                filename: variant,
                message: 'Word ${record.reference} "${record.gloss}" has '
                    '${mapping.column} filled in, but its recording '
                    '"$variant" is not in the audio folder.',
              ));
            }
          }
        }
      }
    }

    // --- Orphaned audio files ---------------------------------------------------
    final orphans = folder.difference(accounted).toList()..sort();
    for (final file in orphans) {
      issues.add(HealthIssue(
        kind: HealthIssueKind.orphanedAudioFile,
        severity: HealthSeverity.warning,
        recordPositions: const [],
        reference: '',
        filename: file,
        message: 'Recording "$file" is in the audio folder but no word '
            'points at it.',
      ));
    }
  }

  return issues;
}
