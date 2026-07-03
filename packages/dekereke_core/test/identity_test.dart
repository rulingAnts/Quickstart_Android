import 'dart:io';

import 'package:dekereke_core/dekereke_core.dart';
import 'package:test/test.dart';

/// Deterministic ID minter for tests.
String Function() counterMinter([String prefix = 'new']) {
  var n = 0;
  return () => '$prefix${(n++).toString().padLeft(3, '0')}';
}

DekerekeRecord record(String ref, String gloss,
        {String? phonetic, String? soundFile, String? notes}) =>
    DekerekeRecord([
      DekerekeValueField('Reference', ref),
      DekerekeValueField('Gloss', gloss),
      DekerekeValueField('Phonetic', phonetic ?? ''),
      DekerekeValueField('SoundFile', soundFile ?? ''),
      if (notes != null) DekerekeValueField('Notes', notes),
    ]);

/// Adopts [records] into a fresh identity map with predictable IDs
/// id000, id001, …
IdentityMap adopt(List<DekerekeRecord> records) =>
    reconcileIdentity(const IdentityMap.empty(), records,
            mintId: counterMinter('id'))
        .updated;

void main() {
  final baseRecords = [
    record('0001', 'body', phonetic: 'bɔdi', soundFile: '0001_body.wav'),
    record('0002', 'water (fresh)', phonetic: 'ɸaʔɛ', soundFile: '0002_water.wav'),
    record('0003', 'ear', phonetic: 'ɛnɔ', soundFile: '0003_ear.wav'),
  ];

  group('adoption (empty previous map)', () {
    test('all records minted, in order, fingerprints recorded', () {
      final result = reconcileIdentity(const IdentityMap.empty(), baseRecords,
          mintId: counterMinter('id'));
      expect(result.records.map((r) => r.id), ['id000', 'id001', 'id002']);
      expect(result.records.every((r) => r.rung == MatchRung.minted), isTrue);
      expect(result.vanished, isEmpty);
      expect(result.updated.entries[1].fingerprint.reference, '0002');
      expect(result.updated.entries[1].fingerprint.position, 1);
    });
  });

  group('re-binding ladder', () {
    test('unchanged save: everything matches by content hash', () {
      final map = adopt(baseRecords);
      final result = reconcileIdentity(map, baseRecords, mintId: counterMinter());
      expect(result.records.map((r) => r.id), ['id000', 'id001', 'id002']);
      expect(result.records.every((r) => r.rung == MatchRung.contentHash), isTrue);
      expect(result.minted, isEmpty);
      expect(result.vanished, isEmpty);
      expect(result.needingReview, isEmpty);
    });

    test('field edit: ID restored via SoundFile', () {
      final map = adopt(baseRecords);
      final edited = List.of(baseRecords);
      edited[1] = baseRecords[1].withValue('Phonetic', 'ɸaʔe');
      final result = reconcileIdentity(map, edited, mintId: counterMinter());
      expect(result.records[1].id, 'id001');
      expect(result.records[1].rung, MatchRung.soundFile);
      expect(result.records[1].needsReview, isFalse);
    });

    test('field + SoundFile edit: ID restored via Reference+Gloss', () {
      final map = adopt(baseRecords);
      final edited = List.of(baseRecords);
      edited[1] = baseRecords[1]
          .withValue('Phonetic', 'ɸaʔe')
          .withValue('SoundFile', '0002_water_retake.wav');
      final result = reconcileIdentity(map, edited, mintId: counterMinter());
      expect(result.records[1].id, 'id001');
      expect(result.records[1].rung, MatchRung.referenceGloss);
    });

    test('everything edited: ID restored via position, flagged for review', () {
      final map = adopt(baseRecords);
      final edited = List.of(baseRecords);
      edited[1] = record('0099', 'renumbered water', phonetic: 'x',
          soundFile: '0099_new.wav');
      final result = reconcileIdentity(map, edited, mintId: counterMinter());
      expect(result.records[1].id, 'id001');
      expect(result.records[1].rung, MatchRung.position);
      expect(result.records[1].needsReview, isTrue);
      expect(result.needingReview, hasLength(1));
    });

    test('reorder: content hash wins, positions refreshed, nothing minted', () {
      final map = adopt(baseRecords);
      final reordered = [baseRecords[2], baseRecords[0], baseRecords[1]];
      final result = reconcileIdentity(map, reordered, mintId: counterMinter());
      expect(result.records.map((r) => r.id), ['id002', 'id000', 'id001']);
      expect(result.records.every((r) => r.rung == MatchRung.contentHash), isTrue);
      expect(result.updated.entries.map((e) => e.fingerprint.position), [0, 1, 2],
          reason: 'fingerprints must be refreshed to the new positions');
    });

    test('reorder + edit together: edited record still found by SoundFile', () {
      final map = adopt(baseRecords);
      final changed = [
        baseRecords[2],
        baseRecords[1].withValue('Phonetic', 'CHANGED'),
        baseRecords[0],
      ];
      final result = reconcileIdentity(map, changed, mintId: counterMinter());
      expect(result.records.map((r) => r.id), ['id002', 'id001', 'id000']);
      expect(result.records[1].rung, MatchRung.soundFile);
    });
  });

  group('deletions', () {
    test('deleted record vanishes explicitly, ID never reused', () {
      final map = adopt(baseRecords);
      final remaining = [baseRecords[0], baseRecords[2]];
      final result = reconcileIdentity(map, remaining, mintId: counterMinter());
      expect(result.records.map((r) => r.id), ['id000', 'id002']);
      expect(result.vanished.map((e) => e.id), ['id001']);
      expect(result.updated.byId('id001'), isNull);
    });

    test('delete + add at same position: no false rebinding via position when '
        'stronger signals exist elsewhere', () {
      final map = adopt(baseRecords);
      final changed = [
        baseRecords[0],
        record('0042', 'brand new', soundFile: '0042_new.wav'),
        baseRecords[2],
      ];
      final result = reconcileIdentity(map, changed, mintId: counterMinter());
      expect(result.records[0].id, 'id000');
      expect(result.records[2].id, 'id002');
      // The new record at position 1 pairs with vanished id001 on the
      // position rung — exactly the ambiguous case the review flag exists for.
      expect(result.records[1].id, 'id001');
      expect(result.records[1].rung, MatchRung.position);
      expect(result.records[1].needsReview, isTrue);
    });
  });

  group('duplicates', () {
    test('duplicated row: best match keeps the ID, copy minted + flagged', () {
      final map = adopt(baseRecords);
      final withCopy = [
        baseRecords[0],
        baseRecords[1],
        baseRecords[1], // exact copy inserted right after
        baseRecords[2],
      ];
      final result =
          reconcileIdentity(map, withCopy, mintId: counterMinter('mint'));
      expect(result.records[1].id, 'id001');
      expect(result.records[1].rung, MatchRung.contentHash);
      final copy = result.records[2];
      expect(copy.rung, MatchRung.minted);
      expect(copy.nearDuplicateOfId, 'id001');
      // id002 must not be stolen by the copy.
      expect(result.records[3].id, 'id002');
      expect(result.vanished, isEmpty);
    });

    test('duplicate References with distinct glosses stay distinct', () {
      final twins = [
        record('0002', 'water (fresh)', soundFile: 'a.wav'),
        record('0002', 'water (in river)', soundFile: 'b.wav'),
      ];
      final map = adopt(twins);
      // Edit both (content + soundfile changed) → Reference+Gloss rung must
      // still tell them apart.
      final edited = [
        twins[0].withValue('Phonetic', 'x').withValue('SoundFile', 'a2.wav'),
        twins[1].withValue('Phonetic', 'y').withValue('SoundFile', 'b2.wav'),
      ];
      final result = reconcileIdentity(map, edited, mintId: counterMinter());
      expect(result.records.map((r) => r.id), ['id000', 'id001']);
      expect(result.records.every((r) => r.rung == MatchRung.referenceGloss),
          isTrue);
    });

    test('records with empty Reference and Gloss never match the '
        'referenceGloss rung', () {
      final blank = [record('', '', notes: 'first')];
      final map = adopt(blank);
      final changed = [record('', '', notes: 'second — content changed')];
      final result = reconcileIdentity(map, changed, mintId: counterMinter());
      // Falls through to position (both at 0), not referenceGloss.
      expect(result.records[0].rung, MatchRung.position);
      expect(result.records[0].id, 'id000');
    });
  });

  group('identity map JSON', () {
    test('round-trips deterministically', () {
      final map = adopt(baseRecords);
      final json = map.toJson();
      expect(IdentityMap.fromJson(json), map);
      expect(IdentityMap.fromJson(json).toJson(), json);
    });

    test('rejects foreign or future files', () {
      expect(() => IdentityMap.fromJson('{"format":"other"}'),
          throwsFormatException);
      expect(
          () => IdentityMap.fromJson(
              '{"format":"deksync-identity","version":999,"records":[]}'),
          throwsFormatException);
      expect(() => IdentityMap.fromJson('not json'), throwsFormatException);
    });

    test('content hash matches the canonical rendering, cross-machine stable',
        () {
      // Hash is over renderRecordCanonical — same content, same hash,
      // regardless of which machine computed it.
      final a = record('0001', 'body', phonetic: 'bɔdi');
      final b = record('0001', 'body', phonetic: 'bɔdi');
      expect(recordContentHash(a), recordContentHash(b));
      expect(recordContentHash(a),
          isNot(recordContentHash(a.withValue('Phonetic', 'x'))));
    });
  });

  group('with the synthetic fixture', () {
    test('full adopt → edit → reconcile cycle on real-format records', () {
      final db = parseDekerekeFile(
          File('../../test_data/dekereke_fixtures/synthetic_db.xml')
              .readAsBytesSync());
      final map = adopt(db.records);
      expect(map.entries, hasLength(5));

      // Edit the nested-fragment record's Phonetic; its qvp fragment and
      // duplicate-Reference sibling must not confuse the ladder.
      final records = List.of(db.records);
      records[1] = records[1].withValue('Phonetic', 'ɸaʔeː');
      final result = reconcileIdentity(map, records, mintId: counterMinter());
      expect(result.records[1].id, map.entries[1].id);
      expect(result.records[1].rung, MatchRung.soundFile);
      // The duplicate-Reference sibling keeps its own id by content.
      expect(result.records[2].id, map.entries[2].id);
      expect(result.records[2].rung, MatchRung.contentHash);
      expect(result.vanished, isEmpty);
      expect(result.minted, isEmpty);
    });

    test('mintDkSyncId format', () {
      final id = mintDkSyncId();
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(mintDkSyncId(), isNot(id));
    });
  });
}
