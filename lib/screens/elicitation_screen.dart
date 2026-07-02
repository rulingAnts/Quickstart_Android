import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../models/wordlist_entry.dart';
import '../providers/wordlist_provider.dart';
import '../services/audio_service.dart';

class ElicitationScreen extends StatefulWidget {
  const ElicitationScreen({super.key});

  @override
  State<ElicitationScreen> createState() => _ElicitationScreenState();
}

class _ElicitationScreenState extends State<ElicitationScreen> {
  final AudioService _audioService = AudioService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    // Discard unsaved takes left over from a crash or force-close.
    _audioService.cleanTempRecordings();
  }

  @override
  void dispose() {
    _audioService.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Elicitation'),
        actions: [
          Consumer<WordlistProvider>(
            builder: (context, provider, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${provider.currentIndex + 1}/${provider.totalCount}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<WordlistProvider>(
        builder: (context, provider, child) {
          final entry = provider.currentEntry;

          if (entry == null) {
            return const Center(
              child: Text('No wordlist loaded'),
            );
          }

          return Column(
            children: [
              LinearProgressIndicator(
                value: provider.totalCount > 0
                    ? provider.completedCount / provider.totalCount
                    : 0,
              ),
              Expanded(
                // Keyed by entry id: navigating to another word rebuilds the
                // editor with that word's saved transcription and audio.
                child: _EntryEditor(
                  key: ValueKey(entry.id),
                  entry: entry,
                  provider: provider,
                  audioService: _audioService,
                  audioPlayer: _audioPlayer,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EntryEditor extends StatefulWidget {
  final WordlistEntry entry;
  final WordlistProvider provider;
  final AudioService audioService;
  final AudioPlayer audioPlayer;

  const _EntryEditor({
    super.key,
    required this.entry,
    required this.provider,
    required this.audioService,
    required this.audioPlayer,
  });

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final TextEditingController _transcriptionController;

  bool _isRecording = false;
  bool _isSaving = false;
  bool _recorderBusy = false;

  /// Audio recorded in this visit to the entry, sitting in the temp
  /// directory until saved (never overwrites the archived recording).
  String? _newAudioFilename;

  /// Audio previously saved for this entry, shown for playback.
  String? _savedAudioFilename;

  @override
  void initState() {
    super.initState();
    _transcriptionController =
        TextEditingController(text: widget.entry.localTranscription ?? '');
    _savedAudioFilename = widget.entry.audioFilename;
  }

  @override
  void dispose() {
    if (_isRecording) {
      // Leaving mid-recording discards the unfinished take.
      widget.audioService.cancelRecording();
    }
    _transcriptionController.dispose();
    super.dispose();
  }

  String? get _playableAudio => _newAudioFilename ?? _savedAudioFilename;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Reference: ${entry.reference}',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              if (entry.isCompleted)
                const Icon(Icons.check_circle, color: Colors.green),
            ],
          ),
          const SizedBox(height: 16),

          // Gloss (word to elicit), with translations when available.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Text(
                    entry.gloss,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (entry.glossIndonesian != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      entry.glossIndonesian!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                  if (entry.glossTokPisin != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      entry.glossTokPisin!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          _PictureDisplay(pictureFilename: entry.pictureFilename),

          const SizedBox(height: 24),

          _buildRecordingControls(),

          const SizedBox(height: 24),

          TextField(
            controller: _transcriptionController,
            decoration: const InputDecoration(
              labelText: 'IPA Transcription',
              hintText: 'Enter phonetic transcription...',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 20),
            maxLines: 2,
          ),

          const SizedBox(height: 16),

          if (_playableAudio != null && !_isRecording) _buildPlaybackButton(),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: widget.provider.hasPrevious && !_isSaving
                        ? _goToPrevious
                        : null,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Previous'),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveAndNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.check),
                    label: const Text(
                      'Save & Next',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Center(
            child: TextButton(
              onPressed:
                  widget.provider.hasNext && !_isSaving ? _skipWord : null,
              child: const Text('Skip without saving'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingControls() {
    return Card(
      color: _isRecording ? Colors.red.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            IconButton(
              onPressed: _toggleRecording,
              icon: Icon(
                _isRecording ? Icons.stop_circle : Icons.mic,
                size: 80,
                color: _isRecording ? Colors.red : Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isRecording
                  ? 'Recording... tap to stop'
                  : (_playableAudio != null ? 'Tap to re-record' : 'Tap to record'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaybackButton() {
    return ElevatedButton.icon(
      onPressed: _playRecording,
      icon: const Icon(Icons.play_arrow),
      label: const Text('Play Recording'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
    );
  }

  Future<void> _toggleRecording() async {
    if (_recorderBusy) return;
    _recorderBusy = true;
    try {
      if (_isRecording) {
        await _stopRecording();
      } else {
        await _startRecording();
      }
    } finally {
      _recorderBusy = false;
    }
  }

  Future<void> _startRecording() async {
    try {
      await widget.audioPlayer.stop();
      await widget.audioService.startRecording(widget.entry);
      if (!mounted) return;
      setState(() {
        _isRecording = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    final filename = await widget.audioService.stopRecording();
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      if (filename != null) {
        _newAudioFilename = filename;
      }
    });
    if (filename == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording failed — please try again')),
      );
    }
  }

  Future<void> _playRecording() async {
    final filename = _playableAudio;
    if (filename == null) return;

    try {
      // An unsaved take lives in the temp directory; saved recordings in
      // the main audio directory.
      final filePath = _newAudioFilename != null
          ? await widget.audioService.getTempAudioFilePath(filename)
          : await widget.audioService.getAudioFilePath(filename);
      if (!await File(filePath).exists()) {
        throw Exception('Audio file not found');
      }
      await widget.audioPlayer.stop();
      await widget.audioPlayer.play(DeviceFileSource(filePath));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing audio: $e')),
        );
      }
    }
  }

  Future<void> _saveAndNext() async {
    // Set synchronously so a double-tap cannot enter twice and double-save
    // or skip an entry.
    if (_isSaving) return;
    setState(() => _isSaving = true);

    var advanced = false;
    try {
      // Finish an in-progress recording so it is included in the save.
      if (_isRecording) {
        await _stopRecording();
        if (!mounted) return;
      }

      final transcription = _transcriptionController.text.trim();

      if (transcription.isEmpty && _playableAudio == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please add a transcription or recording'),
          ),
        );
        return;
      }

      // Only now does a new take replace the archived recording.
      final newTake = _newAudioFilename;
      if (newTake != null) {
        final finalized = await widget.audioService.finalizeRecording(newTake);
        if (!mounted) return;
        if (!finalized) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not save the recording — please try again'),
            ),
          );
          return;
        }
        setState(() {
          _savedAudioFilename = newTake;
          _newAudioFilename = null;
        });
      }

      final saved = await widget.provider.markCurrentAsCompleted(
        transcription: transcription,
        audioFilename: newTake ?? _savedAudioFilename,
      );
      if (!mounted) return;
      if (!saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saving failed — please try again'),
          ),
        );
        return;
      }

      if (widget.provider.hasNext) {
        advanced = true;
        widget.provider.nextEntry();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All entries completed!')),
        );
      }
    } finally {
      // Keep the button disabled when we advanced (this editor is being
      // replaced); re-enable it on validation/save failure or last entry.
      if (mounted && !advanced && _isSaving) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _goToPrevious() async {
    if (_isRecording) {
      await widget.audioService.cancelRecording();
    }
    widget.provider.previousEntry();
  }

  Future<void> _skipWord() async {
    if (_isRecording) {
      await widget.audioService.cancelRecording();
    }
    widget.provider.nextEntry();
  }
}

/// Shows the entry's picture when the referenced file exists in the app's
/// pictures directory; otherwise renders nothing.
class _PictureDisplay extends StatelessWidget {
  final String? pictureFilename;

  const _PictureDisplay({required this.pictureFilename});

  @override
  Widget build(BuildContext context) {
    final filename = pictureFilename;
    if (filename == null || filename.isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<File?>(
      future: _findPicture(filename),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              file,
              height: 200,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }

  Future<File?> _findPicture(String filename) async {
    try {
      final documents = await getApplicationDocumentsDirectory();
      final file = File('${documents.path}/pictures/$filename');
      return await file.exists() ? file : null;
    } catch (_) {
      // Pictures are optional; missing directory or plugin just hides them.
      return null;
    }
  }
}
