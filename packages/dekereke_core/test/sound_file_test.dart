import 'package:dekereke_core/dekereke_core.dart';
import 'package:test/test.dart';

void main() {
  group('splitSoundFileCell', () {
    test('single filename', () {
      expect(splitSoundFileCell('0001_body.wav'), ['0001_body.wav']);
    });

    test('pipe-separated multi-file cell (fixture record 0005)', () {
      expect(splitSoundFileCell('0005_go.wav|0005_go_alt.wav'),
          ['0005_go.wav', '0005_go_alt.wav']);
    });

    test('comma-separated multi-file cell', () {
      expect(splitSoundFileCell('a.wav, b.wav'), ['a.wav', 'b.wav']);
    });

    test('interior spaces and parentheses are part of the filename', () {
      expect(splitSoundFileCell('0002_water.fresh (00392).wav'),
          ['0002_water.fresh (00392).wav']);
      expect(splitSoundFileCell('a b.wav | c (1).wav'),
          ['a b.wav', 'c (1).wav']);
    });

    test('empty cell and stray separators yield no entries', () {
      expect(splitSoundFileCell(''), isEmpty);
      expect(splitSoundFileCell(' | '), isEmpty);
      expect(splitSoundFileCell('a.wav|'), ['a.wav']);
    });
  });

  group('suffixedSoundFile', () {
    test('applies the verified rule: base minus .wav + suffix + .wav', () {
      expect(suffixedSoundFile('0001_body.wav', '-phon'), '0001_body-phon.wav');
    });

    test('handles irregular suffix styles from real settings', () {
      expect(suffixedSoundFile('0001_body.wav', '-tf_Xhi'), '0001_body-tf_Xhi.wav');
      expect(suffixedSoundFile('0001_body.wav', '-tf-Xko'), '0001_body-tf-Xko.wav');
    });

    test('matches .wav case-insensitively (Windows semantics)', () {
      expect(suffixedSoundFile('0001_BODY.WAV', '-phon'), '0001_BODY-phon.wav');
    });

    test('filenames with spaces and parens', () {
      expect(suffixedSoundFile('0002_water.fresh (00392).wav', '-spkB'),
          '0002_water.fresh (00392)-spkB.wav');
    });

    test('base without .wav extension gets suffix appended', () {
      expect(suffixedSoundFile('0001_body', '-phon'), '0001_body-phon.wav');
    });
  });
}
