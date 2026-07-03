# Cloud-session handoff — Dekereke Companion Suite

You are (probably) a Claude Code cloud session with access to ONLY this
repository. Everything you need is in-repo. Read
[COMPANION_SUITE_PLAN.md](COMPANION_SUITE_PLAN.md) first — it is the
authoritative plan (v1.2+). This file adds the context that used to live on
Seth's machines, a decision log, and a prioritized backlog.

## Repository state (2026-07-02)

- Branch `fix/make-app-work` = open **PR #5**: made the Flutter phone app
  actually work (real Dekereke XML import UTF-16, dedupe, consent screen,
  recording safety, export round-trip; 45 tests; CI green with APK
  artifact). Device smoke test still pending — do NOT assume merged.
  **Branch new work off `fix/make-app-work`** (it contains the plan docs
  and all fixes) unless Seth has merged PR #5 by the time you read this.
- CI: `.github/workflows/ci.yml` — analyze + test + release APK artifact.
  Keep it green; it is Seth's only build path (no local Android Studio).
- License: AGPL-3.0. Never commit real Fayu or QWOM data (QWOM is
  CC BY-NC-SA — license-incompatible; Fayu data is Seth's research data).
  Synthetic fixtures live in `test_data/dekereke_fixtures/`.

## Verified Dekereke ground truth (do not re-guess; sources noted)

Verified 2026-07-02 against Seth's real files (`Fayu_stable.xml`, 1,066
records/~75 columns; two real `DkUserSettings.xml` variants; 30,339-file
audio folder) and Casali (2019) "Importing and exporting Dekereke data"
(CanIL EWP 5) plus the Dekereke changelog/binary:

- DB = single UTF-16 LE (BOM, CRLF) XML: `<phon_data>` → `<data_form>`
  records → flat column tags. Empty fields self-closed (`<Notes />`);
  booleans are presence-only tags (`<loan />`); QuickVPlot writes NESTED
  `<qvp_acoustic_data_>` elements inside records — unknown fragments must
  round-trip verbatim.
- `<Reference>` is the only record key; uniqueness/presence NOT enforced
  (real DBs contain duplicates/gaps). Identity design = sidecar map, see
  plan §4.2.
- Columns are implicit: the tag set IS the schema; users add/rename columns
  in-app. Tag names case-sensitive.
- Audio is **WAV-only** (binary uses a pure RIFF reader; no FLAC/MP3).
  Cell may list multiple files (`|` or comma — exact syntax to verify in
  P0). Column audio file = `<SoundFile value minus .wav><suffix>.wav`;
  suffix per column from settings, e.g. `Phonetic → -phon`. Real suffixes
  are irregular (`-tf_Xhi`, `-tf-Xko`); filenames contain spaces/parens.
- `*-DkUserSettings.xml` (UTF-16): `<settings>` containing
  `<sound_file_path>` (machine-local!), praat/analyzer paths
  (machine-local!), `<column_to_sound_file_suffix_mappings>` (entries are
  TAB-separated `Column<TAB>-suffix`), `<user_column_order>`
  (name/position/width), `<columns_for_phonetic_analysis>`,
  `<syllable_division>`, `<banned_onsets>`; some variants add
  `<screen_display_profiles>`, `<hidden_columns>`, `<field_restrictions>`,
  `<gloss_set_restrictions>`, `<search_restrictions>`.
- Dekereke's own merge (Tools > Update Current Data From File):
  last-import-wins, whole-record replace keyed on Reference, never deletes,
  appends unknown/missing References, no conflict detection.
- Dekereke auto-writes timestamped backup XMLs on every save (e.g.
  `Fayu_stableDK-Backup2025-08-26-09-06.xml` observed) — the Companion
  replaces these with real history and sweeps them.
- Builds: legacy ClickOnce 1.0.0.313 (2023, format fully documented);
  Dec-2025 Windows rewrite (adds wordlist recording; format UNVERIFIED —
  P0); Mac preview (out of scope). **Decision: the system pins a minimum
  Windows build** (recommend the rewrite pending P0).
- Real audio scale: 30,339 WAVs (8,368 `-bdoi` [speaker column], 1,059
  `-phon`, ~732-file families per verb-paradigm frame). Multiple divergent
  folder copies exist across Seth's machines/Drive — first manifest build
  doubles as a dedupe report.

## FlexText suite patterns to reuse (mined 2026-07-02, repos not visible here)

Seth's FlexText Editor Suite (PWAs + `flextext-r2-worker` Cloudflare Worker
at connect.flextext.app) is the field-tested model. Key transplants:

- **Enrollment:** one-time invite links, secret in URL fragment (QR-able);
  device mints install_id + install_secret + RSA-OAEP-2048 keypair LOCALLY
  and persists BEFORE the claim POST (idempotent retry); atomic one-time
  claim; researcher approve step; device accept step; out-of-band pubkey
  fingerprint check.
- **Two-lane protocol:** researcher writes only `desired` (settings +
  append-only command log with per-instance seq + desired_rev); device
  writes only its `reported` blob + ack cursor. Poll
  `GET /v1/instances/<id>?since=<rev>` → 204 unchanged / full blob;
  20s/60s poll cadence, bounded exponential backoff + jitter, 20s request
  timeout, 4xx never retried, non-idempotent calls retry:false.
- **Consistency:** CAS on rev columns (5 retries then 409), optimistic
  settings_rev PUT (409 → refetch+reapply), idempotent command dispatch
  (re-appliable after crash), reports change-gated on sha256 of stable
  plaintext (never timestamps).
- **E2EE (optional layer):** AES-256-GCM `encryptJSON` → `<iv>.<ct>` opaque
  tokens; researcher key Kr (server-escrowed by explicit choice) wraps
  per-instance keys Ki; Ki delivered RSA-wrapped to installs. Server stores
  ciphertext + routing fields only.
- **Content/control split:** D1 = tiny control metadata; big files (audio)
  = R2 (10 GB free PER ACCOUNT, zero egress, Range/206 supported;
  flextext already self-caps at 9.5 GB on Seth's account — see open Q2).
  `_`-prefixed R2 keys reserved. MAX_FILE_BYTES 512 MB pattern.
- **Ops:** strictly additive D1 migrations (old clients never break);
  GitHub-Actions-only wrangler deploys with scoped token; workers_dev kept
  alive alongside custom domain so deployed clients never break.

## Decision log

| # | Decision | Status |
|---|---|---|
| D1 | Pin minimum Dekereke version, Windows-only v1 | **Decided** (Seth 2026-07-02); which build → pending P0/Seth |
| D2 | Identity = synced sidecar map + checkpoint re-binding ladder (content hash → SoundFile → Reference+Gloss → position → prompt); NO in-file ID column in v1 | **Decided** (plan §4.2) |
| D3 | **WAV everywhere** — no FLAC at rest or between databases; new recordings are ALWAYS 16-bit mono WAV. Single exception: reference audio exported DB→phone in `.dektask` (playback-only) MAY be FLAC to cut size/bandwidth; never the other direction | **Decided** (Seth 2026-07-02, Q3 — overturns the earlier FLAC-in-cloud recommendation) |
| D4 | Reference labels auto-assigned from per-collaborator blocks; Companion picks sensible defaults (e.g. 1000/person), allocation visible in the health panel | **Decided** (Seth 2026-07-02, Q4) |
| D5 | Seth's Cloudflare account hosts the **engine only** — Worker + D1 for accounts/enrollment, metadata, keys/invites, relay between app instances (flextext model). **No user data storage on his account**; nothing that can get him throttled/charged by others' usage. Each database owner brings their own storage for audio + DB repos: **both backends from day one** behind one pluggable content-addressed blob-store interface — owner's Google Drive (API-only: immutable sha256-named blobs, append-only, no Drive Sync app, no in-place edits — sidesteps every Drive weakness Seth named) and owner's own R2. Text history stays in the owner's GitHub private repo (device-flow). Colleagues still zero accounts: the Worker brokers short-lived storage access; audio bytes flow device↔owner storage directly | **Decided** (Seth 2026-07-02, Q2+Q5) |
| D6 | Desktop = Flutter (Windows) sharing `dekereke_core` with phone app | **Decided** (Seth 2026-07-02, Q7) |
| D7 | Phones = constrained satellites (task packages, leased writable columns), never peers | **Decided** (plan §4.2b, §5) |
| D8 | Canonical form preserves file record order (draft plan said "Reference order"): sorting would break the exact-inverse guarantee, position-hint identity signals, and assumes P0 #3; Reference isn't sortable anyway (duplicates/blanks) | **Decided** (session 2026-07-02, engineering call — veto welcome); spec in `packages/dekereke_core/doc/canonical_form.md` |
| D9 | Assume overlapping edits are common: the plain-language conflict UI is first-class (column leases still reduce conflicts but are not relied on) | **Decided** (Seth 2026-07-02, Q6) |
| D10 | **Product scope:** general-purpose tool for many teams — Seth's own Fayu project is NOT the driving deployment. Typical owner starts from a local folder on one Windows machine and needs share/track/merge from there. (Seth's real files remain the format ground truth; the seeding/dedupe P0 items are now "typical user" features, not a Fayu migration) | **Decided** (Seth 2026-07-02, Q5 reframe) |

All plan §7 questions are RESOLVED (Q1–Q7, 2026-07-02) — see the log above.

## P0 checklist (REQUIRES Seth's Windows VM — a cloud session cannot do these)

1. Unknown flat + nested tag survival through grid/save/Update-From-File.
2. Format snapshot of the pinned (Dec-2025) build vs legacy files.
3. Does grid re-sort rewrite file record order on save?
4. File locking / external-change detection while Dekereke is open.
5. Exact auto-backup filename pattern of the pinned build.
6. Built-in recorder WAV spec; does it fill `SoundFile`; suffix-column support.
7. Exact multi-file cell separator syntax.

**Test kit ready** (2026-07-02): `test_data/p0_test_kit/` — disposable
TestDB with planted probes, settings file, Update-From-File probe,
audible test WAVs, and the numbered click-by-click
[`CHECKLIST.md`](../test_data/p0_test_kit/CHECKLIST.md) covering items
1–7 (~25 min on the VM). Regenerate with
`dart tool/generate_p0_kit.dart` in `packages/dekereke_core`.

## Prioritized backlog for a cloud session (all doable in-repo)

1. ~~**`packages/dekereke_core`**~~ **DONE in PR #6** (2026-07-02): all
   sub-items below implemented with 174 tests (fixture byte-identity
   round-trips included) and a dedicated `dekereke-core` CI job — plus
   beyond the original scope: object-level `diffRecords` (tracked
   changes/history summaries), health panel rules (§4.2 Reference lint),
   Reference block allocation (D4), and the content-addressed BlobStore
   interface + audio sync planning (D5) with memory/filesystem backends.
   Specs: `packages/dekereke_core/doc/canonical_form.md` +
   `task_packages.md`. Original scope for reference:
   - Dekereke XML model + codec: port/extend the proven code in
     `lib/services/xml_service.dart` (UTF-16 LE/BE/UTF-8 sniffing +
     encodeUtf16Le already exist and are tested); add: nested/unknown
     fragment preservation (store raw XML, not just (name, text) pairs),
     boolean presence tags, multi-file SoundFile cells.
   - Canonical form: deterministic UTF-8/LF one-field-per-line rendering +
     exact inverse back to UTF-16 working format. Spec it in
     `packages/dekereke_core/doc/canonical_form.md`.
   - Settings model: parse/generate DkUserSettings; split shared vs
     machine-local parts (plan §4.1).
   - Identity: fingerprints, sidecar map (JSON), reconciliation ladder
     (plan §4.2) — pure functions + exhaustive tests (edit/clear/duplicate/
     delete/reorder scenarios).
   - Merge: record+field 3-way keyed on DkSyncID, conflict objects with
     plain-language rendering data (plan §4.2b).
   - Audio manifest: filename → {sha256, bytes}; diff; conflict policy.
   - Task packages: `.dektask` / `.dekresult` (plan §5.2) with task.json
     carrying the ID map.
   - Tests against `test_data/dekereke_fixtures/` (synthetic, format-
     faithful, safe to extend).
2. ~~**Phone app task mode**~~ **DONE in PR #6** (2026-07-02, plan §5.4):
   `.dektask` import, config-driven elicitation (visible/playable/writable
   fields), suffix-aware 16-bit mono WAV recording, FLAC reference
   playback, validated `.dekresult` export. All 45 pre-existing tests
   green + 24 new. Smoke-test package: `test_data/sample_task/`.
3. ~~**Worker scaffold**~~ **DONE in PR #6** (2026-07-02):
   `workers/dekereke-sync/` — engine-only per D5 (no R2 binding, no user
   blobs): owner bootstrap, one-time invites/claims (atomic, idempotent
   retry), approval step, desired/reported two-lane relay with CAS.
   Additive D1 migrations; 16 integration tests against real workerd+D1
   (Miniflare); `worker-engine` CI job. Deploy remains Seth's (wrangler
   steps documented in `wrangler.toml`/README).
4. ~~**Companion desktop scaffold**~~ **DONE in PR #6** (2026-07-02):
   `apps/companion/` — Flutter Windows shell sharing dekereke_core; the
   Health check screen is already functional (real parser + health rules
   against a picked database); History/Sync are plain-language
   placeholders. Path-filtered `companion.yml` workflow: ubuntu
   analyze/test + windows-2022 release build uploaded as the
   `dekereke-companion-windows` artifact.

Do NOT start server deployments, don't touch PR #5's app code except via
its own branch, and keep every commit CI-green.

### Queued: consent system (design ready, awaiting Q-A..Q-D answers)

Seth supplied the flextext consent-system spec (2026-07-02: two
composable axes — ask: text/audio; confirm: yesno/record/signature —
frozen prompts, bundled receipts). The wordlist adaptation is designed
and adversarially panel-reviewed in `docs/CONSENT_DESIGN.md` (v1.1):
consent covers a SCOPE (one ceremony per speaker × imported wordlist,
never per recording), items stamp receiptId+hash, receipts are
tamper-evident (content hash + per-device chain), lightweight
researcher-recorded continuation prompts, withdrawal route added (the
shipped app has none post-assent). Implementation blocked ONLY on the
four §6 decisions (continuation default, IP/location, speaker-name
field, withdrawal export behavior) — get Seth's answers, log them here,
then build: core ConsentConfig/ConsentReceipt + format carriers first,
phone ceremony UI second, Companion task-builder UI with P3.

## Working agreements

- **Model policy: Claude Fable only** (pinned in `.claude/settings.json`:
  model + allowlist + no fallbacks). If you ever detect you are running as
  a different model (Opus/Sonnet/etc.), STOP immediately, say so, and wait
  — do not continue the work on a downgraded model. If Fable usage limits
  are hit, stop and wait for the reset; never switch models to keep going.
- **Use GitHub Actions/Workflows as much as possible for testing,
  troubleshooting, and building** (Seth's explicit instruction): extend
  `.github/workflows/` with jobs for `dekereke_core` tests, phone-app
  tests/APKs, Windows desktop builds, and any troubleshooting harnesses.
  CI runs and artifacts are the source of truth — Seth has limited
  bandwidth and no local build tooling; a green workflow with a
  downloadable artifact beats "works in my sandbox".
- Seth will answer the open questions (plan §7) directly in-session —
  record each answer immediately in this file's Decision log and mark the
  question resolved in the plan, so no answer is ever lost to a short
  session.
- Seth interacts from his phone; sessions may be short — leave the repo
  self-explanatory after every push (update this file's Decision log and
  the plan's §7 as things resolve).
- Verify, never guess: anything about Dekereke behavior not listed above is
  UNVERIFIED — park it in the P0 list rather than assuming.
- Plain-language UX everywhere; no git/VCS vocabulary in anything
  user-facing.
