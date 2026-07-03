import 'package:dekereke_core/dekereke_core.dart';
import 'package:test/test.dart';

DekerekeRecord record(String ref, String gloss,
        {String phonetic = '', String notes = '', bool loan = false}) =>
    DekerekeRecord([
      DekerekeValueField('Reference', ref),
      DekerekeValueField('Gloss', gloss),
      DekerekeValueField('Phonetic', phonetic),
      DekerekeValueField('Notes', notes),
      if (loan) const DekerekeValueField('loan', ''),
    ]);

IdentifiedRecord idr(String id, DekerekeRecord r) => IdentifiedRecord(id, r);

void main() {
  final base = [
    idr('a', record('0001', 'body', phonetic: 'bɔdi')),
    idr('b', record('0002', 'water', phonetic: 'ɸaʔɛ')),
    idr('c', record('0003', 'ear', phonetic: 'ɛnɔ')),
  ];

  group('clean merges', () {
    test('identical sides merge to themselves', () {
      final result = merge3(base: base, ours: base, theirs: base);
      expect(result.isClean, isTrue);
      expect(result.records, base);
    });

    test('disjoint field edits auto-merge', () {
      final ours = [
        base[0],
        idr('b', record('0002', 'water', phonetic: 'ɸaʔe')), // we edited Phonetic
        base[2],
      ];
      final theirs = [
        base[0],
        idr('b', record('0002', 'water', phonetic: 'ɸaʔɛ', notes: 'checked')),
        base[2],
      ];
      final result = merge3(base: base, ours: ours, theirs: theirs);
      expect(result.isClean, isTrue);
      final merged = result.records[1].record;
      expect(merged.valueOf('Phonetic'), 'ɸaʔe');
      expect(merged.valueOf('Notes'), 'checked');
    });

    test('identical edits on both sides agree', () {
      final edited = [
        base[0],
        idr('b', record('0002', 'water', phonetic: 'NEW')),
        base[2],
      ];
      final result = merge3(base: base, ours: edited, theirs: edited);
      expect(result.isClean, isTrue);
      expect(result.records[1].record.valueOf('Phonetic'), 'NEW');
    });

    test('edits to different records auto-merge', () {
      final ours = [
        idr('a', record('0001', 'body', phonetic: 'EDIT-A')),
        base[1],
        base[2],
      ];
      final theirs = [
        base[0],
        base[1],
        idr('c', record('0003', 'ear', phonetic: 'EDIT-C')),
      ];
      final result = merge3(base: base, ours: ours, theirs: theirs);
      expect(result.isClean, isTrue);
      expect(result.records[0].record.valueOf('Phonetic'), 'EDIT-A');
      expect(result.records[2].record.valueOf('Phonetic'), 'EDIT-C');
    });
  });

  group('additions', () {
    test('kept from both sides, ours order first then theirs-only', () {
      final ours = [...base, idr('x', record('0100', 'sun'))];
      final theirs = [...base, idr('y', record('0200', 'moon'))];
      final result = merge3(base: base, ours: ours, theirs: theirs);
      expect(result.isClean, isTrue);
      expect(result.records.map((r) => r.id), ['a', 'b', 'c', 'x', 'y']);
      expect(result.addedByOurs, ['x']);
      expect(result.addedByTheirs, ['y']);
    });

    test('same-Reference additions coexist (identity is the ID, not Reference)',
        () {
      final ours = [...base, idr('x', record('0100', 'sun'))];
      final theirs = [...base, idr('y', record('0100', 'sunshine'))];
      final result = merge3(base: base, ours: ours, theirs: theirs);
      expect(result.isClean, isTrue);
      expect(result.records, hasLength(5));
    });

    test('added on both sides under one ID: field-merged against empty base',
        () {
      final added = DekerekeRecord(const [
        DekerekeValueField('Reference', '0100'),
        DekerekeValueField('Gloss', 'sun'),
        DekerekeValueField('Phonetic', 'x'),
      ]);
      final ours = [...base, idr('x', added)];
      // Theirs has the same content plus a field ours lacks entirely.
      final theirs = [...base, idr('x', added.withValue('Notes', 'from B'))];
      final result = merge3(base: base, ours: ours, theirs: theirs);
      expect(result.conflicts, isEmpty);
      final merged = result.records.last.record;
      expect(merged.valueOf('Phonetic'), 'x');
      expect(merged.valueOf('Notes'), 'from B');
    });

    test('added on both sides: empty-present vs filled field is a conflict '
        '(absent ≠ empty is strict)', () {
      final ours = [...base, idr('x', record('0100', 'sun'))]; // Notes = ''
      final theirs = [
        ...base,
        idr('x', record('0100', 'sun', notes: 'from B'))
      ];
      final result = merge3(base: base, ours: ours, theirs: theirs);
      expect(result.conflicts, hasLength(1));
      expect(result.conflicts.single.fieldName, 'Notes');
      expect(result.conflicts.single.baseValue, isNull);
      expect(result.conflicts.single.ourValue, '');
      expect(result.conflicts.single.theirValue, 'from B');
    });
  });

  group('conflicts', () {
    test('same field, different values → conflict with all three values', () {
      final ours = [
        base[0],
        idr('b', record('0002', 'water', phonetic: 'ɛnɔ')),
        base[2],
      ];
      final theirs = [
        base[0],
        idr('b', record('0002', 'water', phonetic: 'ɛnɔː')),
        base[2],
      ];
      final result = merge3(base: base, ours: ours, theirs: theirs);
      expect(result.conflicts, hasLength(1));
      final conflict = result.conflicts.single;
      expect(conflict.id, 'b');
      expect(conflict.reference, '0002');
      expect(conflict.gloss, 'water');
      expect(conflict.fieldName, 'Phonetic');
      expect(conflict.baseValue, 'ɸaʔɛ');
      expect(conflict.ourValue, 'ɛnɔ');
      expect(conflict.theirValue, 'ɛnɔː');
      expect(conflict.isFragment, isFalse);
      // Merged output provisionally holds ours.
      expect(result.records[1].record.valueOf('Phonetic'), 'ɛnɔ');
    });

    test('resolution helpers apply any choice', () {
      final ours = [idr('b', record('0002', 'water', phonetic: 'ɛnɔ'))];
      final theirs = [idr('b', record('0002', 'water', phonetic: 'ɛnɔː'))];
      final result = merge3(
          base: [idr('b', record('0002', 'water', phonetic: 'x'))],
          ours: ours,
          theirs: theirs);
      final conflict = result.conflicts.single;

      final keepTheirs = applyConflictResolution(
          result.records, conflict, conflict.theirValue);
      expect(keepTheirs.single.record.valueOf('Phonetic'), 'ɛnɔː');

      final custom =
          applyConflictResolution(result.records, conflict, 'merged form');
      expect(custom.single.record.valueOf('Phonetic'), 'merged form');

      final removed = applyConflictResolution(result.records, conflict, null);
      expect(removed.single.record.valueOf('Phonetic'), isNull);
    });

    test('presence-only boolean: cleared on one side merges; both-changed '
        'differently conflicts on absence vs value', () {
      final withLoan = [idr('a', record('0001', 'body', loan: true))];
      final without = [idr('a', record('0001', 'body'))];
      // Ours cleared the flag, theirs untouched → cleared.
      final cleared =
          merge3(base: withLoan, ours: without, theirs: withLoan);
      expect(cleared.isClean, isTrue);
      expect(cleared.records.single.record.hasField('loan'), isFalse);

      // Ours cleared it, theirs gave it a value → conflict (absent ≠ empty).
      final valued = [
        idr('a', record('0001', 'body').withValue('loan', 'x'))
      ];
      final conflicted = merge3(base: withLoan, ours: without, theirs: valued);
      expect(conflicted.conflicts, hasLength(1));
      expect(conflicted.conflicts.single.ourValue, isNull);
      expect(conflicted.conflicts.single.theirValue, 'x');
      expect(conflicted.conflicts.single.baseValue, '');
    });

    test('fragment fields conflict with isFragment set', () {
      const fragA = DekerekeFragmentField('qvp_acoustic_data_',
          '<qvp_acoustic_data_><f1>700</f1></qvp_acoustic_data_>');
      const fragB = DekerekeFragmentField('qvp_acoustic_data_',
          '<qvp_acoustic_data_><f1>710</f1></qvp_acoustic_data_>');
      const fragBase = DekerekeFragmentField('qvp_acoustic_data_',
          '<qvp_acoustic_data_><f1>690</f1></qvp_acoustic_data_>');
      final b = [
        idr('a', DekerekeRecord([...record('0001', 'body').fields, fragBase]))
      ];
      final o = [
        idr('a', DekerekeRecord([...record('0001', 'body').fields, fragA]))
      ];
      final t = [
        idr('a', DekerekeRecord([...record('0001', 'body').fields, fragB]))
      ];
      final result = merge3(base: b, ours: o, theirs: t);
      expect(result.conflicts.single.isFragment, isTrue);
      expect(result.conflicts.single.ourValue, contains('700'));
    });
  });

  group('deletions (never implicit)', () {
    test('their deletion: record survives + pending deletion reported', () {
      final theirs = [base[0], base[2]];
      final result = merge3(base: base, ours: base, theirs: theirs);
      expect(result.records.map((r) => r.id), ['a', 'b', 'c'],
          reason: 'deletion must not apply silently');
      final pending = result.pendingDeletions.single;
      expect(pending.id, 'b');
      expect(pending.deletedBy, MergeSide.theirs);
      expect(pending.modifiedBySurvivingSide, isFalse);
    });

    test('delete vs edit: flagged as modified by surviving side', () {
      final ours = [
        base[0],
        idr('b', record('0002', 'water', phonetic: 'EDITED')),
        base[2],
      ];
      final theirs = [base[0], base[2]];
      final result = merge3(base: base, ours: ours, theirs: theirs);
      final pending = result.pendingDeletions.single;
      expect(pending.deletedBy, MergeSide.theirs);
      expect(pending.modifiedBySurvivingSide, isTrue);
      expect(pending.record.valueOf('Phonetic'), 'EDITED');
    });

    test('our deletion mirrors', () {
      final ours = [base[0], base[2]];
      final result = merge3(base: base, ours: ours, theirs: base);
      expect(result.records.map((r) => r.id), ['a', 'c', 'b'],
          reason: 'kept record re-enters after ours (theirs-only order)');
      expect(result.pendingDeletions.single.deletedBy, MergeSide.ours);
    });

    test('deleted on both sides: gone from output, reported as agreed', () {
      final oneLess = [base[0], base[2]];
      final result = merge3(base: base, ours: oneLess, theirs: oneLess);
      expect(result.records.map((r) => r.id), ['a', 'c']);
      expect(result.pendingDeletions.single.deletedBy, MergeSide.both);
    });

    test('applyConfirmedDeletions removes exactly the confirmed ids', () {
      final theirs = [base[0], base[2]];
      final result = merge3(base: base, ours: base, theirs: theirs);
      final applied = applyConfirmedDeletions(result.records, {'b'});
      expect(applied.map((r) => r.id), ['a', 'c']);
    });
  });

  group('ordering', () {
    test("ours' record order wins for shared records", () {
      final ours = [base[2], base[0], base[1]];
      final result = merge3(base: base, ours: ours, theirs: base);
      expect(result.records.map((r) => r.id), ['c', 'a', 'b']);
    });

    test('theirs-only field appended after ours fields', () {
      final ours = [idr('a', record('0001', 'body', phonetic: 'x'))];
      final theirs = [
        idr('a',
            record('0001', 'body').withValue('NewColumn', 'from theirs'))
      ];
      final b = [idr('a', record('0001', 'body'))];
      final result = merge3(base: b, ours: ours, theirs: theirs);
      final merged = result.records.single.record;
      expect(merged.fields.last.name, 'NewColumn');
      expect(merged.valueOf('Phonetic'), 'x');
      expect(result.isClean, isTrue);
    });
  });

  group('identifyRecords', () {
    test('zips records with ids in order', () {
      final records = [record('1', 'a'), record('2', 'b')];
      final identified = identifyRecords(records, ['id1', 'id2']);
      expect(identified[0].id, 'id1');
      expect(identified[1].record.gloss, 'b');
    });

    test('throws on length mismatch', () {
      expect(() => identifyRecords([record('1', 'a')], ['x', 'y']),
          throwsArgumentError);
    });
  });

  group('phone merge-back shape (plan §5.3)', () {
    test('task-writable cell edits merge like any other field edit', () {
      // Researcher exported a task at `base`; speaker filled Phonetic on the
      // phone (theirs); researcher meanwhile edited Notes (ours).
      final ours = [
        idr('a', record('0001', 'body', notes: 'researcher note')),
      ];
      final theirs = [
        idr('a', record('0001', 'body', phonetic: 'bɔdi ')), // trailing space kept
      ];
      final b = [idr('a', record('0001', 'body'))];
      final result = merge3(base: b, ours: ours, theirs: theirs);
      expect(result.isClean, isTrue);
      final merged = result.records.single.record;
      expect(merged.valueOf('Phonetic'), 'bɔdi ');
      expect(merged.valueOf('Notes'), 'researcher note');
    });
  });
}
