import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/wordlist_entry.dart';

/// Records elicitation audio safely: new takes are written to a temporary
/// directory (`audio/tmp/`) and only moved over the archived WAV in
/// `audio/` when the entry is saved. Cancelling or navigating away discards
/// the temporary take and can never touch a previously saved recording.
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentRecordingPath;

  /// Request microphone permission
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<Directory> _audioDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${directory.path}/audio');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    return audioDir;
  }

  /// Where in-progress (unsaved) takes live. Kept inside audio/ but in a
  /// subdirectory so exports (which list only files in audio/) skip it.
  Future<Directory> _tempDirectory() async {
    final audioDir = await _audioDirectory();
    final tempDir = Directory('${audioDir.path}/tmp');
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    return tempDir;
  }

  /// Start recording a take for a wordlist entry. Returns the filename the
  /// take will be saved as once finalized (e.g. "0001body.wav" — the
  /// wordlist's assigned `<SoundFile>` name when available).
  Future<String> startRecording(WordlistEntry entry) async {
    return _start(entry.recordingFilename);
  }

  /// Start recording a take under an explicit filename — task mode names
  /// takes by the task's suffix assignment (`<base><suffix>.wav`).
  Future<String> startRecordingAs(String filename) async {
    return _start(filename);
  }

  /// Start recording a verbal consent statement.
  Future<String> startConsentRecording() async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return _start('consent_$timestamp.wav');
  }

  Future<String> _start(String filename) async {
    if (!await requestPermission()) {
      throw Exception('Microphone permission denied');
    }

    final tempDir = await _tempDirectory();
    _currentRecordingPath = '${tempDir.path}/$filename';

    // 16-bit PCM WAV, 44.1 kHz mono, per the export spec.
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: _currentRecordingPath!,
    );

    return filename;
  }

  /// Stop recording. Returns the take's filename (still in the temp
  /// directory — call [finalizeRecording] to keep it), or null if nothing
  /// was recorded or the file was not written.
  Future<String?> stopRecording() async {
    final path = await _recorder.stop() ?? _currentRecordingPath;
    _currentRecordingPath = null;
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) return null;
    return file.uri.pathSegments.last;
  }

  /// Move a stopped take from the temp directory over the archived
  /// recording. Only called from save paths, so an archived WAV is never
  /// touched until the user commits. Returns true on success (or when the
  /// take was already finalized, so retries after a failed DB save work).
  Future<bool> finalizeRecording(String filename) async {
    final tempDir = await _tempDirectory();
    final audioDir = await _audioDirectory();
    final source = File('${tempDir.path}/$filename');
    final destination = File('${audioDir.path}/$filename');

    if (!await source.exists()) {
      return destination.exists();
    }
    try {
      await source.rename(destination.path);
      return true;
    } on FileSystemException {
      // Cross-device fallback; same filesystem in practice.
      try {
        await source.copy(destination.path);
        await source.delete();
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  /// Check if currently recording
  Future<bool> isRecording() async {
    return await _recorder.isRecording();
  }

  /// Cancel and discard the current take. Only the temp file is deleted;
  /// archived recordings are never affected.
  Future<void> cancelRecording() async {
    final path = _currentRecordingPath;
    _currentRecordingPath = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // Nothing to stop.
    }
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// Remove leftover unsaved takes (e.g. after a crash or force-close).
  Future<void> cleanTempRecordings() async {
    final tempDir = await _tempDirectory();
    await for (final file in tempDir.list()) {
      if (file is File) {
        try {
          await file.delete();
        } catch (_) {
          // Best effort; stale files are harmless.
        }
      }
    }
  }

  /// Dispose the recorder
  Future<void> dispose() async {
    await _recorder.dispose();
  }

  /// Full path to an archived (saved) recording.
  Future<String> getAudioFilePath(String filename) async {
    final audioDir = await _audioDirectory();
    return '${audioDir.path}/$filename';
  }

  /// Full path to an unsaved take in the temp directory.
  Future<String> getTempAudioFilePath(String filename) async {
    final tempDir = await _tempDirectory();
    return '${tempDir.path}/$filename';
  }

  /// Whether an archived recording exists for [filename].
  Future<bool> audioFileExists(String filename) async {
    return File(await getAudioFilePath(filename)).exists();
  }
}
