import 'dart:typed_data';

import 'package:dekereke_core/dekereke_core.dart';
import 'package:test/test.dart';

void main() {
  group('sniffXmlEncoding', () {
    test('detects UTF-16 LE BOM', () {
      expect(sniffXmlEncoding(Uint8List.fromList([0xFF, 0xFE, 0x3C, 0x00])),
          DekerekeEncoding.utf16le);
    });

    test('detects UTF-16 BE BOM', () {
      expect(sniffXmlEncoding(Uint8List.fromList([0xFE, 0xFF, 0x00, 0x3C])),
          DekerekeEncoding.utf16be);
    });

    test('detects UTF-8 BOM', () {
      expect(sniffXmlEncoding(Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x3C])),
          DekerekeEncoding.utf8);
    });

    test('sniffs BOM-less UTF-16 LE from < next to zero byte', () {
      expect(sniffXmlEncoding(Uint8List.fromList([0x3C, 0x00, 0x3F, 0x00])),
          DekerekeEncoding.utf16le);
    });

    test('sniffs BOM-less UTF-16 BE', () {
      expect(sniffXmlEncoding(Uint8List.fromList([0x00, 0x3C, 0x00, 0x3F])),
          DekerekeEncoding.utf16be);
    });

    test('defaults to UTF-8', () {
      expect(sniffXmlEncoding(Uint8List.fromList('<?xml'.codeUnits)),
          DekerekeEncoding.utf8);
      expect(sniffXmlEncoding(Uint8List(0)), DekerekeEncoding.utf8);
    });
  });

  group('decodeXmlBytes', () {
    test('round-trips UTF-16 LE with BOM through encodeUtf16Le', () {
      const text = '<phon_data>ɸaʔɛ — bɔdi</phon_data>';
      final bytes = encodeUtf16Le(text);
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xFE);
      expect(decodeXmlBytes(bytes), text);
    });

    test('decodes UTF-16 LE without BOM', () {
      final withBom = encodeUtf16Le('<x>ɛnɔ</x>');
      final withoutBom = Uint8List.sublistView(withBom, 2);
      expect(decodeXmlBytes(withoutBom), '<x>ɛnɔ</x>');
    });

    test('decodes UTF-16 BE with BOM', () {
      const text = '<x>a</x>';
      final bytes = <int>[0xFE, 0xFF];
      for (final unit in text.codeUnits) {
        bytes.add(unit >> 8);
        bytes.add(unit & 0xFF);
      }
      expect(decodeXmlBytes(Uint8List.fromList(bytes)), text);
    });

    test('decodes UTF-8 with and without BOM', () {
      const text = '<x>ɸaʔɛ</x>';
      final utf8Bytes = encodeUtf8NoBom(text);
      expect(decodeXmlBytes(utf8Bytes), text);
      expect(decodeXmlBytes(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8Bytes])),
          text);
    });

    test('preserves supplementary-plane characters (surrogate pairs)', () {
      const text = '<x>𝕏 𐐷</x>';
      expect(decodeXmlBytes(encodeUtf16Le(text)), text);
    });

    test('rejects odd-length UTF-16 content', () {
      expect(() => decodeXmlBytes(Uint8List.fromList([0xFF, 0xFE, 0x3C])),
          throwsFormatException);
    });
  });
}
