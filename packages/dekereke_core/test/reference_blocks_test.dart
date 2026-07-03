import 'package:dekereke_core/dekereke_core.dart';
import 'package:test/test.dart';

void main() {
  group('grantBlock', () {
    test('first grant clears existing data and lands on a thousands start', () {
      // Database already numbers up to 1066 (like the real Fayu DB).
      final allocation =
          const ReferenceAllocation().grantBlock('seth', floor: 1066);
      final block = allocation.blocks.single;
      expect(block.start, 2001);
      expect(block.end, 3000);
      expect(block.ownerId, 'seth');
    });

    test('subsequent grants stack above every existing block', () {
      final allocation = const ReferenceAllocation()
          .grantBlock('seth', floor: 1066)
          .grantBlock('chris')
          .grantBlock('seth');
      expect(allocation.blocks.map((b) => b.start), [2001, 3001, 4001]);
      expect(allocation.blocksOf('seth').map((b) => b.start), [2001, 4001]);
    });

    test('empty database grants from 1', () {
      final block = const ReferenceAllocation().grantBlock('a').blocks.single;
      expect(block.start, 1);
      expect(block.end, 1000);
    });

    test('custom sizes keep the ≡1 (mod size) rule', () {
      final allocation =
          const ReferenceAllocation().grantBlock('a', size: 100, floor: 250);
      expect(allocation.blocks.single.start, 301);
    });

    test('rejects nonsense sizes', () {
      expect(() => const ReferenceAllocation().grantBlock('a', size: 0),
          throwsArgumentError);
    });
  });

  group('nextReference', () {
    test('assigns the first free number in the local block, padded', () {
      final allocation =
          const ReferenceAllocation().grantBlock('seth', floor: 100);
      expect(allocation.nextReference('seth', {}), '1001');
      expect(allocation.nextReference('seth', {'1001', '1002'}), '1003');
    });

    test('used labels match numerically regardless of padding', () {
      final allocation = const ReferenceAllocation().grantBlock('a');
      expect(allocation.nextReference('a', {'0001', '2', ' 3 '}), '0004');
    });

    test('scans multiple blocks in grant order and reports exhaustion', () {
      var allocation = const ReferenceAllocation()
          .grantBlock('a', size: 2)
          .grantBlock('a', size: 2);
      expect(allocation.blocks.map((b) => b.start), [1, 3]);
      expect(allocation.nextReference('a', {'0001', '0002', '0003'}), '0004');
      expect(allocation.nextReference('a', {'0001', '0002', '0003', '0004'}),
          isNull,
          reason: 'null = grant a new block');
    });

    test('another owner never assigns from a foreign block', () {
      final allocation = const ReferenceAllocation().grantBlock('a');
      expect(allocation.nextReference('b', {}), isNull);
    });

    test('numbers wider than the pad width use their natural digits', () {
      final allocation = const ReferenceAllocation()
          .grantBlock('a', floor: 99999);
      expect(allocation.nextReference('a', {}), '100001');
    });
  });

  group('JSON', () {
    test('round-trips deterministically', () {
      final allocation = const ReferenceAllocation()
          .grantBlock('seth', floor: 1066)
          .grantBlock('chris');
      final json = allocation.toJson();
      expect(ReferenceAllocation.fromJson(json), allocation);
      expect(ReferenceAllocation.fromJson(json).toJson(), json);
    });

    test('rejects foreign and future files', () {
      expect(() => ReferenceAllocation.fromJson('{"format":"x"}'),
          throwsFormatException);
      expect(
          () => ReferenceAllocation.fromJson(
              '{"format":"deksync-reference-blocks","version":99,"blocks":[]}'),
          throwsFormatException);
    });
  });
}
