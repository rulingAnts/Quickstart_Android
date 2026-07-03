/// Content-addressed blob storage (plan §4.4, decision D5).
///
/// Audio bytes live in the OWNER's storage under their SHA-256 — immutable,
/// append-only, hash-named. This interface is what the sync engine talks
/// to; Google Drive and owner-R2 become drop-in implementations on the
/// desktop side, while [MemoryBlobStore] and [FileBlobStore] cover tests,
/// the local cache and USB seeding.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'manifest.dart';

/// Lowercase-hex SHA-256 of [bytes] — the blob key and R2/Drive object name.
String sha256OfBytes(List<int> bytes) => sha256.convert(bytes).toString();

final class BlobNotFoundException implements Exception {
  final String hash;
  const BlobNotFoundException(this.hash);

  @override
  String toString() => 'BlobNotFoundException($hash)';
}

/// Thrown when stored bytes do not hash to their key (corruption in
/// transit or at rest) — never ignored, never auto-repaired.
final class BlobCorruptException implements Exception {
  final String expectedHash;
  final String actualHash;
  const BlobCorruptException(this.expectedHash, this.actualHash);

  @override
  String toString() =>
      'BlobCorruptException(expected $expectedHash, got $actualHash)';
}

abstract interface class BlobStore {
  Future<bool> contains(String hash);

  /// Stores [bytes] under [hash]. Verifies the hash first (a mismatch is a
  /// caller bug or corruption) and is idempotent — re-putting an existing
  /// blob is a no-op.
  Future<void> put(String hash, Uint8List bytes);

  /// Returns the blob, verifying its content hash on the way out.
  Future<Uint8List> get(String hash);

  /// Every hash present in the store.
  Future<Set<String>> list();
}

/// In-memory store (tests, dry runs).
final class MemoryBlobStore implements BlobStore {
  final Map<String, Uint8List> _blobs = {};

  @override
  Future<bool> contains(String hash) async => _blobs.containsKey(hash);

  @override
  Future<void> put(String hash, Uint8List bytes) async {
    final actual = sha256OfBytes(bytes);
    if (actual != hash) throw BlobCorruptException(hash, actual);
    _blobs.putIfAbsent(hash, () => Uint8List.fromList(bytes));
  }

  @override
  Future<Uint8List> get(String hash) async {
    final bytes = _blobs[hash];
    if (bytes == null) throw BlobNotFoundException(hash);
    final actual = sha256OfBytes(bytes);
    if (actual != hash) throw BlobCorruptException(hash, actual);
    return Uint8List.fromList(bytes);
  }

  @override
  Future<Set<String>> list() async => _blobs.keys.toSet();

  /// Test hook: silently corrupt a stored blob.
  void corrupt(String hash, Uint8List bytes) => _blobs[hash] = bytes;
}

/// Flat directory of hash-named files — the local blob cache, and the
/// import-from-folder/USB seeding path.
final class FileBlobStore implements BlobStore {
  final Directory directory;

  const FileBlobStore(this.directory);

  File _fileFor(String hash) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw ArgumentError.value(hash, 'hash', 'not a lowercase sha256');
    }
    return File('${directory.path}/$hash');
  }

  @override
  Future<bool> contains(String hash) => _fileFor(hash).exists();

  @override
  Future<void> put(String hash, Uint8List bytes) async {
    final actual = sha256OfBytes(bytes);
    if (actual != hash) throw BlobCorruptException(hash, actual);
    final file = _fileFor(hash);
    if (await file.exists()) return;
    await directory.create(recursive: true);
    // Write-then-rename so a crash never leaves a half-written blob under
    // its final name.
    final temp = File('${file.path}.part');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<Uint8List> get(String hash) async {
    final file = _fileFor(hash);
    if (!await file.exists()) throw BlobNotFoundException(hash);
    final bytes = await file.readAsBytes();
    final actual = sha256OfBytes(bytes);
    if (actual != hash) throw BlobCorruptException(hash, actual);
    return bytes;
  }

  @override
  Future<Set<String>> list() async {
    if (!await directory.exists()) return {};
    final hashes = <String>{};
    await for (final entry in directory.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(name)) hashes.add(name);
    }
    return hashes;
  }
}

/// What has to move so both sides hold every blob the manifest names.
final class AudioSyncPlan {
  /// Hashes to copy local → remote.
  final List<String> toUpload;

  /// Hashes to copy remote → local.
  final List<String> toDownload;

  /// Hashes the manifest names that NEITHER side has — usually a blob a
  /// third machine hasn't pushed yet; surfaced, never silently dropped.
  final List<String> unavailable;

  const AudioSyncPlan({
    required this.toUpload,
    required this.toDownload,
    required this.unavailable,
  });

  bool get isNoop =>
      toUpload.isEmpty && toDownload.isEmpty && unavailable.isEmpty;
}

/// Plans a sync for [wanted] (the manifest's hash set) between two stores.
/// Pure set arithmetic — sorted output for determinism.
AudioSyncPlan planAudioSync({
  required Set<String> wanted,
  required Set<String> localHashes,
  required Set<String> remoteHashes,
}) {
  final toUpload = wanted
      .where((h) => localHashes.contains(h) && !remoteHashes.contains(h))
      .toList()
    ..sort();
  final toDownload = wanted
      .where((h) => !localHashes.contains(h) && remoteHashes.contains(h))
      .toList()
    ..sort();
  final unavailable = wanted
      .where((h) => !localHashes.contains(h) && !remoteHashes.contains(h))
      .toList()
    ..sort();
  return AudioSyncPlan(
    toUpload: toUpload,
    toDownload: toDownload,
    unavailable: unavailable,
  );
}

/// Executes [plan]: copies blobs both ways with hash verification at each
/// hop (both stores verify on put/get). Returns the plan for chaining.
Future<AudioSyncPlan> runAudioSync(
  AudioSyncPlan plan, {
  required BlobStore local,
  required BlobStore remote,
}) async {
  for (final hash in plan.toUpload) {
    await remote.put(hash, await local.get(hash));
  }
  for (final hash in plan.toDownload) {
    await local.put(hash, await remote.get(hash));
  }
  return plan;
}

/// Seeding/import helper: hashes a folder's files into an [AudioManifest]
/// (filename → {sha256, bytes}).
AudioManifest buildManifest(Map<String, List<int>> files) => AudioManifest({
      for (final entry in files.entries)
        entry.key: AudioFileStat(
          sha256: sha256OfBytes(entry.value),
          bytes: entry.value.length,
        ),
    });
