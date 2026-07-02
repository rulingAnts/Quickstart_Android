import 'dart:io';
import 'dart:typed_data';

import 'package:dekereke_core/dekereke_core.dart';
import 'package:test/test.dart';

Uint8List bytesOf(List<int> data) => Uint8List.fromList(data);

void main() {
  final blobA = bytesOf([1, 1, 1]);
  final blobB = bytesOf([2, 2]);
  final hashA = sha256OfBytes(blobA);
  final hashB = sha256OfBytes(blobB);

  group('MemoryBlobStore', () {
    test('put/get round-trip with verification', () async {
      final store = MemoryBlobStore();
      await store.put(hashA, blobA);
      expect(await store.contains(hashA), isTrue);
      expect(await store.get(hashA), blobA);
      expect(await store.list(), {hashA});
    });

    test('put rejects a wrong hash; get rejects corruption', () async {
      final store = MemoryBlobStore();
      expect(() => store.put(hashA, blobB),
          throwsA(isA<BlobCorruptException>()));
      await store.put(hashA, blobA);
      store.corrupt(hashA, blobB);
      expect(() => store.get(hashA), throwsA(isA<BlobCorruptException>()));
    });

    test('missing blob throws BlobNotFound', () {
      expect(() => MemoryBlobStore().get(hashA),
          throwsA(isA<BlobNotFoundException>()));
    });
  });

  group('FileBlobStore', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('blob_store_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('put/get/list round-trip; idempotent put; no .part leftovers',
        () async {
      final store = FileBlobStore(tempDir);
      await store.put(hashA, blobA);
      await store.put(hashA, blobA); // idempotent
      await store.put(hashB, blobB);
      expect(await store.get(hashA), blobA);
      expect(await store.list(), {hashA, hashB});
      final names = [
        await for (final f in tempDir.list()) f.uri.pathSegments.last
      ];
      expect(names.where((n) => n.endsWith('.part')), isEmpty);
    });

    test('detects on-disk corruption', () async {
      final store = FileBlobStore(tempDir);
      await store.put(hashA, blobA);
      await File('${tempDir.path}/$hashA').writeAsBytes(blobB);
      expect(() => store.get(hashA), throwsA(isA<BlobCorruptException>()));
    });

    test('ignores foreign files in the directory and rejects bad keys',
        () async {
      final store = FileBlobStore(tempDir);
      await tempDir.create(recursive: true);
      await File('${tempDir.path}/notes.txt').writeAsString('x');
      expect(await store.list(), isEmpty);
      expect(() => store.get('../escape'), throwsArgumentError);
    });

    test('empty/missing directory lists empty', () async {
      final store = FileBlobStore(Directory('${tempDir.path}/nope'));
      expect(await store.list(), isEmpty);
    });
  });

  group('planAudioSync', () {
    test('classifies uploads, downloads and unavailable blobs', () {
      final plan = planAudioSync(
        wanted: {'a', 'b', 'c', 'd'},
        localHashes: {'a', 'b'},
        remoteHashes: {'a', 'c'},
      );
      expect(plan.toUpload, ['b']);
      expect(plan.toDownload, ['c']);
      expect(plan.unavailable, ['d']);
      expect(plan.isNoop, isFalse);
    });

    test('in-sync stores plan a no-op', () {
      final plan = planAudioSync(
        wanted: {'a'},
        localHashes: {'a'},
        remoteHashes: {'a'},
      );
      expect(plan.isNoop, isTrue);
    });

    test('blobs outside the manifest are never moved', () {
      final plan = planAudioSync(
        wanted: {'a'},
        localHashes: {'a', 'stray-local'},
        remoteHashes: {'a', 'stray-remote'},
      );
      expect(plan.isNoop, isTrue);
    });
  });

  group('runAudioSync', () {
    test('moves exactly the planned blobs, both directions', () async {
      final local = MemoryBlobStore();
      final remote = MemoryBlobStore();
      await local.put(hashA, blobA);
      await remote.put(hashB, blobB);

      final plan = planAudioSync(
        wanted: {hashA, hashB},
        localHashes: await local.list(),
        remoteHashes: await remote.list(),
      );
      await runAudioSync(plan, local: local, remote: remote);

      expect(await local.list(), {hashA, hashB});
      expect(await remote.list(), {hashA, hashB});
      expect(await remote.get(hashA), blobA);
      expect(await local.get(hashB), blobB);
    });

    test('corruption aborts the sync instead of spreading', () async {
      final local = MemoryBlobStore();
      final remote = MemoryBlobStore();
      await local.put(hashA, blobA);
      local.corrupt(hashA, blobB);

      final plan = planAudioSync(
        wanted: {hashA},
        localHashes: await local.list(),
        remoteHashes: await remote.list(),
      );
      await expectLater(runAudioSync(plan, local: local, remote: remote),
          throwsA(isA<BlobCorruptException>()));
      expect(await remote.contains(hashA), isFalse);
    });
  });

  group('buildManifest', () {
    test('hashes a folder into manifest stats', () {
      final manifest = buildManifest({
        '0001_body.wav': blobA,
        '0002_water.wav': blobB,
      });
      expect(manifest.files['0001_body.wav'],
          AudioFileStat(sha256: hashA, bytes: 3));
      expect(manifest.files['0002_water.wav'],
          AudioFileStat(sha256: hashB, bytes: 2));
    });
  });
}
