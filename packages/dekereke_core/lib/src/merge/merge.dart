/// Record + field three-way merge keyed on DkSyncID (plan §4.2b).
///
/// Reference plays no part in matching (it is display-only here); records
/// pair up by the DkSyncIDs the identity ladder bound. The rules mirror the
/// plan exactly:
///
/// - additions are kept from both sides;
/// - a field edited on one side only auto-merges, identical edits agree;
/// - the same field edited differently is a [FieldConflict] — nothing
///   proceeds silently, nothing is lost either way (the conflict carries
///   all three values for the plain-language UI);
/// - record deletions are never implicit: a record missing on one side
///   becomes a [PendingDeletion] that the other side confirms; until then
///   it stays in the merged output.
library;

import '../model/database.dart';

/// A record bound to its DkSyncID (see `identity/`).
final class IdentifiedRecord {
  final String id;
  final DekerekeRecord record;

  const IdentifiedRecord(this.id, this.record);

  @override
  bool operator ==(Object other) =>
      other is IdentifiedRecord && other.id == id && other.record == record;

  @override
  int get hashCode => Object.hash(id, record);

  @override
  String toString() => 'IdentifiedRecord($id: $record)';
}

/// Which side of a merge did something.
enum MergeSide { ours, theirs, both }

/// The same field edited to different values on both sides.
///
/// Values are null when the field is absent on that side (absent ≠ empty:
/// presence-only booleans hang on this distinction). For fragment fields
/// the values are the canonical fragment XML and [isFragment] is set.
final class FieldConflict {
  final String id;

  /// Display data for plain-language rendering ("Word 0042 'ear': …").
  final String reference;
  final String gloss;

  final String fieldName;

  /// Which same-named occurrence (0 for the normal unique-name case).
  final int occurrence;

  final bool isFragment;

  final String? baseValue;
  final String? ourValue;
  final String? theirValue;

  const FieldConflict({
    required this.id,
    required this.reference,
    required this.gloss,
    required this.fieldName,
    this.occurrence = 0,
    this.isFragment = false,
    required this.baseValue,
    required this.ourValue,
    required this.theirValue,
  });

  @override
  String toString() =>
      'FieldConflict($reference "$gloss" $fieldName: base=$baseValue '
      'ours=$ourValue theirs=$theirValue)';
}

/// A record deleted on one side (or both) — awaiting explicit confirmation.
final class PendingDeletion {
  final String id;
  final MergeSide deletedBy;

  /// The surviving content (from the side that still has the record; the
  /// base version when both deleted). What "restore instead" would keep.
  final DekerekeRecord record;

  /// True when the surviving side had ALSO edited the record since base —
  /// the classic delete-vs-edit conflict, worth stronger UI wording.
  final bool modifiedBySurvivingSide;

  const PendingDeletion({
    required this.id,
    required this.deletedBy,
    required this.record,
    this.modifiedBySurvivingSide = false,
  });
}

/// Result of [merge3].
final class MergeResult {
  /// Merged records: ours' order first, then theirs-only records in theirs'
  /// order. Records under a one-sided [PendingDeletion] are still included
  /// (deletions apply only via [applyConfirmedDeletions]); both-sided
  /// deletions are not (neither side has the record any more).
  ///
  /// Conflicted fields provisionally hold OUR value until resolved.
  final List<IdentifiedRecord> records;

  final List<FieldConflict> conflicts;
  final List<PendingDeletion> pendingDeletions;

  /// IDs of records added since base, per side (for checkpoint summaries).
  final List<String> addedByOurs;
  final List<String> addedByTheirs;

  const MergeResult({
    required this.records,
    required this.conflicts,
    required this.pendingDeletions,
    required this.addedByOurs,
    required this.addedByTheirs,
  });

  bool get isClean => conflicts.isEmpty && pendingDeletions.isEmpty;
}

/// Three-way merge of identified record lists.
///
/// [base] is the common ancestor checkpoint; [ours]/[theirs] are its two
/// descendants. IDs must be unique within each list (they are DkSyncIDs).
MergeResult merge3({
  required List<IdentifiedRecord> base,
  required List<IdentifiedRecord> ours,
  required List<IdentifiedRecord> theirs,
}) {
  final baseById = {for (final r in base) r.id: r.record};
  final oursById = {for (final r in ours) r.id: r.record};
  final theirsById = {for (final r in theirs) r.id: r.record};

  final records = <IdentifiedRecord>[];
  final conflicts = <FieldConflict>[];
  final pendingDeletions = <PendingDeletion>[];
  final addedByOurs = <String>[];
  final addedByTheirs = <String>[];

  void mergeRecord(String id, DekerekeRecord our, DekerekeRecord their) {
    final baseRecord = baseById[id];
    if (our == their) {
      records.add(IdentifiedRecord(id, our));
      return;
    }
    final merged = _mergeFields(
      id: id,
      base: baseRecord ?? const DekerekeRecord([]),
      ours: our,
      theirs: their,
      conflicts: conflicts,
    );
    records.add(IdentifiedRecord(id, merged));
  }

  // Ours' order drives the output.
  for (final our in ours) {
    final their = theirsById[our.id];
    final inBase = baseById.containsKey(our.id);
    if (their != null) {
      if (!inBase) {
        // Added on both sides under one ID (identity synced out of band).
        addedByOurs.add(our.id);
        addedByTheirs.add(our.id);
      }
      mergeRecord(our.id, our.record, their);
    } else if (!inBase) {
      addedByOurs.add(our.id);
      records.add(our);
    } else {
      // In base and ours, gone from theirs: they deleted it.
      records.add(our);
      pendingDeletions.add(PendingDeletion(
        id: our.id,
        deletedBy: MergeSide.theirs,
        record: our.record,
        modifiedBySurvivingSide: baseById[our.id] != our.record,
      ));
    }
  }

  // Theirs-only records: additions and our-side deletions.
  for (final their in theirs) {
    if (oursById.containsKey(their.id)) continue;
    if (!baseById.containsKey(their.id)) {
      addedByTheirs.add(their.id);
      records.add(their);
    } else {
      records.add(their);
      pendingDeletions.add(PendingDeletion(
        id: their.id,
        deletedBy: MergeSide.ours,
        record: their.record,
        modifiedBySurvivingSide: baseById[their.id] != their.record,
      ));
    }
  }

  // Deleted on both sides: agreed, gone from the output, reported.
  for (final b in base) {
    if (!oursById.containsKey(b.id) && !theirsById.containsKey(b.id)) {
      pendingDeletions.add(PendingDeletion(
        id: b.id,
        deletedBy: MergeSide.both,
        record: b.record,
      ));
    }
  }

  return MergeResult(
    records: records,
    conflicts: conflicts,
    pendingDeletions: pendingDeletions,
    addedByOurs: addedByOurs,
    addedByTheirs: addedByTheirs,
  );
}

/// Removes records whose one-sided pending deletion the user confirmed.
List<IdentifiedRecord> applyConfirmedDeletions(
        List<IdentifiedRecord> records, Set<String> confirmedIds) =>
    records.where((r) => !confirmedIds.contains(r.id)).toList();

// ---- Field-level merge ------------------------------------------------------

/// A field slot: name + occurrence index among same-named fields, so
/// repeated tags (rare but legal XML) merge positionally instead of
/// colliding.
typedef _Slot = (String name, int occurrence);

Map<_Slot, DekerekeField> _slots(DekerekeRecord record) {
  final counts = <String, int>{};
  final map = <_Slot, DekerekeField>{};
  for (final field in record.fields) {
    final n = counts.update(field.name, (c) => c + 1, ifAbsent: () => 0);
    map[(field.name, n)] = field;
  }
  return map;
}

bool _same(DekerekeField? a, DekerekeField? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a == b;
}

String? _valueOf(DekerekeField? field) => switch (field) {
      null => null,
      DekerekeValueField(:final value) => value,
      DekerekeFragmentField(:final xml) => xml,
    };

DekerekeRecord _mergeFields({
  required String id,
  required DekerekeRecord base,
  required DekerekeRecord ours,
  required DekerekeRecord theirs,
  required List<FieldConflict> conflicts,
}) {
  final baseSlots = _slots(base);
  final ourSlots = _slots(ours);
  final theirSlots = _slots(theirs);

  // Merged slot order: ours' slots, then theirs-only slots (theirs' order).
  final order = <_Slot>[...ourSlots.keys];
  for (final slot in theirSlots.keys) {
    if (!ourSlots.containsKey(slot)) order.add(slot);
  }

  final reference = ours.reference.isNotEmpty ? ours.reference : theirs.reference;
  final gloss = ours.gloss.isNotEmpty ? ours.gloss : theirs.gloss;

  final mergedFields = <DekerekeField>[];
  for (final slot in order) {
    final b = baseSlots[slot];
    final o = ourSlots[slot];
    final t = theirSlots[slot];

    final DekerekeField? chosen;
    if (_same(o, t)) {
      chosen = o;
    } else if (_same(b, o)) {
      chosen = t; // theirs changed
    } else if (_same(b, t)) {
      chosen = o; // ours changed
    } else {
      // Both changed, differently → conflict; keep ours provisionally.
      chosen = o;
      conflicts.add(FieldConflict(
        id: id,
        reference: reference,
        gloss: gloss,
        fieldName: slot.$1,
        occurrence: slot.$2,
        isFragment: (o ?? t ?? b) is DekerekeFragmentField,
        baseValue: _valueOf(b),
        ourValue: _valueOf(o),
        theirValue: _valueOf(t),
      ));
    }
    if (chosen != null) mergedFields.add(chosen);
  }
  return DekerekeRecord(mergedFields);
}

/// Applies a user's resolution of [conflict] to [records]: replaces the
/// conflicted slot with [resolvedValue] (a plain value, or canonical
/// fragment XML when the conflict [FieldConflict.isFragment]); null removes
/// the field. Returns the updated list.
List<IdentifiedRecord> applyConflictResolution(
  List<IdentifiedRecord> records,
  FieldConflict conflict,
  String? resolvedValue,
) {
  return records.map((identified) {
    if (identified.id != conflict.id) return identified;
    final fields = List.of(identified.record.fields);
    var occurrence = -1;
    final index = fields.indexWhere((f) {
      if (f.name != conflict.fieldName) return false;
      occurrence++;
      return occurrence == conflict.occurrence;
    });
    final DekerekeField? replacement = switch (resolvedValue) {
      null => null,
      final v when conflict.isFragment => DekerekeFragmentField(conflict.fieldName, v),
      final v => DekerekeValueField(conflict.fieldName, v),
    };
    if (index >= 0) {
      if (replacement == null) {
        fields.removeAt(index);
      } else {
        fields[index] = replacement;
      }
    } else if (replacement != null) {
      fields.add(replacement);
    }
    return IdentifiedRecord(identified.id, DekerekeRecord(fields));
  }).toList();
}

/// Pairs a database's records with the IDs of an identity map's entries in
/// order — the normal way to feed [merge3] after `reconcileIdentity`.
List<IdentifiedRecord> identifyRecords(
    List<DekerekeRecord> records, List<String> idsInOrder) {
  if (records.length != idsInOrder.length) {
    throw ArgumentError(
        'records (${records.length}) and ids (${idsInOrder.length}) '
        'must align');
  }
  return [
    for (final (i, record) in records.indexed)
      IdentifiedRecord(idsInOrder[i], record),
  ];
}

// ---- Object-level diff ------------------------------------------------------

/// One field's change between two versions of a record. Null values mean
/// the field was absent on that side (absent ≠ empty).
final class RecordFieldChange {
  final String fieldName;
  final int occurrence;
  final bool isFragment;
  final String? fromValue;
  final String? toValue;

  const RecordFieldChange({
    required this.fieldName,
    this.occurrence = 0,
    this.isFragment = false,
    required this.fromValue,
    required this.toValue,
  });

  @override
  String toString() =>
      'RecordFieldChange($fieldName: $fromValue -> $toValue)';
}

/// A record present in both versions with different content.
final class ChangedRecord {
  final String id;

  /// Display data (from the newer version) for plain-language rendering.
  final String reference;
  final String gloss;

  final List<RecordFieldChange> changes;

  const ChangedRecord({
    required this.id,
    required this.reference,
    required this.gloss,
    required this.changes,
  });
}

/// What changed between two checkpoints, at the record/field level —
/// this powers "Saved by Seth — 3 words changed" history summaries and
/// per-record tracked changes. Line numbers never appear anywhere.
final class DatabaseDiff {
  final List<IdentifiedRecord> added;
  final List<IdentifiedRecord> removed;
  final List<ChangedRecord> changed;

  /// True when the shared records appear in a different order (a grid
  /// re-sort, not a content change — reported separately so summaries
  /// don't count it as an edit).
  final bool orderChanged;

  const DatabaseDiff({
    required this.added,
    required this.removed,
    required this.changed,
    required this.orderChanged,
  });

  bool get isEmpty =>
      added.isEmpty && removed.isEmpty && changed.isEmpty && !orderChanged;
}

/// Object-level diff between two identified record lists (older [from] →
/// newer [to]), keyed on DkSyncID like everything else.
DatabaseDiff diffRecords(
    List<IdentifiedRecord> from, List<IdentifiedRecord> to) {
  final fromById = {for (final r in from) r.id: r.record};
  final toById = {for (final r in to) r.id: r.record};

  final added = [for (final r in to) if (!fromById.containsKey(r.id)) r];
  final removed = [for (final r in from) if (!toById.containsKey(r.id)) r];

  final changed = <ChangedRecord>[];
  for (final r in to) {
    final before = fromById[r.id];
    if (before == null || before == r.record) continue;
    final beforeSlots = _slots(before);
    final afterSlots = _slots(r.record);
    final slots = <_Slot>[...afterSlots.keys];
    for (final slot in beforeSlots.keys) {
      if (!afterSlots.containsKey(slot)) slots.add(slot);
    }
    final changes = <RecordFieldChange>[
      for (final slot in slots)
        if (!_same(beforeSlots[slot], afterSlots[slot]))
          RecordFieldChange(
            fieldName: slot.$1,
            occurrence: slot.$2,
            isFragment: (afterSlots[slot] ?? beforeSlots[slot])
                is DekerekeFragmentField,
            fromValue: _valueOf(beforeSlots[slot]),
            toValue: _valueOf(afterSlots[slot]),
          ),
    ];
    changed.add(ChangedRecord(
      id: r.id,
      reference: r.record.reference,
      gloss: r.record.gloss,
      changes: changes,
    ));
  }

  final sharedFromOrder = [
    for (final r in from) if (toById.containsKey(r.id)) r.id
  ];
  final sharedToOrder = [
    for (final r in to) if (fromById.containsKey(r.id)) r.id
  ];
  var orderChanged = false;
  for (var i = 0; i < sharedFromOrder.length; i++) {
    if (sharedFromOrder[i] != sharedToOrder[i]) {
      orderChanged = true;
      break;
    }
  }

  return DatabaseDiff(
    added: added,
    removed: removed,
    changed: changed,
    orderChanged: orderChanged,
  );
}
