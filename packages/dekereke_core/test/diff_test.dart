import 'package:dekereke_core/dekereke_core.dart';
import 'package:test/test.dart';

DekerekeRecord record(String ref, String gloss, {String phonetic = ''}) =>
    DekerekeRecord([
      DekerekeValueField('Reference', ref),
      DekerekeValueField('Gloss', gloss),
      DekerekeValueField('Phonetic', phonetic),
    ]);

void main() {
  final base = [
    IdentifiedRecord('a', record('0001', 'body', phonetic: 'bɔdi')),
    IdentifiedRecord('b', record('0002', 'water', phonetic: 'ɸaʔɛ')),
    IdentifiedRecord('c', record('0003', 'ear', phonetic: 'ɛnɔ')),
  ];

  test('identical versions diff empty', () {
    expect(diffRecords(base, base).isEmpty, isTrue);
  });

  test('field edits are reported per record and field, never as lines', () {
    final after = [
      base[0],
      IdentifiedRecord('b', record('0002', 'water', phonetic: 'ɸaʔe')),
      base[2],
    ];
    final diff = diffRecords(base, after);
    expect(diff.added, isEmpty);
    expect(diff.removed, isEmpty);
    expect(diff.orderChanged, isFalse);
    final change = diff.changed.single;
    expect(change.id, 'b');
    expect(change.reference, '0002');
    expect(change.gloss, 'water');
    final field = change.changes.single;
    expect(field.fieldName, 'Phonetic');
    expect(field.fromValue, 'ɸaʔɛ');
    expect(field.toValue, 'ɸaʔe');
  });

  test('field added / cleared / removed are distinct changes', () {
    final after = [
      IdentifiedRecord(
          'a', record('0001', 'body', phonetic: 'bɔdi').withValue('Notes', 'n')),
      IdentifiedRecord('b', record('0002', 'water')), // Phonetic cleared to ''
      IdentifiedRecord(
          'c',
          const DekerekeRecord([
            DekerekeValueField('Reference', '0003'),
            DekerekeValueField('Gloss', 'ear'),
          ])), // Phonetic field REMOVED
    ];
    final diff = diffRecords(base, after);
    expect(diff.changed, hasLength(3));

    final aChange = diff.changed.firstWhere((c) => c.id == 'a').changes.single;
    expect(aChange.fieldName, 'Notes');
    expect(aChange.fromValue, isNull, reason: 'field did not exist before');
    expect(aChange.toValue, 'n');

    final bChange = diff.changed.firstWhere((c) => c.id == 'b').changes.single;
    expect(bChange.fromValue, 'ɸaʔɛ');
    expect(bChange.toValue, '', reason: 'cleared but still present');

    final cChange = diff.changed.firstWhere((c) => c.id == 'c').changes.single;
    expect(cChange.fromValue, 'ɛnɔ');
    expect(cChange.toValue, isNull, reason: 'field removed entirely');
  });

  test('additions and removals are keyed by DkSyncID', () {
    final after = [
      base[0],
      base[2],
      IdentifiedRecord('x', record('0100', 'sun')),
    ];
    final diff = diffRecords(base, after);
    expect(diff.added.single.id, 'x');
    expect(diff.removed.single.id, 'b');
    expect(diff.changed, isEmpty);
  });

  test('a pure re-sort is order-only, not counted as edits', () {
    final after = [base[2], base[0], base[1]];
    final diff = diffRecords(base, after);
    expect(diff.changed, isEmpty);
    expect(diff.added, isEmpty);
    expect(diff.removed, isEmpty);
    expect(diff.orderChanged, isTrue);
    expect(diff.isEmpty, isFalse);
  });

  test('fragment changes are flagged as fragments', () {
    final withFragment = [
      IdentifiedRecord(
          'a',
          DekerekeRecord([
            ...record('0001', 'body').fields,
            const DekerekeFragmentField('qvp_acoustic_data_', '<qvp_acoustic_data_><f1>1</f1></qvp_acoustic_data_>'),
          ])),
    ];
    final after = [
      IdentifiedRecord(
          'a',
          DekerekeRecord([
            ...record('0001', 'body').fields,
            const DekerekeFragmentField('qvp_acoustic_data_', '<qvp_acoustic_data_><f1>2</f1></qvp_acoustic_data_>'),
          ])),
    ];
    final change = diffRecords(withFragment, after).changed.single.changes.single;
    expect(change.isFragment, isTrue);
    expect(change.fieldName, 'qvp_acoustic_data_');
  });
}
