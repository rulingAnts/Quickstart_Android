import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/wordlist_entry.dart';

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

  /// Start recording audio for a wordlist entry. Returns the filename the
  /// recording will be saved as (e.g. "0001body.wav" — the wordlist's
  /// assigned `<SoundFile>` name when available).
  Future<String> startRecording(WordlistEntry entry) async {
    return _start(entry.recordingFilename);
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

    final audioDir = await _audioDirectory();
    _currentRecordingPath = '${audioDir.path}/$filename';

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

  /// Stop recording. Returns the saved filename, or null if nothing was
  /// recorded or the file was not written.
  Future<String?> stopRecording() async {
    final path = await _recorder.stop() ?? _currentRecordingPath;
    _currentRecordingPath = null;
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) return null;
    return file.uri.pathSegments.last;
  }

  /// Check if currently recording
  Future<bool> isRecording() async {
    return await _recorder.isRecording();
  }

  /// Cancel and discard the current recording.
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

  /// Dispose the recorder
  Future<void> dispose() async {
    await _recorder.dispose();
  }

  /// Get the full path to an audio file by filename
  Future<String> getAudioFilePath(String filename) async {
    final audioDir = await _audioDirectory();
    return '${audioDir.path}/$filename';
  }

  /// Whether a recording exists for [filename].
  Future<bool> audioFileExists(String filename) async {
    return File(await getAudioFilePath(filename)).exists();
  }
}
