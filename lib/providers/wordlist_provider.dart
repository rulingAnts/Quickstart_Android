import 'package:flutter/foundation.dart';
import '../models/wordlist_entry.dart';
import '../services/database_service.dart';

class WordlistProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;

  List<WordlistEntry> _entries = [];
  int _currentIndex = 0;
  bool _isLoading = false;
  String? _lastError;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Async work (DB loads) can finish after the owning screen is gone;
  /// notifying then would throw.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  List<WordlistEntry> get entries => _entries;
  WordlistEntry? get currentEntry =>
      _entries.isEmpty ? null : _entries[_currentIndex];
  int get currentIndex => _currentIndex;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;
  int get totalCount => _entries.length;
  int get completedCount => _entries.where((e) => e.isCompleted).length;

  Future<void> loadWordlist() async {
    _isLoading = true;
    _lastError = null;
    _notify();

    try {
      _entries = await _db.getAllWordlistEntries();
      _currentIndex = _firstIncompleteIndex();
    } catch (e) {
      _lastError = 'Error loading wordlist: $e';
      debugPrint(_lastError);
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Index of the first entry still to be elicited, so a fieldwork session
  /// resumes where it left off. Falls back to the start when everything is
  /// complete.
  int _firstIncompleteIndex() {
    final index = _entries.indexWhere((e) => !e.isCompleted);
    return index == -1 ? 0 : index;
  }

  void jumpToFirstIncomplete() {
    if (_entries.isEmpty) return;
    _currentIndex = _firstIncompleteIndex();
    _notify();
  }

  /// Persists [entry]. Returns false (and sets [lastError]) when the write
  /// fails, so callers can avoid advancing past an unsaved word.
  Future<bool> updateEntry(WordlistEntry entry) async {
    try {
      await _db.updateWordlistEntry(entry);
      final index = _entries.indexWhere((e) => e.id == entry.id);
      if (index != -1) {
        _entries[index] = entry;
        _notify();
      }
      return true;
    } catch (e) {
      _lastError = 'Error updating entry: $e';
      debugPrint(_lastError);
      _notify();
      return false;
    }
  }

  void setCurrentIndex(int index) {
    if (index >= 0 && index < _entries.length) {
      _currentIndex = index;
      _notify();
    }
  }

  bool get hasNext => _currentIndex < _entries.length - 1;
  bool get hasPrevious => _currentIndex > 0;

  void nextEntry() {
    if (hasNext) {
      _currentIndex++;
      _notify();
    }
  }

  void previousEntry() {
    if (hasPrevious) {
      _currentIndex--;
      _notify();
    }
  }

  /// Saves the current entry's collected data. Pass the audio filename that
  /// should be stored; existing audio is kept when [audioFilename] is null.
  /// Returns false when the write fails.
  Future<bool> markCurrentAsCompleted({
    required String transcription,
    String? audioFilename,
  }) async {
    final entry = currentEntry;
    if (entry == null) return false;

    final updatedEntry = entry.copyWith(
      localTranscription: transcription,
      audioFilename: audioFilename ?? entry.audioFilename,
      recordedAt: DateTime.now(),
      isCompleted: true,
    );

    return updateEntry(updatedEntry);
  }

  Future<void> clearWordlist() async {
    await _db.deleteAllWordlistEntries();
    _entries = [];
    _currentIndex = 0;
    _notify();
  }
}
