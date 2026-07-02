/// Per-collaborator Reference number blocks (decision D4).
///
/// Identity is DkSyncID (plan §4.2); Reference is only a human label —
/// but two machines must still never mint the same new label. Each
/// collaborator gets reserved number blocks; new-Reference labels
/// auto-assign from the local block. The allocation file is versioned and
/// synced like everything else (`.deksync/reference-blocks.json`), so a
/// block grant is visible to every machine before it can collide.
library;

import 'dart:convert';

import 'package:collection/collection.dart';

/// One reserved range of Reference numbers ([start]..[end], inclusive).
final class ReferenceBlock {
  /// The collaborator/install this block belongs to.
  final String ownerId;

  final int start;
  final int size;

  const ReferenceBlock({
    required this.ownerId,
    required this.start,
    required this.size,
  });

  int get end => start + size - 1;

  bool contains(int number) => number >= start && number <= end;

  Map<String, Object> toJson() =>
      {'owner': ownerId, 'start': start, 'size': size};

  factory ReferenceBlock.fromJson(Map<String, Object?> json) => ReferenceBlock(
        ownerId: json['owner'] as String,
        start: json['start'] as int,
        size: json['size'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is ReferenceBlock &&
      other.ownerId == ownerId &&
      other.start == start &&
      other.size == size;

  @override
  int get hashCode => Object.hash(ownerId, start, size);

  @override
  String toString() => 'ReferenceBlock($ownerId: $start..$end)';
}

/// The synced allocation state: every granted block, plus the label width.
final class ReferenceAllocation {
  static const format = 'deksync-reference-blocks';
  static const version = 1;

  /// Default block size — Companion-picked default per D4.
  static const defaultBlockSize = 1000;

  final List<ReferenceBlock> blocks;

  /// Zero-padding width for labels ("0001"); larger numbers simply use
  /// more digits, matching the app's existing normalization.
  final int labelWidth;

  const ReferenceAllocation({this.blocks = const [], this.labelWidth = 4});

  List<ReferenceBlock> blocksOf(String ownerId) =>
      blocks.where((b) => b.ownerId == ownerId).toList();

  /// Grants the next free block to [ownerId] and returns the new state.
  ///
  /// Deterministic rule: the block starts at the smallest `s` with
  /// `s ≡ 1 (mod size)` that lies above every existing block and above
  /// [floor] (pass the highest Reference number already used in the
  /// database, so the first grant clears existing data). With the default
  /// size that yields human-friendly thousands ranges: 1001, 2001, …
  ReferenceAllocation grantBlock(
    String ownerId, {
    int size = defaultBlockSize,
    int floor = 0,
  }) {
    if (size <= 0) throw ArgumentError.value(size, 'size', 'must be positive');
    var minimum = floor;
    for (final block in blocks) {
      if (block.end > minimum) minimum = block.end;
    }
    // Smallest s > minimum with s % size == 1 (or == 0 for size 1).
    var start = (minimum ~/ size) * size + 1;
    if (start <= minimum) start += size;
    return ReferenceAllocation(
      blocks: [
        ...blocks,
        ReferenceBlock(ownerId: ownerId, start: start, size: size),
      ],
      labelWidth: labelWidth,
    );
  }

  /// The next unused Reference label for [ownerId], scanning their blocks
  /// in grant order and skipping [usedReferences] (compared numerically,
  /// so "42", "042" and "0042" all block number 42).
  ///
  /// Returns null when every number in every block of theirs is used —
  /// time to [grantBlock] a new one.
  String? nextReference(String ownerId, Set<String> usedReferences) {
    final usedNumbers = <int>{
      for (final ref in usedReferences)
        if (int.tryParse(ref.trim()) case final number?) number,
    };
    for (final block in blocksOf(ownerId)) {
      for (var n = block.start; n <= block.end; n++) {
        if (!usedNumbers.contains(n)) return formatLabel(n);
      }
    }
    return null;
  }

  String formatLabel(int number) =>
      number.toString().padLeft(labelWidth, '0');

  /// Deterministic JSON for the synced file.
  String toJson() => const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': version,
        'labelWidth': labelWidth,
        'blocks': [for (final block in blocks) block.toJson()],
      });

  factory ReferenceAllocation.fromJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('Reference blocks file is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?> || decoded['format'] != format) {
      throw const FormatException('Not a $format file');
    }
    final fileVersion = decoded['version'];
    if (fileVersion is! int || fileVersion > version) {
      throw FormatException(
          'Reference blocks version $fileVersion is newer than supported '
          '($version) — update the app');
    }
    return ReferenceAllocation(
      labelWidth: decoded['labelWidth'] as int? ?? 4,
      blocks: [
        for (final block in decoded['blocks'] as List<Object?>)
          ReferenceBlock.fromJson(block as Map<String, Object?>),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReferenceAllocation &&
      other.labelWidth == labelWidth &&
      const ListEquality<ReferenceBlock>().equals(other.blocks, blocks);

  @override
  int get hashCode =>
      Object.hash(labelWidth, const ListEquality<ReferenceBlock>().hash(blocks));
}
