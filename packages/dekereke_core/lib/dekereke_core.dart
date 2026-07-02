/// Pure Dart core for the Dekereke Companion Suite.
///
/// See `docs/COMPANION_SUITE_PLAN.md` (repo root) for the architecture and
/// `doc/canonical_form.md` for the canonical-form specification.
library;

export 'src/codec/db_codec.dart';
export 'src/codec/encoding.dart';
export 'src/codec/xml_writer.dart'
    show escapeXmlText, escapeXmlAttribute, serializeXmlNode;
export 'src/model/database.dart';
export 'src/model/sound_file.dart';
export 'src/settings/settings.dart';
