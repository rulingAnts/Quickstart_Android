import 'package:xml/xml.dart';

/// Deterministic XML serialization primitives.
///
/// The canonical form (see `doc/canonical_form.md`) requires byte-stable
/// output, so escaping is pinned here rather than delegated to a library
/// whose defaults could change between versions.
///
/// Text content escapes `&`, `<`, `>` (as .NET's XmlWriter — Dekereke's
/// writer — does) plus CR and LF as character references, so that a
/// serialized document contains raw newlines only *between* structural
/// lines. That makes the LF <-> CRLF conversion between canonical and
/// working form a safe whole-string operation.
String escapeXmlText(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('\r', '&#xD;')
    .replaceAll('\n', '&#xA;');

/// Escapes an attribute value quoted with [quote] (`"` or `'`).
String escapeXmlAttribute(String value, String quote) {
  final base = value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('\r', '&#xD;')
      .replaceAll('\n', '&#xA;')
      .replaceAll('\t', '&#x9;');
  return quote == '"'
      ? base.replaceAll('"', '&quot;')
      : base.replaceAll("'", '&apos;');
}

/// Normalizes CRLF (and stray CR) to LF. Applied to structural whitespace,
/// comments and CDATA when parsing into canonical form; the inverse (a
/// whole-string LF -> CRLF) happens when materializing the working format.
String normalizeNewlinesToLf(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

/// Serializes a parsed XML node back to text with LF newlines and the
/// pinned escaping rules, preserving:
///
/// - element structure, attribute order and attribute quote style,
/// - self-closing vs. open+close empty-element style,
/// - whitespace-only text nodes verbatim (modulo CRLF -> LF),
/// - comments, CDATA and processing instructions.
///
/// This is what "round-trip unknown fragments verbatim" means concretely:
/// the serialization is byte-identical to Dekereke's own output for
/// Dekereke-written fragments (verified against fixtures), and a fixed
/// point for anything else.
String serializeXmlNode(XmlNode node) {
  final buffer = StringBuffer();
  _writeNode(buffer, node);
  return buffer.toString();
}

void _writeNode(StringBuffer buffer, XmlNode node) {
  switch (node) {
    case XmlElement():
      _writeElement(buffer, node);
    case XmlText():
      final text = node.value;
      if (text.trim().isEmpty) {
        // Structural whitespace: keep verbatim so Dekereke's own layout
        // (newline + tabs) survives round-trips.
        buffer.write(normalizeNewlinesToLf(text));
      } else {
        buffer.write(escapeXmlText(text));
      }
    case XmlCDATA():
      buffer
        ..write('<![CDATA[')
        ..write(normalizeNewlinesToLf(node.value))
        ..write(']]>');
    case XmlComment():
      buffer
        ..write('<!--')
        ..write(normalizeNewlinesToLf(node.value))
        ..write('-->');
    case XmlProcessing():
      buffer.write(node.value.isEmpty
          ? '<?${node.target}?>'
          : '<?${node.target} ${node.value}?>');
    default:
      throw UnsupportedError(
          'Cannot serialize ${node.nodeType} node: ${node.toXmlString()}');
  }
}

void _writeElement(StringBuffer buffer, XmlElement element) {
  buffer.write('<${element.name.qualified}');
  for (final attribute in element.attributes) {
    final quote =
        attribute.attributeType == XmlAttributeType.SINGLE_QUOTE ? "'" : '"';
    buffer.write(' ${attribute.name.qualified}='
        '$quote${escapeXmlAttribute(attribute.value, quote)}$quote');
  }
  if (element.children.isEmpty) {
    // Dekereke writes self-closing tags with a space: `<Notes />`.
    buffer.write(
        element.isSelfClosing ? ' />' : '></${element.name.qualified}>');
  } else {
    buffer.write('>');
    for (final child in element.children) {
      _writeNode(buffer, child);
    }
    buffer.write('</${element.name.qualified}>');
  }
}
