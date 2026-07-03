import 'dart:convert';
import 'dart:typed_data';

/// Text encodings Dekereke-related XML files appear in.
///
/// Dekereke itself writes UTF-16 little-endian with a BOM; the Companion's
/// canonical form is UTF-8 without a BOM (see `doc/canonical_form.md`).
enum DekerekeEncoding { utf8, utf16le, utf16be }

/// Detects the encoding of an XML file's bytes.
///
/// Detection order: UTF-16 LE/BE BOM, UTF-8 BOM, then a UTF-16 sniff — an
/// XML file starts with `<` (0x3C), which in UTF-16 has a zero byte next to
/// it. Everything else is assumed UTF-8 (which covers plain ASCII too).
DekerekeEncoding sniffXmlEncoding(Uint8List bytes) {
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) return DekerekeEncoding.utf16le;
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) return DekerekeEncoding.utf16be;
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return DekerekeEncoding.utf8;
  }
  if (bytes.length >= 2) {
    if (bytes[0] == 0x3C && bytes[1] == 0x00) return DekerekeEncoding.utf16le;
    if (bytes[0] == 0x00 && bytes[1] == 0x3C) return DekerekeEncoding.utf16be;
  }
  return DekerekeEncoding.utf8;
}

/// Decodes XML file bytes, honoring a UTF-16 LE/BE or UTF-8 BOM and falling
/// back to sniffing (see [sniffXmlEncoding]). The BOM is not part of the
/// returned string.
///
/// Throws [FormatException] for UTF-16 content with an odd byte length,
/// which can only be corruption.
String decodeXmlBytes(Uint8List bytes) {
  switch (sniffXmlEncoding(bytes)) {
    case DekerekeEncoding.utf16le:
      return _decodeUtf16(_stripBom(bytes, 0xFF, 0xFE), littleEndian: true);
    case DekerekeEncoding.utf16be:
      return _decodeUtf16(_stripBom(bytes, 0xFE, 0xFF), littleEndian: false);
    case DekerekeEncoding.utf8:
      final hasBom = bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF;
      return utf8.decode(hasBom ? bytes.sublist(3) : bytes);
  }
}

Uint8List _stripBom(Uint8List bytes, int b0, int b1) =>
    (bytes.length >= 2 && bytes[0] == b0 && bytes[1] == b1)
        ? Uint8List.sublistView(bytes, 2)
        : bytes;

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  if (bytes.length.isOdd) {
    throw const FormatException(
        'UTF-16 content has an odd number of bytes (file is corrupt)');
  }
  final data = ByteData.sublistView(bytes);
  final codeUnits = List<int>.generate(
    bytes.length ~/ 2,
    (i) => data.getUint16(i * 2, littleEndian ? Endian.little : Endian.big),
  );
  return String.fromCharCodes(codeUnits);
}

/// Encodes [text] as UTF-16 little-endian with a BOM — the encoding
/// Dekereke reads and writes.
Uint8List encodeUtf16Le(String text) {
  final codeUnits = text.codeUnits;
  final bytes = Uint8List(2 + codeUnits.length * 2);
  bytes[0] = 0xFF;
  bytes[1] = 0xFE;
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < codeUnits.length; i++) {
    data.setUint16(2 + i * 2, codeUnits[i], Endian.little);
  }
  return bytes;
}

/// Encodes [text] as UTF-8 without a BOM — the canonical-form encoding.
Uint8List encodeUtf8NoBom(String text) => Uint8List.fromList(utf8.encode(text));
