import 'package:collection/collection.dart';

/// One field of a Dekereke record.
///
/// Two kinds exist (see `doc/canonical_form.md` §record model):
///
/// - [DekerekeValueField]: a plain column cell — an element containing only
///   text (or nothing). Presence-only booleans like `<loan />` are value
///   fields with an empty value; their *presence* carries the meaning.
/// - [DekerekeFragmentField]: anything else (an element with child elements,
///   attributes, CDATA…), e.g. QuickVPlot's nested `<qvp_acoustic_data_>`.
///   Preserved as raw XML and round-tripped verbatim.
sealed class DekerekeField {
  final String name;
  const DekerekeField(this.name);
}

final class DekerekeValueField extends DekerekeField {
  /// Exact text content: never trimmed, whitespace runs preserved.
  final String value;

  const DekerekeValueField(super.name, this.value);

  @override
  bool operator ==(Object other) =>
      other is DekerekeValueField && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);

  @override
  String toString() => 'DekerekeValueField($name: ${value.isEmpty ? '<empty>' : value})';
}

final class DekerekeFragmentField extends DekerekeField {
  /// Canonical serialization of the fragment (LF newlines, pinned escaping —
  /// see `serializeXmlNode`). Starts at the fragment's own open tag; the
  /// record renderer supplies surrounding indentation.
  ///
  /// Non-element nodes that appear directly inside a record (comments,
  /// CDATA, processing instructions) are also preserved as fragments, under
  /// the reserved name [rawNodeName].
  final String xml;

  const DekerekeFragmentField(super.name, this.xml);

  /// Reserved [name] for preserved non-element nodes inside a record.
  static const rawNodeName = '#raw';

  @override
  bool operator ==(Object other) =>
      other is DekerekeFragmentField && other.name == name && other.xml == xml;

  @override
  int get hashCode => Object.hash(name, xml);

  @override
  String toString() => 'DekerekeFragmentField($name)';
}

/// A top-level child of `<phon_data>`: either a record or (defensively)
/// any unknown node preserved verbatim.
sealed class DekerekeDatabaseItem {
  const DekerekeDatabaseItem();
}

/// An unknown top-level node under `<phon_data>` (Dekereke writes only
/// `<data_form>` children, but unknown content must survive round-trips).
final class DekerekeRawItem extends DekerekeDatabaseItem {
  /// Canonical serialization (LF newlines), starting at the node itself.
  final String xml;

  const DekerekeRawItem(this.xml);

  @override
  bool operator ==(Object other) => other is DekerekeRawItem && other.xml == xml;

  @override
  int get hashCode => xml.hashCode;
}

/// One `<data_form>` record: an ordered list of fields.
///
/// Field order is preserved exactly as in the file. Dekereke column names
/// are case-sensitive and normally unique per record, but this model does
/// not enforce uniqueness (the format doesn't either).
final class DekerekeRecord extends DekerekeDatabaseItem {
  final List<DekerekeField> fields;

  const DekerekeRecord(this.fields);

  /// The value of the first [DekerekeValueField] named [name], or null if
  /// the field is absent (note: an *empty present* field returns `''`,
  /// which is distinct from absent — presence-only booleans rely on this).
  String? valueOf(String name) => fields
      .whereType<DekerekeValueField>()
      .firstWhereOrNull((f) => f.name == name)
      ?.value;

  bool hasField(String name) => fields.any((f) => f.name == name);

  String get reference => valueOf('Reference') ?? '';
  String get gloss => valueOf('Gloss') ?? '';

  /// The raw `<SoundFile>` cell (may name multiple files — see
  /// `sound_file.dart`).
  String get soundFileCell => valueOf('SoundFile') ?? '';

  /// A copy with the first value field named [name] set to [value], or the
  /// field appended if absent.
  DekerekeRecord withValue(String name, String value) {
    final updated = List.of(fields);
    final index = updated
        .indexWhere((f) => f is DekerekeValueField && f.name == name);
    if (index >= 0) {
      updated[index] = DekerekeValueField(name, value);
    } else {
      updated.add(DekerekeValueField(name, value));
    }
    return DekerekeRecord(updated);
  }

  @override
  bool operator ==(Object other) =>
      other is DekerekeRecord &&
      const ListEquality<DekerekeField>().equals(other.fields, fields);

  @override
  int get hashCode => const ListEquality<DekerekeField>().hash(fields);

  @override
  String toString() =>
      'DekerekeRecord(${reference.isEmpty ? '<no ref>' : reference}: $gloss)';
}

/// A parsed Dekereke database: the ordered children of `<phon_data>`.
///
/// Item order is preserved exactly — whether Dekereke re-writes file order
/// on grid re-sort is unverified (P0 #3 in `docs/HANDOFF.md`), so order is
/// treated as significant.
final class DekerekeDatabase {
  final List<DekerekeDatabaseItem> items;

  const DekerekeDatabase(this.items);

  List<DekerekeRecord> get records => items.whereType<DekerekeRecord>().toList();

  @override
  bool operator ==(Object other) =>
      other is DekerekeDatabase &&
      const ListEquality<DekerekeDatabaseItem>().equals(other.items, items);

  @override
  int get hashCode => const ListEquality<DekerekeDatabaseItem>().hash(items);
}
