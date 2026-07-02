/// Shared by the kit generators: audible 16-bit mono WAV test tones.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// A 0.4 s, 44.1 kHz, 16-bit mono sine WAV with fade-in/out (no clicks).
Uint8List sineWav(double frequency) {
  const sampleRate = 44100;
  const seconds = 0.4;
  final sampleCount = (sampleRate * seconds).round();
  final dataBytes = sampleCount * 2;

  final bytes = Uint8List(44 + dataBytes);
  final data = ByteData.sublistView(bytes);

  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes[offset + i] = text.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  data.setUint16(32, 2, Endian.little); // block align
  data.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  data.setUint32(40, dataBytes, Endian.little);

  const fadeSamples = 1000;
  for (var i = 0; i < sampleCount; i++) {
    var amplitude = 0.6;
    if (i < fadeSamples) amplitude *= i / fadeSamples;
    if (i > sampleCount - fadeSamples) {
      amplitude *= (sampleCount - i) / fadeSamples;
    }
    final sample =
        (math.sin(2 * math.pi * frequency * i / sampleRate) * amplitude * 32767)
            .round();
    data.setInt16(44 + i * 2, sample, Endian.little);
  }
  return bytes;
}
