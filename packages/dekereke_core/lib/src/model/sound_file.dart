/// SoundFile-cell helpers.
///
/// Verified (docs/HANDOFF.md): audio is WAV-only; a record's `<SoundFile>`
/// holds a base filename, and a suffix-mapped column plays
/// `<base minus .wav><suffix>.wav`. A cell may list multiple files.
///
/// UNVERIFIED (P0 #7): the exact multi-file separator syntax. Both `|` and
/// `,` are accepted here per the ground-truth notes; revisit once P0 #7 is
/// answered.
library;

final _separators = RegExp(r'[|,]');

/// Splits a raw `<SoundFile>` cell into individual filenames.
///
/// Splits on `|` and `,`, trims whitespace *around separators* only
/// (filenames legitimately contain interior spaces), and drops empty
/// entries. An empty cell yields an empty list.
List<String> splitSoundFileCell(String cell) => cell
    .split(_separators)
    .map((name) => name.trim())
    .where((name) => name.isNotEmpty)
    .toList();

/// The audio filename a suffix-mapped column plays for a given base
/// filename: `<base minus .wav><suffix>.wav`.
///
/// The `.wav` extension is matched case-insensitively (Windows filesystem
/// semantics); the suffix is appended verbatim — real suffixes are
/// irregular (`-phon`, `-tf_Xhi`, `-tf-Xko`).
String suffixedSoundFile(String baseFilename, String suffix) {
  final lower = baseFilename.toLowerCase();
  final stem = lower.endsWith('.wav')
      ? baseFilename.substring(0, baseFilename.length - 4)
      : baseFilename;
  return '$stem$suffix.wav';
}
