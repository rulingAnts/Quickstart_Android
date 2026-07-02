import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dekereke_core/dekereke_core.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/wordlist_entry.dart';
import '../providers/wordlist_provider.dart';
import '../services/audio_service.dart';
import '../services/database_service.dart';
import '../services/task_service.dart';

/// Editor for one entry of an active task (plan §5.4): renders exactly the
/// fields the researcher configured — visible prompts, playable reference
/// audio, and writable columns collecting text and/or audio — instead of
/// the fixed Gloss+transcription+mic layout.
class TaskEntryEditor extends StatefulWidget {
  final DekTask task;
  final WordlistEntry entry;
  final WordlistProvider provider;
  final AudioService audioService;
  final AudioPlayer audioPlayer;
  final TaskService taskService;

  const TaskEntryEditor({
    super.key,
    required this.task,
    required this.entry,
    required this.provider,
    required this.audioService,
    required this.audioPlayer,
    required this.taskService,
  });

  @override
  State<TaskEntryEditor> createState() => _TaskEntryEditorState();
}

class _TaskEntryEditorState extends State<TaskEntryEditor> {
  final DatabaseService _db = DatabaseService.instance;

  final Map<String, TextEditingController> _textControllers = {};

  /// Recordings saved in earlier visits: column → filename (in audio/).
  Map<String, String> _savedRecordings = {};

  /// Takes recorded in this visit: column → filename (still in the temp
  /// directory until saved; never overwrites an archived recording).
  final Map<String, String> _newTakes = {};

  /// Column currently being recorded, if any (one mic at a time).
  String? _recordingColumn;

  bool _loading = true;
  bool _isSaving = false;
  bool _recorderBusy = false;

  String get _dkSyncId => widget.entry.dkSyncId ?? '';

  /// The entry's original cell values, for visible-field prompts.
  late final Map<String, String> _entryValues = {
    for (final field in widget.entry.xmlFields) field.key: field.value,
  };

  List<TaskField> get _writableFields => widget.task.writableFields;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await _db.getTaskValues(_dkSyncId);
    final recordings = await _db.getTaskRecordings(_dkSyncId);
    if (!mounted) return;
    setState(() {
      for (final field in _writableFields) {
        if (field.input == TaskInputKind.text ||
            field.input == TaskInputKind.both) {
          _textControllers[field.column] =
              TextEditingController(text: values[field.column] ?? '');
        }
      }
      _savedRecordings = recordings;
      _loading = false;
    });
  }

  @override
  void dispose() {
    if (_recordingColumn != null) {
      // Leaving mid-recording discards the unfinished take.
      widget.audioService.cancelRecording();
    }
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final entry = widget.entry;
    var visibleCount = 0;

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
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              if (entry.isCompleted)
                const Icon(Icons.check_circle, color: Colors.green),
            ],
          ),
          const SizedBox(height: 16),
          for (final field in widget.task.fields) ...[
            switch (field.role) {
              TaskFieldRole.visible => _visibleCard(field, visibleCount++ == 0),
              TaskFieldRole.playable => _playableRow(field),
              TaskFieldRole.writable => _writableSection(field),
            },
            const SizedBox(height: 16),
          ],
          _PictureDisplay(pictureFilename: entry.pictureFilename),
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

  /// A read-only prompt field. The first one is the main elicitation prompt
  /// and rendered large, like the gloss in plain mode.
  Widget _visibleCard(TaskField field, bool primary) {
    final value = _entryValues[field.column] ?? '';
    if (value.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (!primary)
              Text(
                field.column,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            Text(
              value,
              textAlign: TextAlign.center,
              style: primary
                  ? const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)
                  : TextStyle(fontSize: 22, color: Colors.grey[800]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playableRow(TaskField field) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.volume_up, color: Colors.blue),
        title: Text('Listen: ${field.column}'),
        trailing: IconButton(
          icon: const Icon(Icons.play_arrow, size: 36, color: Colors.blue),
          onPressed: () => _playReference(field),
        ),
      ),
    );
  }

  Widget _writableSection(TaskField field) {
    final collectsText = field.input == TaskInputKind.text ||
        field.input == TaskInputKind.both;
    final collectsAudio = field.collectsAudio;
    final isRecordingThis = _recordingColumn == field.column;
    final take = _newTakes[field.column] ?? _savedRecordings[field.column];

    return Card(
      color: isRecordingThis ? Colors.red.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              field.column,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (collectsText) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _textControllers[field.column],
                decoration: const InputDecoration(
                  hintText: 'Type here...',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 20),
                maxLines: 2,
              ),
            ],
            if (collectsAudio) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => _toggleRecording(field),
                    icon: Icon(
                      isRecordingThis ? Icons.stop_circle : Icons.mic,
                      size: 56,
                      color: isRecordingThis ? Colors.red : Colors.blue,
                    ),
                  ),
                  if (take != null && !isRecordingThis)
                    IconButton(
                      onPressed: () => _playTake(field),
                      icon: const Icon(Icons.play_arrow,
                          size: 44, color: Colors.green),
                    ),
                ],
              ),
              Center(
                child: Text(
                  isRecordingThis
                      ? 'Recording... tap to stop'
                      : (take != null ? 'Tap mic to re-record' : 'Tap mic to record'),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _playReference(TaskField field) async {
    final cellFiles = splitSoundFileCell(widget.entry.soundFile ?? '');
    if (cellFiles.isEmpty) {
      _showMessage('No reference audio for this word');
      return;
    }
    // Multi-file cells: play the first file (v1).
    final name = suffixedSoundFile(cellFiles.first, field.suffix ?? '');
    final path = await widget.taskService.findReferenceAudio(name);
    if (!mounted) return;
    if (path == null) {
      _showMessage('This recording was not included in the task');
      return;
    }
    try {
      await widget.audioPlayer.stop();
      await widget.audioPlayer.play(DeviceFileSource(path));
    } catch (e) {
      _showMessage('Error playing audio: $e');
    }
  }

  Future<void> _toggleRecording(TaskField field) async {
    if (_recorderBusy) return;
    _recorderBusy = true;
    try {
      if (_recordingColumn == field.column) {
        final filename = await widget.audioService.stopRecording();
        if (!mounted) return;
        setState(() {
          _recordingColumn = null;
          if (filename != null) _newTakes[field.column] = filename;
        });
        if (filename == null) {
          _showMessage('Recording failed — please try again');
        }
      } else if (_recordingColumn != null) {
        _showMessage('Finish the other recording first');
      } else {
        try {
          await widget.audioPlayer.stop();
          final filename =
              widget.taskService.recordingFilenameFor(widget.entry, field);
          await widget.audioService.startRecordingAs(filename);
          if (!mounted) return;
          setState(() => _recordingColumn = field.column);
        } catch (e) {
          _showMessage('Error starting recording: $e');
        }
      }
    } finally {
      _recorderBusy = false;
    }
  }

  Future<void> _playTake(TaskField field) async {
    final newTake = _newTakes[field.column];
    final filename = newTake ?? _savedRecordings[field.column];
    if (filename == null) return;
    try {
      final path = newTake != null
          ? await widget.audioService.getTempAudioFilePath(filename)
          : await widget.audioService.getAudioFilePath(filename);
      if (!await File(path).exists()) {
        throw Exception('Audio file not found');
      }
      await widget.audioPlayer.stop();
      await widget.audioPlayer.play(DeviceFileSource(path));
    } catch (e) {
      _showMessage('Error playing audio: $e');
    }
  }

  Future<void> _saveAndNext() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    var advanced = false;
    try {
      // Finish an in-progress recording so it is included in the save.
      if (_recordingColumn != null) {
        final column = _recordingColumn!;
        final filename = await widget.audioService.stopRecording();
        if (!mounted) return;
        setState(() {
          _recordingColumn = null;
          if (filename != null) _newTakes[column] = filename;
        });
      }

      final textValues = {
        for (final entry in _textControllers.entries)
          entry.key: entry.value.text.trim(),
      };
      final hasText = textValues.values.any((v) => v.isNotEmpty);
      final hasAudio = _newTakes.isNotEmpty || _savedRecordings.isNotEmpty;
      if (!hasText && !hasAudio) {
        _showMessage('Please add an answer or a recording');
        return;
      }

      // Only now do new takes replace archived recordings.
      for (final take in Map.of(_newTakes).entries) {
        final finalized =
            await widget.audioService.finalizeRecording(take.value);
        if (!mounted) return;
        if (!finalized) {
          _showMessage('Could not save the recording — please try again');
          return;
        }
        await _db.setTaskRecording(_dkSyncId, take.key, take.value);
        setState(() {
          _savedRecordings[take.key] = take.value;
          _newTakes.remove(take.key);
        });
      }

      for (final value in textValues.entries) {
        if (value.value.isEmpty) {
          await _db.deleteTaskValue(_dkSyncId, value.key);
        } else {
          await _db.setTaskValue(_dkSyncId, value.key, value.value);
        }
      }

      final saved = await widget.provider.updateEntry(widget.entry.copyWith(
        isCompleted: true,
        recordedAt: DateTime.now(),
      ));
      if (!mounted) return;
      if (!saved) {
        _showMessage('Saving failed — please try again');
        return;
      }

      if (widget.provider.hasNext) {
        advanced = true;
        widget.provider.nextEntry();
      } else {
        _showMessage('All entries completed!');
      }
    } finally {
      if (mounted && !advanced && _isSaving) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _goToPrevious() async {
    if (_recordingColumn != null) {
      await widget.audioService.cancelRecording();
      _recordingColumn = null;
    }
    widget.provider.previousEntry();
  }

  Future<void> _skipWord() async {
    if (_recordingColumn != null) {
      await widget.audioService.cancelRecording();
      _recordingColumn = null;
    }
    widget.provider.nextEntry();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
