import 'package:flutter/foundation.dart';
import '../utils/logger.dart';
import '../models/wordlist_entry.dart';
import '../services/database_service.dart';

class WordlistProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  
  List<WordlistEntry> _entries = [];
  int _currentIndex = 0;
  bool _isLoading = false;

  List<WordlistEntry> get entries => _entries;
  WordlistEntry? get currentEntry => 
      _entries.isEmpty ? null : _entries[_currentIndex];
  int get currentIndex => _currentIndex;
  bool get isLoading => _isLoading;
  int get totalCount => _entries.length;
  int get completedCount => 
      _entries.where((e) => e.isCompleted).length;

  Future<void> loadWordlist() async {
    _isLoading = true;
    notifyListeners();

    try {
      _entries = await _db.getAllWordlistEntries();
      _currentIndex = 0;
    } catch (e, st) {
      Log.e('Error loading wordlist', e, st);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateEntry(WordlistEntry entry) async {
    try {
      await _db.updateWordlistEntry(entry);
      final index = _entries.indexWhere((e) => e.id == entry.id);
      if (index != -1) {
        _entries[index] = entry;
        notifyListeners();
      }
    } catch (e, st) {
      Log.e('Error updating entry', e, st);
    }
  }

  void setCurrentIndex(int index) {
    if (index >= 0 && index < _entries.length) {
      _currentIndex = index;
      notifyListeners();
    }
  }

  void nextEntry() {
    if (_currentIndex < _entries.length - 1) {
      _currentIndex++;
      notifyListeners();
    }
  }

  void previousEntry() {
    if (_currentIndex > 0) {
      _currentIndex--;
      notifyListeners();
    }
  }

  Future<void> markCurrentAsCompleted({
    required String transcription,
    String? audioFilename,
  }) async {
    if (currentEntry == null) return;

    final updatedEntry = currentEntry!.copyWith(
      localTranscription: transcription,
      audioFilename: audioFilename,
      recordedAt: DateTime.now(),
      isCompleted: true,
    );

    await updateEntry(updatedEntry);
  }

  Future<void> clearWordlist() async {
    await _db.deleteAllWordlistEntries();
    _entries = [];
    _currentIndex = 0;
    notifyListeners();
  }
}
