# dekereke_core

Pure Dart core for the **Dekereke Companion Suite** (see
[`docs/COMPANION_SUITE_PLAN.md`](../../docs/COMPANION_SUITE_PLAN.md) and
[`docs/HANDOFF.md`](../../docs/HANDOFF.md) at the repo root). Shared by the
phone app (this repo) and the future Flutter Windows Companion.

No Flutter dependency — everything here runs under plain `dart test` and is
exercised by the `dekereke-core` CI job.

## Modules

| Module | Status | What it does |
|---|---|---|
| `codec/` | ✅ | UTF-16 LE/BE/UTF-8 detection and codec; Dekereke XML ⇄ model with verbatim unknown-fragment preservation; byte-identical round-trip for Dekereke-written files |
| canonical form | ✅ | Deterministic UTF-8/LF rendering + exact inverse to the UTF-16 working format — spec in [`doc/canonical_form.md`](doc/canonical_form.md) |
| `model/` | ✅ | Database/record/field model; SoundFile cell + suffix rules |
| `settings/` | ✅ | `DkUserSettings.xml` model; shared vs. machine-local split; byte-identical round-trip (plan §4.1) |
| `identity/` | ✅ | Record fingerprints, sidecar identity map (`deksync-identity` JSON), reconciliation ladder (plan §4.2) |
| `merge/` | ✅ | Record+field three-way merge keyed on DkSyncID; conflicts carry plain-language data; deletions never implicit (plan §4.2b) |
| `audio/` | ✅ | `filename → {sha256, bytes}` manifest, dedupe report, diff, 3-way merge with keep-both policy (plan §4.4) |
| `task/` | ✅ | `.dektask` / `.dekresult` formats — spec in [`doc/task_packages.md`](doc/task_packages.md) (plan §5.2) |

## Ground rules

- **Never guess Dekereke behavior.** Everything implemented here traces to
  the verified list in `docs/HANDOFF.md`; open format questions live in its
  P0 checklist (e.g. the exact multi-file SoundFile separator syntax, P0 #7).
- Tests run against the synthetic, format-faithful fixtures in
  `test_data/dekereke_fixtures/` — genuine UTF-16 LE + BOM + CRLF files.
  Never commit real Fayu or QWOM data.

## Development

```sh
dart pub get
dart analyze --fatal-infos
dart test
```
