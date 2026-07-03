import 'package:dekereke_core/dekereke_core.dart';
import 'package:test/test.dart';

const statA = AudioFileStat(sha256: 'aaaa', bytes: 100);
const statB = AudioFileStat(sha256: 'bbbb', bytes: 200);
const statC = AudioFileStat(sha256: 'cccc', bytes: 300);
const statD = AudioFileStat(sha256: 'dddd', bytes: 400);

void main() {
  group('JSON', () {
    test('round-trips and is deterministic regardless of insertion order', () {
      final one = AudioManifest({
        '0002_water.fresh (00392).wav': statB,
        '0001_body.wav': statA,
      });
      final other = AudioManifest({
        '0001_body.wav': statA,
        '0002_water.fresh (00392).wav': statB,
      });
      expect(one.toJson(), other.toJson(),
          reason: 'filenames must be emitted sorted');
      expect(AudioManifest.fromJson(one.toJson()), one);
    });

    test('rejects foreign and future files', () {
      expect(() => AudioManifest.fromJson('{"format":"x"}'),
          throwsFormatException);
      expect(
          () => AudioManifest.fromJson(
              '{"format":"deksync-audio-manifest","version":99,"files":{}}'),
          throwsFormatException);
    });
  });

  group('dedupe report', () {
    test('groups filenames sharing content', () {
      final manifest = AudioManifest({
        'a.wav': statA,
        'copy of a.wav': statA,
        'b.wav': statB,
      });
      expect(manifest.duplicateGroups(), {
        'aaaa': ['a.wav', 'copy of a.wav'],
      });
    });
  });

  group('diff', () {
    test('added / removed / changed', () {
      final before = AudioManifest({'keep.wav': statA, 'gone.wav': statB, 're.wav': statC});
      final after = AudioManifest({'keep.wav': statA, 'new.wav': statD, 're.wav': statB});
      final diff = diffManifests(before, after);
      expect(diff.added, ['new.wav']);
      expect(diff.removed, ['gone.wav']);
      expect(diff.changed, ['re.wav']);
      expect(diffManifests(before, before).isEmpty, isTrue);
    });
  });

  group('three-way merge', () {
    final base = AudioManifest({'a.wav': statA, 'b.wav': statB});

    test('append-mostly reality: both sides add different takes', () {
      final ours = AudioManifest({...base.files, 'mine.wav': statC});
      final theirs = AudioManifest({...base.files, 'chris.wav': statD});
      final result = mergeManifests(base: base, ours: ours, theirs: theirs);
      expect(result.isClean, isTrue);
      expect(result.merged.files.keys.toSet(),
          {'a.wav', 'b.wav', 'mine.wav', 'chris.wav'});
      expect(result.addedByOurs, ['mine.wav']);
      expect(result.addedByTheirs, ['chris.wav']);
    });

    test('one-sided re-record wins', () {
      final ours = AudioManifest({'a.wav': statC, 'b.wav': statB});
      final result = mergeManifests(base: base, ours: ours, theirs: base);
      expect(result.isClean, isTrue);
      expect(result.merged.files['a.wav'], statC);
    });

    test('same re-record on both sides agrees', () {
      final same = AudioManifest({'a.wav': statC, 'b.wav': statB});
      final result = mergeManifests(base: base, ours: same, theirs: same);
      expect(result.isClean, isTrue);
      expect(result.merged.files['a.wav'], statC);
    });

    test('re-record conflict: keep both, rename incoming', () {
      final ours = AudioManifest({'a.wav': statC, 'b.wav': statB});
      final theirs = AudioManifest({'a.wav': statD, 'b.wav': statB});
      final result = mergeManifests(base: base, ours: ours, theirs: theirs);
      expect(result.conflicts, hasLength(1));
      final conflict = result.conflicts.single;
      expect(conflict.filename, 'a.wav');
      expect(conflict.baseStat, statA);
      expect(result.merged.files['a.wav'], statC,
          reason: 'ours provisionally');

      final resolved =
          resolveKeepBoth(result.merged, conflict, 'a (from Chris).wav');
      expect(resolved.files['a.wav'], statC);
      expect(resolved.files['a (from Chris).wav'], statD);

      expect(() => resolveKeepBoth(result.merged, conflict, 'b.wav'),
          throwsArgumentError,
          reason: 'rename must not clobber different content');
    });

    test('both added same name with different content: conflict, no base', () {
      final ours = AudioManifest({...base.files, 'new.wav': statC});
      final theirs = AudioManifest({...base.files, 'new.wav': statD});
      final result = mergeManifests(base: base, ours: ours, theirs: theirs);
      expect(result.conflicts.single.baseStat, isNull);
    });

    test('removal is never implicit', () {
      final theirs = AudioManifest({'a.wav': statA});
      final result = mergeManifests(base: base, ours: base, theirs: theirs);
      expect(result.merged.files.containsKey('b.wav'), isTrue);
      final pending = result.pendingRemovals.single;
      expect(pending.filename, 'b.wav');
      expect(pending.removedBy, MergeSide.theirs);
      expect(pending.modifiedBySurvivingSide, isFalse);

      final applied = applyConfirmedRemovals(result.merged, {'b.wav'});
      expect(applied.files.keys, ['a.wav']);
    });

    test('remove vs re-record is flagged', () {
      final ours = AudioManifest({'a.wav': statA, 'b.wav': statC}); // re-recorded b
      final theirs = AudioManifest({'a.wav': statA}); // removed b
      final result = mergeManifests(base: base, ours: ours, theirs: theirs);
      final pending = result.pendingRemovals.single;
      expect(pending.modifiedBySurvivingSide, isTrue);
      expect(pending.stat, statC);
    });

    test('removed on both sides: agreed, out of merged, reported', () {
      final oneLess = AudioManifest({'a.wav': statA});
      final result = mergeManifests(base: base, ours: oneLess, theirs: oneLess);
      expect(result.merged.files.containsKey('b.wav'), isFalse);
      expect(result.pendingRemovals.single.removedBy, MergeSide.both);
    });
  });
}
