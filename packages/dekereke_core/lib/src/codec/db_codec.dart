import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../model/database.dart';
import 'encoding.dart';
import 'xml_writer.dart';

/// Codec between Dekereke database files and [DekerekeDatabase], covering
/// both on-disk representations:
///
/// - **working format**: what Dekereke reads/writes — UTF-16 LE with BOM,
///   CRLF, `encoding="utf-16"` declaration;
/// - **canonical form**: what history/sync stores — UTF-8 without BOM, LF,
///   `encoding="utf-8"` declaration, deterministic rendering.
///
/// Full spec: `doc/canonical_form.md`. Key invariant: for a Dekereke-written
/// file, `encodeWorkingFile(parseDekerekeFile(bytes))` is byte-identical to
/// `bytes` (proven against the fixtures); for any parseable input the
/// composition is a fixed point after one pass.
const String canonicalXmlDeclaration =
    '<?xml version="1.0" encoding="utf-8" standalone="yes"?>';
const String workingXmlDeclaration =
    '<?xml version="1.0" encoding="utf-16" standalone="yes"?>';

/// Parses Dekereke database XML text (working or canonical — the declaration
/// is not consulted; the string is already decoded).
///
/// Throws [FormatException] if the document is not a `<phon_data>` database
/// or contains constructs Dekereke cannot have written and this codec could
/// not preserve (attributes or non-whitespace text directly on/inside
/// `<data_form>` outside of fields).
DekerekeDatabase parseDekerekeXml(String source) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(source);
  } on XmlException catch (e) {
    throw FormatException('Not well-formed XML: ${e.message}');
  }
  final root = document.rootElement;
  if (root.name.local != 'phon_data') {
    throw FormatException(
        'Expected a <phon_data> database, found <${root.name.qualified}>');
  }

  final items = <DekerekeDatabaseItem>[];
  for (final node in root.children) {
    if (node is XmlElement) {
      if (node.name.qualified == 'data_form') {
        items.add(_parseRecord(node));
      } else {
        items.add(DekerekeRawItem(serializeXmlNode(node)));
      }
    } else if (node is XmlText) {
      if (node.value.trim().isNotEmpty) {
        throw FormatException(
            'Unexpected text directly under <phon_data>: "${node.value.trim()}"');
      }
      // Structural whitespace — regenerated deterministically.
    } else if (node is XmlComment ||
        node is XmlCDATA ||
        node is XmlProcessing) {
      items.add(DekerekeRawItem(serializeXmlNode(node)));
    }
    // Other node types (doctype events don't appear as root children in
    // package:xml documents) are structural and need no preservation.
  }
  return DekerekeDatabase(items);
}

DekerekeRecord _parseRecord(XmlElement element) {
  if (element.attributes.isNotEmpty) {
    throw FormatException(
        'Unsupported attributes on <data_form>: ${element.attributes}');
  }
  final fields = <DekerekeField>[];
  for (final node in element.children) {
    if (node is XmlElement) {
      if (_isValueElement(node)) {
        fields.add(DekerekeValueField(node.name.qualified, _innerText(node)));
      } else {
        fields.add(DekerekeFragmentField(
            node.name.qualified, serializeXmlNode(node)));
      }
    } else if (node is XmlText) {
      if (node.value.trim().isNotEmpty) {
        throw FormatException(
            'Unexpected text directly under <data_form>: "${node.value.trim()}"');
      }
    } else if (node is XmlComment ||
        node is XmlCDATA ||
        node is XmlProcessing) {
      fields.add(DekerekeFragmentField(
          DekerekeFragmentField.rawNodeName, serializeXmlNode(node)));
    }
  }
  return DekerekeRecord(fields);
}

/// A column cell: no attributes and only text content (or empty).
bool _isValueElement(XmlElement element) =>
    element.attributes.isEmpty &&
    element.children.every((node) => node is XmlText);

String _innerText(XmlElement element) =>
    element.children.whereType<XmlText>().map((t) => t.value).join();

/// Renders one record as its canonical block (LF newlines, no trailing
/// newline). This exact string is also what record content hashes are
/// computed over (see `identity/`).
String renderRecordCanonical(DekerekeRecord record) {
  final buffer = StringBuffer('\t<data_form>\n');
  for (final field in record.fields) {
    switch (field) {
      case DekerekeValueField(:final name, :final value):
        if (value.isEmpty) {
          buffer.write('\t\t<$name />\n');
        } else {
          buffer.write('\t\t<$name>${escapeXmlText(value)}</$name>\n');
        }
      case DekerekeFragmentField(:final xml):
        buffer.write('\t\t$xml\n');
    }
  }
  buffer.write('\t</data_form>');
  return buffer.toString();
}

/// Renders the canonical form: UTF-8/LF text, one field per line,
/// deterministic (see `doc/canonical_form.md`).
String renderCanonicalXml(DekerekeDatabase db) {
  final buffer = StringBuffer(canonicalXmlDeclaration)..write('\n');
  if (db.items.isEmpty) {
    buffer.write('<phon_data />\n');
    return buffer.toString();
  }
  buffer.write('<phon_data>\n');
  for (final item in db.items) {
    switch (item) {
      case DekerekeRecord():
        buffer.write(renderRecordCanonical(item));
      case DekerekeRawItem(:final xml):
        buffer.write('\t$xml');
    }
    buffer.write('\n');
  }
  buffer.write('</phon_data>\n');
  return buffer.toString();
}

/// Renders the working-format text (CRLF, `utf-16` declaration). Escaped
/// values contain no raw newlines (pinned escaping), so the LF -> CRLF
/// conversion is a safe whole-string operation.
String renderWorkingXml(DekerekeDatabase db) {
  final canonical = renderCanonicalXml(db);
  final withDeclaration = workingXmlDeclaration +
      canonical.substring(canonicalXmlDeclaration.length);
  return withDeclaration.replaceAll('\n', '\r\n');
}

/// Decodes and parses a database file in either representation.
DekerekeDatabase parseDekerekeFile(Uint8List bytes) =>
    parseDekerekeXml(decodeXmlBytes(bytes));

/// Encodes the working format: UTF-16 LE with BOM — bytes Dekereke opens.
Uint8List encodeWorkingFile(DekerekeDatabase db) =>
    encodeUtf16Le(renderWorkingXml(db));

/// Encodes the canonical form: UTF-8, no BOM — bytes history/sync stores.
Uint8List encodeCanonicalFile(DekerekeDatabase db) =>
    encodeUtf8NoBom(renderCanonicalXml(db));
