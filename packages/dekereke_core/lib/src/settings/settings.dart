import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:xml/xml.dart';

import '../codec/db_codec.dart' show canonicalXmlDeclaration, workingXmlDeclaration;
import '../codec/encoding.dart';
import '../codec/xml_writer.dart';

/// `*-DkUserSettings.xml` model (plan §4.1).
///
/// Verified structure (docs/HANDOFF.md): a UTF-16 `<settings>` element whose
/// children mix **shared** configuration (column→suffix mappings, column
/// order/widths, analysis settings, display profiles, hidden columns, field
/// restrictions) with **machine-local** paths that must never sync. Some
/// Dekereke variants add elements this model has never seen — every element
/// is preserved verbatim, known or not.
///
/// Machine-local setting names, verified against two real settings variants:
const Set<String> machineLocalSettingNames = {
  'sound_file_path',
  'acoustic_analyzer_path',
  'speech_analyzer_path',
  'praat_path',
};

/// One top-level child of `<settings>`, preserved verbatim.
final class DkSettingElement {
  final String name;

  /// Canonical serialization (LF newlines, pinned escaping) of the whole
  /// element, starting at its open tag.
  final String xml;

  const DkSettingElement(this.name, this.xml);

  /// Builds a Dekereke-style simple text setting: `<name>value</name>`,
  /// self-closed when [value] is empty.
  factory DkSettingElement.text(String name, String value) => value.isEmpty
      ? DkSettingElement(name, '<$name />')
      : DkSettingElement(name, '<$name>${escapeXmlText(value)}</$name>');

  bool get isMachineLocal => machineLocalSettingNames.contains(name);

  /// The element's text content when it is a simple text setting.
  String get textValue => _parsed.innerText;

  XmlElement get _parsed => XmlDocument.parse(xml).rootElement;

  @override
  bool operator ==(Object other) =>
      other is DkSettingElement && other.name == name && other.xml == xml;

  @override
  int get hashCode => Object.hash(name, xml);

  @override
  String toString() => 'DkSettingElement($name)';
}

/// A `Column<TAB>-suffix` entry from
/// `<column_to_sound_file_suffix_mappings>`.
final class SuffixMapping {
  final String column;
  final String suffix;

  const SuffixMapping(this.column, this.suffix);

  @override
  bool operator ==(Object other) =>
      other is SuffixMapping && other.column == column && other.suffix == suffix;

  @override
  int get hashCode => Object.hash(column, suffix);

  @override
  String toString() => 'SuffixMapping($column -> $suffix)';
}

/// A `<column>` entry from `<user_column_order>`.
final class ColumnOrderEntry {
  final String name;
  final int position;
  final int width;

  const ColumnOrderEntry(this.name, {required this.position, required this.width});

  @override
  bool operator ==(Object other) =>
      other is ColumnOrderEntry &&
      other.name == name &&
      other.position == position &&
      other.width == width;

  @override
  int get hashCode => Object.hash(name, position, width);

  @override
  String toString() => 'ColumnOrderEntry($name @$position w$width)';
}

/// The result of [DkUserSettings.splitMachineLocal].
final class SettingsSplit {
  /// The syncable settings: machine-local elements present but **emptied**
  /// (structure and position preserved so re-merging is order-stable).
  final DkUserSettings shared;

  /// The machine-local elements, verbatim, keyed by name.
  final Map<String, DkSettingElement> local;

  const SettingsSplit({required this.shared, required this.local});
}

/// Parsed `DkUserSettings.xml`: the ordered children of `<settings>`.
final class DkUserSettings {
  final List<DkSettingElement> elements;

  const DkUserSettings(this.elements);

  factory DkUserSettings.parseBytes(Uint8List bytes) =>
      DkUserSettings.parse(decodeXmlBytes(bytes));

  factory DkUserSettings.parse(String source) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(source);
    } on XmlException catch (e) {
      throw FormatException('Not well-formed XML: ${e.message}');
    }
    final root = document.rootElement;
    if (root.name.local != 'settings') {
      throw FormatException(
          'Expected a <settings> document, found <${root.name.qualified}>');
    }
    final elements = <DkSettingElement>[];
    for (final node in root.children) {
      if (node is XmlElement) {
        elements.add(
            DkSettingElement(node.name.qualified, serializeXmlNode(node)));
      } else if (node is XmlText) {
        if (node.value.trim().isNotEmpty) {
          throw FormatException(
              'Unexpected text directly under <settings>: "${node.value.trim()}"');
        }
      } else if (node is XmlComment ||
          node is XmlCDATA ||
          node is XmlProcessing) {
        elements.add(DkSettingElement('#raw', serializeXmlNode(node)));
      }
    }
    return DkUserSettings(elements);
  }

  DkSettingElement? element(String name) =>
      elements.firstWhereOrNull((e) => e.name == name);

  /// The text value of a simple text setting, or null when absent.
  String? valueOf(String name) => element(name)?.textValue;

  // ---- Typed views of verified shared settings ----------------------------

  /// Column→suffix mappings; entries are TAB-separated `Column<TAB>-suffix`.
  /// Entries without a TAB are skipped (never observed; defensive).
  List<SuffixMapping> get suffixMappings {
    final container = element('column_to_sound_file_suffix_mappings');
    if (container == null) return const [];
    return container._parsed
        .findElements('column_to_sound_file_suffix_mapping')
        .map((e) => e.innerText)
        .where((entry) => entry.contains('\t'))
        .map((entry) {
      final tab = entry.indexOf('\t');
      return SuffixMapping(entry.substring(0, tab), entry.substring(tab + 1));
    }).toList();
  }

  /// The suffix for [column], or null if the column has no audio mapping.
  String? suffixForColumn(String column) =>
      suffixMappings.firstWhereOrNull((m) => m.column == column)?.suffix;

  List<ColumnOrderEntry> get columnOrder {
    final container = element('user_column_order');
    if (container == null) return const [];
    return container._parsed.findElements('column').map((column) {
      final name = column.getElement('column_name')?.innerText ?? '';
      final position =
          int.tryParse(column.getElement('column_position')?.innerText ?? '') ??
              0;
      final width =
          int.tryParse(column.getElement('column_width')?.innerText ?? '') ?? 0;
      return ColumnOrderEntry(name, position: position, width: width);
    }).toList();
  }

  List<String> get hiddenColumns => _stringList('hidden_columns', 'hidden_column');

  List<String> get analysisColumns =>
      _stringList('columns_for_phonetic_analysis', 'analysis_column');

  List<String> get bannedOnsets => _stringList('banned_onsets', 'banned_onset');

  String? get syllableDivision => valueOf('syllable_division');

  /// Machine-local audio folder (never synced).
  String? get soundFilePath => valueOf('sound_file_path');

  List<String> _stringList(String containerName, String childName) {
    final container = element(containerName);
    if (container == null) return const [];
    return container._parsed
        .findElements(childName)
        .map((e) => e.innerText)
        .toList();
  }

  // ---- Mutation (returns copies) ------------------------------------------

  /// A copy with [element] replacing the first element of the same name, or
  /// appended if absent.
  DkUserSettings withElement(DkSettingElement element) {
    final updated = List.of(elements);
    final index = updated.indexWhere((e) => e.name == element.name);
    if (index >= 0) {
      updated[index] = element;
    } else {
      updated.add(element);
    }
    return DkUserSettings(updated);
  }

  DkUserSettings withValue(String name, String value) =>
      withElement(DkSettingElement.text(name, value));

  // ---- Shared vs machine-local split (plan §4.1) ---------------------------

  /// Splits into the syncable part and the machine-local elements.
  ///
  /// The shared part keeps machine-local elements in place but **emptied**
  /// (`<sound_file_path />`): no local data leaves the machine, yet element
  /// order is preserved so [mergeMachineLocal] reassembles files stably.
  SettingsSplit splitMachineLocal() {
    final local = <String, DkSettingElement>{};
    final shared = <DkSettingElement>[];
    for (final element in elements) {
      if (element.isMachineLocal) {
        local[element.name] = element;
        shared.add(DkSettingElement.text(element.name, ''));
      } else {
        shared.add(element);
      }
    }
    return SettingsSplit(shared: DkUserSettings(shared), local: local);
  }

  /// Reassembles a machine's real settings: this (shared) settings document
  /// with [local] elements substituted back in. Local elements whose names
  /// are missing from the shared part are appended.
  DkUserSettings mergeMachineLocal(Map<String, DkSettingElement> local) {
    var merged = this;
    for (final element in local.values) {
      merged = merged.withElement(element);
    }
    return merged;
  }

  // ---- Rendering -----------------------------------------------------------

  /// Canonical rendering (UTF-8 declaration, LF) — what sync/history stores
  /// for the shared part (`settings.shared.xml`).
  String renderCanonicalXml() => _render(canonicalXmlDeclaration);

  /// Working rendering (UTF-16 declaration, CRLF) — the file Dekereke reads.
  String renderWorkingXml() =>
      _render(workingXmlDeclaration).replaceAll('\n', '\r\n');

  /// Working-format bytes: UTF-16 LE with BOM.
  Uint8List encodeWorkingFile() => encodeUtf16Le(renderWorkingXml());

  /// Canonical bytes: UTF-8, no BOM.
  Uint8List encodeCanonicalFile() => encodeUtf8NoBom(renderCanonicalXml());

  String _render(String declaration) {
    final buffer = StringBuffer(declaration)..write('\n');
    if (elements.isEmpty) {
      buffer.write('<settings />\n');
      return buffer.toString();
    }
    buffer.write('<settings>\n');
    for (final element in elements) {
      buffer
        ..write('\t')
        ..write(element.xml)
        ..write('\n');
    }
    buffer.write('</settings>\n');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is DkUserSettings &&
      const ListEquality<DkSettingElement>().equals(other.elements, elements);

  @override
  int get hashCode => const ListEquality<DkSettingElement>().hash(elements);
}
