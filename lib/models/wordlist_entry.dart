import 'dart:convert';

/// Represents a single word entry in the wordlist.
///
/// Entries are imported from Dekereke XML (`<phon_data>/<data_form>`), where
/// each record carries many fields beyond the ones this app edits. The full,
/// ordered set of original XML fields is preserved in [xmlFieldsJson] so that
/// export can round-trip the file without losing data Dekereke needs.
class WordlistEntry {
  /// Database row id. Null for entries not yet inserted, so SQLite can
  /// auto-assign one (passing an explicit id of 0 for every row was the
  /// source of import failures/duplicates).
  final int? id;

  final String reference; // 4-digit reference number (e.g., "0001")
  final String gloss; // English gloss (elicitation prompt)
  final String? glossIndonesian; // <GlossIndonesian>
  final String? glossTokPisin; // <GlossTokPisin>
  final String? category; // <Category> (N, V, ...)
  final String? semanticDomain; // <SemanticDomain>
  final String? soundFile; // Expected WAV name from <SoundFile>, e.g. "0001body.wav"
  final String? pictureFilename; // <Image_File> or <Picture>
  final String? localTranscription; // IPA transcription by native speaker
  final String? audioFilename; // Actual recorded file, e.g. "0001body.wav"
  final DateTime? recordedAt;
  final bool isCompleted;

  /// JSON-encoded ordered list of the entry's original XML fields:
  /// `[["Reference","0001"],["CAWL","1"],...]`. Null for entries that were
  /// not imported from a full Dekereke record.
  final String? xmlFieldsJson;

  WordlistEntry({
    this.id,
    required this.reference,
    required this.gloss,
    this.glossIndonesian,
    this.glossTokPisin,
    this.category,
    this.semanticDomain,
    this.soundFile,
    this.pictureFilename,
    this.localTranscription,
    this.audioFilename,
    this.recordedAt,
    this.isCompleted = false,
    this.xmlFieldsJson,
  });

  /// Original XML fields as an ordered (name, value) list, or empty if the
  /// entry has no preserved fields.
  List<MapEntry<String, String>> get xmlFields {
    if (xmlFieldsJson == null || xmlFieldsJson!.isEmpty) return const [];
    final decoded = jsonDecode(xmlFieldsJson!) as List<dynamic>;
    return decoded
        .map((f) => MapEntry((f as List)[0] as String, f[1] as String))
        .toList();
  }

  static String encodeXmlFields(List<MapEntry<String, String>> fields) {
    return jsonEncode(fields.map((f) => [f.key, f.value]).toList());
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'reference': reference,
      'gloss': gloss,
      'gloss_indonesian': glossIndonesian,
      'gloss_tok_pisin': glossTokPisin,
      'category': category,
      'semantic_domain': semanticDomain,
      'sound_file': soundFile,
      'picture_filename': pictureFilename,
      'local_transcription': localTranscription,
      'audio_filename': audioFilename,
      'recorded_at': recordedAt?.toIso8601String(),
      'is_completed': isCompleted ? 1 : 0,
      'xml_fields': xmlFieldsJson,
    };
  }

  factory WordlistEntry.fromMap(Map<String, dynamic> map) {
    return WordlistEntry(
      id: map['id'] as int?,
      reference: map['reference'] as String,
      gloss: map['gloss'] as String,
      glossIndonesian: map['gloss_indonesian'] as String?,
      glossTokPisin: map['gloss_tok_pisin'] as String?,
      category: map['category'] as String?,
      semanticDomain: map['semantic_domain'] as String?,
      soundFile: map['sound_file'] as String?,
      pictureFilename: map['picture_filename'] as String?,
      localTranscription: map['local_transcription'] as String?,
      audioFilename: map['audio_filename'] as String?,
      recordedAt: map['recorded_at'] != null
          ? DateTime.parse(map['recorded_at'] as String)
          : null,
      isCompleted: (map['is_completed'] as int? ?? 0) == 1,
      xmlFieldsJson: map['xml_fields'] as String?,
    );
  }

  /// Filename used when recording audio for this entry. Prefers the
  /// wordlist-assigned `<SoundFile>` name; otherwise builds one from the
  /// reference and a sanitized gloss per the naming convention
  /// (e.g., "0001body.wav").
  String get recordingFilename {
    if (soundFile != null && soundFile!.trim().isNotEmpty) {
      return soundFile!.trim();
    }
    return '$reference${sanitizeGlossForFilename(gloss)}.wav';
  }

  /// Lowercases, replaces spaces with periods, and strips characters that
  /// are unsafe in filenames (parentheses, slashes, quotes, ...).
  static String sanitizeGlossForFilename(String gloss) {
    final lowered = gloss.toLowerCase().replaceAll(RegExp(r'\s+'), '.');
    final cleaned = lowered.replaceAll(RegExp(r'[^a-z0-9.\-]'), '');
    // Collapse runs of periods and trim leading/trailing ones.
    return cleaned
        .replaceAll(RegExp(r'\.{2,}'), '.')
        .replaceAll(RegExp(r'^\.+|\.+$'), '');
  }

  WordlistEntry copyWith({
    int? id,
    String? reference,
    String? gloss,
    String? glossIndonesian,
    String? glossTokPisin,
    String? category,
    String? semanticDomain,
    String? soundFile,
    String? pictureFilename,
    String? localTranscription,
    String? audioFilename,
    DateTime? recordedAt,
    bool? isCompleted,
    String? xmlFieldsJson,
  }) {
    return WordlistEntry(
      id: id ?? this.id,
      reference: reference ?? this.reference,
      gloss: gloss ?? this.gloss,
      glossIndonesian: glossIndonesian ?? this.glossIndonesian,
      glossTokPisin: glossTokPisin ?? this.glossTokPisin,
      category: category ?? this.category,
      semanticDomain: semanticDomain ?? this.semanticDomain,
      soundFile: soundFile ?? this.soundFile,
      pictureFilename: pictureFilename ?? this.pictureFilename,
      localTranscription: localTranscription ?? this.localTranscription,
      audioFilename: audioFilename ?? this.audioFilename,
      recordedAt: recordedAt ?? this.recordedAt,
      isCompleted: isCompleted ?? this.isCompleted,
      xmlFieldsJson: xmlFieldsJson ?? this.xmlFieldsJson,
    );
  }
}
