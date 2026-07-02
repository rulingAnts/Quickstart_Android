/// Pure Dart core for the Dekereke Companion Suite.
///
/// See `docs/COMPANION_SUITE_PLAN.md` (repo root) for the architecture and
/// `doc/canonical_form.md` for the canonical-form specification.
library;

export 'src/audio/blob_store.dart';
export 'src/audio/manifest.dart';
export 'src/codec/db_codec.dart';
export 'src/codec/encoding.dart';
export 'src/codec/xml_writer.dart'
    show escapeXmlText, escapeXmlAttribute, serializeXmlNode;
export 'src/health/health.dart';
export 'src/identity/identity.dart';
export 'src/identity/reference_blocks.dart';
export 'src/merge/merge.dart';
export 'src/model/database.dart';
export 'src/model/sound_file.dart';
export 'src/settings/settings.dart';
export 'src/task/task_package.dart';
