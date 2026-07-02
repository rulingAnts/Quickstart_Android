# Dekereke Companion Suite — Plan (draft v1, 2026-07-02)

Sync/merge for shared Dekereke databases + researcher-configured delegation to
the Quickstart_Android phone app. **Planning document — nothing here is built
yet.** Facts below are verified against real files and documentation; open
questions are listed explicitly at the end.

---

## 1. Verified ground truth (no guessing)

**Sources:** Seth's live database (`~/GIT/dekereke-stable/Fayu_stable.xml`,
1,066 records, ~75 columns, 3.3 MB) and its `Fayu_stable-DkUserSettings.xml`;
the `Barnabas-DkUserSettings.xml` delegated-view variant; the audio folder
(30,339 WAVs; 8,368 `-bdoi`, 1,059 `-phon`, ~732-file verb-frame families);
Casali (2019) *Importing and exporting Dekereke data* (CanIL EWP 5); the
Dekereke changelog and legacy binary.

- **Database** = one flat UTF-16 LE XML file: `<phon_data>` → `<data_form>`
  records → flat column tags. Empty fields are self-closed; booleans are
  presence-only tags (`<loan />`). QuickVPlot writes **nested**
  `<qvp_acoustic_data_>` elements inside records — records are not always
  leaf-only, so any tool must round-trip unknown XML fragments verbatim.
- **`<Reference>` is the only persistent record key.** No GUIDs.
- **Columns are per-database and implicit** — the tag set *is* the schema;
  users add/rename columns freely in Dekereke.
- **Audio is WAV-only.** Playback uses a pure RIFF/WAVE reader; no FLAC/MP3
  support anywhere in Dekereke. Multiple files per cell supported
  (`|`/comma separated).
- **Sound mapping:** each record's `<SoundFile>` holds the base filename
  (`0012_descend.wav`); a suffix-mapped column plays
  `<base minus .wav><suffix>.wav` (Phonetic→`-phon`, Barnabas→`-bdoi`).
  Mappings live in `DkUserSettings.xml` as TAB-separated
  `Column<TAB>-suffix` entries. Real suffixes are irregular (`-tf_Xhi`,
  `-tf-Xko`); filenames contain spaces and parentheses.
- **`DkUserSettings.xml` mixes shared and machine-local config:** shared
  (suffix mappings, column order/widths, analysis settings, display
  profiles / hidden columns / field restrictions) vs machine-local
  (`sound_file_path`, Praat/analyzer paths). Sync must split these.
- **Dekereke's own collaboration model** (per Casali 2019): export selected/
  filtered rows (with field selection) + "Copy Sound Files Of Selected Data
  To Folder" → share → *Update Current Data From File*, which is
  **last-import-wins, whole-record replace keyed on Reference, never
  deletes, no conflict detection**. Our system automates and hardens exactly
  this workflow.
- **Backups:** Dekereke writes timestamped backup XMLs on every save
  (author calls the feature "rudimentary"); dozens accumulate. Our history
  replaces them.
- **Versions:** legacy ClickOnce build 1.0.0.313 (2023, no auto-update);
  a rewritten Windows version (Dec 2025, includes wordlist recording) and a
  preliminary Mac version (Apr 2025) exist — their format deltas are
  unverified (see Open Questions).

## 2. Requirements (Seth, 2026-07-02)

1. Keep multiple copies of a Dekereke DB in sync: diff, merge, concurrent
   changes, history, easy revert — **including sound files** (8 GB+, tens of
   thousands of small WAVs).
2. Delegate collection to phones: researcher chooses records + which fields
   are visible / playable / writable (text, audio, or both; new blank column
   or existing column); results **merge** back, never overwrite.
3. **Zero VCS knowledge required.** No git/mercurial vocabulary anywhere.
   Everything automatic; plain-language conflict resolution; one-time guided
   setup (e.g. a private repo + token) is acceptable.
4. **Free** to run. Audio must be shared and synced; too big for GitHub/LFS.
5. Deletes Dekereke's backup clutter and replaces it with real history.

## 3. Architecture overview

```
┌─────────────────────────── Researcher's PC (Windows, next to Dekereke) ──┐
│  Dekereke  ⇄  workspace files  ⇄  Dekereke Companion (Flutter desktop)   │
│  (unchanged)   Fayu.xml (UTF-16)     • watches saves → auto-checkpoints  │
│                DkUserSettings.xml    • history / one-click restore       │
│                audio/*.wav           • sync (pull-merge-push)            │
│                                      • delegation: build/merge tasks     │
└──────────────────────────────┬───────────────────────────┬──────────────┘
                    text + manifest                audio blobs (WAV, D3)
                               │                           │
                 GitHub private repo (free,     OWNER's blob storage (D5):
                 owner's) canonical UTF-8 DB    Google Drive or owner R2 —
                 + history, audio manifest,     immutable sha256-named blobs;
                 shared settings                access brokered by the engine
                               │                (maintainer's Worker + D1:
                               │                enrollment/metadata/relay ONLY)
                               │                           │
┌──────────────────────────────┴───────────────────────────┴──────────────┐
│  Colleague's PC — same Companion app, enrolled by invite                 │
└──────────────────────────────────────────────────────────────────────────┘

Delegation:  Companion ──.dektask ZIP──▶ Quickstart_Android ──.dekresult──▶
             (file share/USB/QR now; Worker relay in a later phase)
```

Three deliverables, one shared core:

- **`dekereke_core`** (Dart package): UTF-16 codec, canonical form,
  record/field 3-way merge, audio manifest, task package format. Shared by
  the phone app (already Flutter) and the desktop app (Flutter for
  Windows/macOS). The phone app's proven XML round-trip code seeds this.
- **Dekereke Companion** (Flutter desktop): sync + history + delegation UI.
- **Worker backend (the engine)**: small Cloudflare Worker + D1 on the
  maintainer's account — enrollment, metadata, keys/invites, relay only;
  no user blobs (D5) — copying flextext-r2-worker's proven patterns
  (one-time invite links with secret in URL fragment, client-minted
  credentials, rev-cursor polling, additive migrations,
  GitHub-Actions-only deploys). Owner storage (Drive/R2) is accessed
  directly by devices with short-lived brokered credentials.

## 4. Sync engine design

### 4.1 Canonical form (what history is kept in)

Git stores a **canonical UTF-8** rendering, not the UTF-16 working file:
UTF-8, LF, one field per line, records in original file order (decision D8 —
sorting by Reference was dropped: it breaks the exact inverse and the
position identity signal, and Reference allows duplicates/blanks),
unknown/nested fragments preserved verbatim. Full spec + implementation:
`packages/dekereke_core/doc/canonical_form.md`. The Companion converts on the fly:
pull → materialize UTF-16 LE + BOM + CRLF for Dekereke; checkpoint → parse
back to canonical. (This is the git-hook idea done properly — the phone app
already has tested code for exactly this conversion.) Result: meaningful
line-level diffs, tractable merges, tiny repo (~3 MB text).

The shared parts of `DkUserSettings.xml` (suffix mappings, column order,
display profiles) are versioned as a canonical `settings.shared.xml`; each
machine's real `DkUserSettings.xml` is generated locally = shared part +
local paths (sound folder, Praat). Local paths never sync.

### 4.2 Identity & integrity (the Reference problem)

`<Reference>` is a design flaw as a key: Dekereke enforces neither
uniqueness nor presence, and it doubles as the audio-naming convention.
The Companion separates **identity** from **label** — and keeps identity
entirely out of Dekereke's reach (a hidden column can't be kept hidden or
read-only in the Windows app, so correctness must not depend on one):

- **Sidecar identity map = authority.** `.deksync/identity.json` (versioned
  and synced like everything else) maps `DkSyncID → record fingerprint`,
  where the fingerprint carries several independent signals: full content
  hash, `SoundFile` value, Reference+Gloss, file position. Dekereke never
  sees this file; nothing done in its UI can damage it.
- **Re-binding at every checkpoint** (every watched Dekereke save, so drift
  between reconciliations is tiny): match records to IDs by exact content
  hash (covers ~99% each save) → SoundFile → Reference+Gloss → position
  hint → rare plain-language repair prompt. IDs are *restored*, never
  re-minted, whenever any signal matches; truly new records get new IDs;
  vanished records become explicit, user-confirmed deletions at sync time.
  Duplicated rows: best match keeps the ID, the copy is minted fresh and
  flagged as near-duplicate content.
- **No ID column in the XML for v1.** IDs travel between machines via the
  synced sidecar, and to/from phones inside `task.json` (our format) —
  never inside the wordlist XML. The only flow that would want an in-file
  ID is a full DB copy leaving the ecosystem by email/USB and returning;
  that is handled by one-time content matching at adoption (same ladder).
  P0 tests whether Dekereke preserves unknown flat and *nested* tags
  through load/save — if nested tags survive invisibly (as its own
  `<qvp_acoustic_data_>` does), that becomes an optional tamper-resistant
  embedding for later; if not, sidecar-only is confirmed.
- Merge and task matching key on `DkSyncID` (from the sidecar).
  Consequences: duplicate References merge losslessly (flagged, not
  fatal), missing References still sync, renumbering is just a field edit,
  and phone results match their exact source records.
- **Database health panel = Reference lint.** Audio naming still leans on
  Reference, so the Companion continuously flags: duplicate References,
  empty References, SoundFile↔Reference mismatches, orphaned audio files,
  and missing suffix files — each with a guided fix, including a
  **linkage-preserving renumber** (updates Reference + renames base WAV +
  all suffix WAVs + `<SoundFile>` atomically), which Dekereke lacks.
- **Reserved Reference blocks per collaborator** prevent two machines from
  minting the same new Reference; auto-assignment picks the next free
  number in the local block.
- P0 experiment (informs the *optional* embedding only — nothing in v1
  depends on it): whether Dekereke's grid shows, and load/save/
  Update-From-File preserve, unknown flat tags and unknown nested tags.

### 4.2b Merge (the heart)

Record-level 3-way merge keyed on `DkSyncID` (Reference is display-only in
merge), then field-level within a record:

- Added records: kept from both sides (identity is `DkSyncID`, so
  same-Reference additions coexist and get flagged by the health panel).
- Field edited on one side only → auto-merge.
- Same field edited identically → auto-merge.
- Same field, different values → **conflict**, shown in plain language:
  *"Word 0042 'ear': Phonetic — Yours: 'ɛnɔ' / Chris's: 'ɛnɔː'. Keep yours /
  Keep Chris's / Keep both (Chris's goes to Notes)"*. Nothing proceeds
  silently; nothing is lost either way.
- Deletions are never implicit (matches Dekereke's own never-delete merge):
  a delete is an explicit tombstoned action that the other side confirms on
  next sync.
- Sync = always pull → merge → checkpoint → push (no rebase/branch concepts
  surface anywhere; "branching" exists only implicitly and merges away).
- **Object-level, never line-level:** merge, diff and tracked changes all
  operate on the parsed record/field model keyed by DkSyncID
  (`merge3`/`diffRecords` in `dekereke_core`) — git/GitHub is only the
  content store and transport. `git merge` and GitHub's line-based
  conflict machinery are never invoked: the Companion merges objects
  locally, renders the canonical form, and commits the already-merged
  result. The canonical form's one-field-per-line property just makes the
  *stored* history compact and pleasant to eyeball on github.com — it is
  not the merge mechanism.

**Scope note (multi-writer, heterogeneous):** the sync graph is N full
Dekereke databases (unmodified Windows app, multiple researchers as
symmetric peers) + M phone instances (constrained satellites for
low-literacy speakers — subset of records, whitelisted fields, leased
writable columns; they never see sync or merge vocabulary). All merging
happens researcher-side in the Companion. Writable-column leases live in
the synced repo state, so two researchers cannot unknowingly delegate the
same column to different speakers.

### 4.3 History & backups UX

- Companion watches the workspace; every Dekereke save → automatic
  checkpoint ("Saved by Seth — 3 words changed") with no user action.
- History screen: human timeline, per-checkpoint summary (records
  added/changed, fields touched, audio added), one-click **Restore** of the
  DB and/or individual records ("restore word 0042 as of last Tuesday").
- Sweeps `*DK-Backup*.xml` (configurable retention, default: delete after
  the content is checkpointed — it's redundant with history).
- Git terms never appear. Under the hood: libgit2 (via dart bindings) or a
  bundled portable git — implementation detail hidden from users.

### 4.4 Audio sync (the 8 GB problem)

- **Manifest, not LFS:** `audio-manifest.json` in the repo maps
  `filename → {sha256, bytes}`. Text history stays tiny; the manifest's git
  history *is* the audio folder's history. (Implemented in
  `dekereke_core` `audio/`.)
- **Blobs in the OWNER'S storage** (D5), content-addressed by sha256
  (immune to spaces/parens in names), behind one pluggable blob-store
  interface — immutable, append-only, hash-named objects. Two backends
  from day one:
  - **Google Drive** (default for low-tech-savvy owners): API-only —
    never the Drive Sync app, never in-place edits, never duplicate-copy
    juggling; blobs are only ever *added*, which is the one thing the
    Drive API does well. 15 GB free that owners already have.
  - **Owner's own Cloudflare R2** for owners willing to set one up
    (10 GB free, zero egress).
  The maintainer's Worker brokers enrollment and short-lived access
  tokens; audio bytes flow device ↔ owner storage directly (no traffic
  or storage on the maintainer's account).
- **WAV everywhere** (D3): no transcoding at rest or between databases;
  new recordings are ALWAYS 16-bit mono WAV. ~30k files ≈ 8 GB fits
  Drive's 15 GB; owners can prune/split or move to R2 if they outgrow it.
  The single FLAC exception lives in §5.2 (phone reference audio).
- **Append-mostly reality:** recordings are rarely modified; a sync is
  usually "upload my 40 new takes, download Chris's 12". Re-record conflict
  (same filename, different hash, both sides) → keep both, rename the
  incoming one visibly, surface in the conflict list. (Implemented:
  `mergeManifests` + `resolveKeepBoth`.)
- **Seeding:** the first gigabytes never need to cross slow links —
  Companion supports import-from-folder/USB with manifest verification;
  only deltas sync thereafter. The first manifest build doubles as a
  dedupe report (`duplicateGroups`).

### 4.5 Accounts & setup (the "free + friendly" answer)

- **The engine is deployed ONCE, by the maintainer** (Seth's Cloudflare
  account, D5): Worker + D1 holding enrollment, metadata, keys/invites and
  the relay — the exact operational model of flextext-r2-worker. It stores
  no user blobs and proxies no audio, so nothing about it scales with
  users' data.
- **Database owner (one-time, guided):** GitHub account + private repo —
  Companion uses GitHub's **device flow** sign-in (type an 8-character code
  into github.com; no manual PAT creation) with PAT entry as fallback —
  plus connecting their storage backend: Google Drive OAuth (default) or
  their own R2 credentials (§4.4).
- **Colleagues: zero accounts.** The owner mints a one-time invite link/QR
  (flextext enrollment pattern: secret in URL fragment, client-minted
  credentials, owner approval step). A colleague installs Companion, opens
  the invite, picks a folder — done. Their git access is mediated by the
  Worker (repo deploy key server-side) and their storage access rides
  short-lived tokens the Worker brokers, so they never touch GitHub, Drive
  or Cloudflare themselves.
- Everything rides free tiers: GitHub private repo, Workers free plan
  (100k req/day), D1, and the owner's own Drive 15 GB / R2 10 GB.

## 5. Delegation to the phone app

### 5.1 Researcher side (Companion)

Mirrors Dekereke's own concepts (filtered rows + field selection + display
profiles), so it can also emit a matching `DkUserSettings` display profile:

- Pick records: all / filter / reference list (same semantics as Dekereke's
  *Export Filtered Data*).
- Per field: **visible** (read-only prompt: Gloss, IndonesianGloss,
  pictures…), **playable** (suffix-mapped column → its WAVs get bundled),
  **writable** (existing column or a *new* column created here, with
  text / audio / both; audio target gets a suffix mapping, e.g. new column
  `Yohanis` → suffix `-yoh`).
- Guardrail: a given writable column/suffix can only be in one open task at
  a time → merge-back conflicts become structurally rare.

### 5.2 Package formats

- **`.dektask` ZIP:** `task.json` (task id, base checkpoint id, field
  config, suffix assignments, consent config) + subset wordlist XML
  (canonical UTF-8 — the phone parser already accepts it) + `audio/` for
  playable references + optional `pictures/`. Reference audio MAY be
  FLAC-compressed here — the one FLAC exception (D3): DB→phone,
  playback-only, never the other direction.
- **`.dekresult` ZIP:** task id + base checkpoint + collected cell values +
  new recordings (already named `<base><suffix>.wav`, ALWAYS 16-bit mono
  WAV per D3) + consent log — a constrained superset of the phone app's
  existing export.
- Both formats implemented + spec'd:
  `packages/dekereke_core/doc/task_packages.md`.
- Transport now: any file channel (USB, share sheet, Drive) — offline-first.
  Later phase: Worker relay with QR enrollment and rev-cursor polling
  (the flextext two-lane desired/reported protocol transplants directly).

### 5.3 Merge-back

3-way against the recorded base checkpoint. Only cells in
(task's Reference set × writable columns) can differ → a conflict occurs
only if the researcher edited one of those exact cells since exporting the
task; resolved in the same plain-language UI. New audio enters via the
manifest like any other sync. Consent logs archive alongside the checkpoint.

### 5.4 Phone app changes (moderate, builds on what's shipped)

- Task import (`.dektask`) alongside plain-XML import.
- Elicitation screen driven by field config: N visible fields, playable
  fields with play buttons, K writable fields (text box / mic / both) —
  a generalization of today's hardcoded Gloss+Indonesian+Phonetic+mic.
- Recording filenames honor the task's suffix assignment (existing
  `recordingFilename` logic parameterized); recordings captured as
  **16-bit mono WAV** (D3).
- Playable reference fields must handle FLAC as well as WAV (the D3
  exception; Android's player stack supports FLAC natively).
- Export produces `.dekresult`. Everything else (consent, temp-file
  recording safety, session resume, dedupe) is already in place.

## 6. Phases

| Phase | Delivers | Notes |
|---|---|---|
| **P0 Verify** | Format deltas of the Dec-2025 Dekereke rewrite vs legacy; backup filename scheme; unknown flat/nested tag survival through grid/save/Update-From-File (decides optional ID embedding); whether grid re-sort rewrites file record order on save (position-hint validity); its recorder's WAV spec | Empirical, on the Windows VM; blocks nothing else except final canonicalizer details |
| **P1 History** ("backup killer") | `dekereke_core` + Companion single-user: workspace adoption, save-watching auto-checkpoints, history/restore UI, DK-Backup sweep | Immediately useful to Seth alone; no server, no accounts |
| **P2 Sync** | GitHub device-flow setup, pull-merge-push, conflict UI, audio manifest + owner blob storage (Drive + owner-R2 backends, D5; WAV everywhere, D3), invites for colleagues | The colleague send/receive request |
| **P3 Delegation (offline)** | Researcher task builder, `.dektask`/`.dekresult`, phone task mode | Phone changes land in Quickstart_Android |
| **P4 Online + polish** | Worker relay for phones (QR, polling), Mac support, multi-database | Optional niceties |

## 7. Open questions — ALL RESOLVED (Seth, 2026-07-02)

Answers live in the HANDOFF decision log (D1–D10); summaries:

1. ~~Which Dekereke build(s)~~ **RESOLVED: pinned minimum Dekereke version,
   Windows only** (D1). Remaining sub-decision: legacy 1.0.0.313 vs the
   Dec-2025 rewrite (recommendation: the rewrite; P0 verifies its format).
2. ~~Hosting centralization~~ **RESOLVED (D5): Seth's Cloudflare account
   runs the engine only** (Worker + D1: enrollment, metadata, keys/invites,
   relay — flextext model; nothing that scales with users' data or could
   get him throttled/charged). **All user data storage is owner-supplied**
   (see Q5).
3. ~~FLAC-at-rest~~ **RESOLVED (D3): WAV everywhere.** No FLAC at rest or
   between databases; new recordings ALWAYS 16-bit mono WAV. One exception:
   reference audio bundled DB→phone (playback-only) may be FLAC.
4. ~~Reference block sizes~~ **RESOLVED (D4): Companion picks defaults**
   (e.g. 1000-per-person), allocation visible in the health panel.
5. ~~Master audio folder~~ **RESOLVED (D5+D10): reframed — general-purpose
   tool**, not a Fayu migration. Owners bring their own storage: Google
   Drive AND owner-R2 backends both supported from day one behind one
   pluggable content-addressed blob store (§4.4).
6. ~~Same-column edits?~~ **RESOLVED (D9): assume overlap** — the
   plain-language conflict UI is first-class.
7. ~~Desktop stack~~ **RESOLVED (D6): Flutter for Windows**, sharing
   `dekereke_core` (built, tested, CI-covered) with the phone app.
