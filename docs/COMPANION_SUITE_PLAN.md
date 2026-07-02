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
                    text + manifest                    audio blobs (FLAC)
                               │                           │
                 GitHub private repo (free)     Cloudflare Worker + R2
                 canonical UTF-8 DB + history   (clone of flextext-r2-worker
                 audio manifest, shared settings patterns; 10 GB free, no
                               │                 egress fees; invite auth)
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
- **Worker backend**: small Cloudflare Worker + R2 + D1, copying
  flextext-r2-worker's proven patterns (one-time invite links with secret in
  URL fragment, client-minted credentials, rev-cursor polling, additive
  migrations, GitHub-Actions-only deploys).

## 4. Sync engine design

### 4.1 Canonical form (what history is kept in)

Git stores a **canonical UTF-8** rendering, not the UTF-16 working file:
UTF-8, LF, one field per line, records in Reference order, unknown/nested
fragments preserved verbatim. The Companion converts on the fly:
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
  history *is* the audio folder's history.
- **Blobs in R2**, content-addressed by hash (immune to spaces/parens in
  names), uploaded/downloaded through the Worker with Range support.
  R2 free tier: 10 GB storage, **zero egress fees** — the decisive
  advantage over GitHub (LFS free = 1 GB), Drive (quota/API pain), or B2
  (egress caps).
- **FLAC on the wire and at rest, WAV on disk** (verified: Dekereke plays
  WAV only). Lossless FLAC ≈ 50–60% of WAV → ~30k files ≈ 8 GB WAV ≈
  4–5 GB FLAC: fits free tier with headroom. Companion encodes on upload,
  decodes on download; colleagues always see plain WAVs in their folder.
- **Append-mostly reality:** recordings are rarely modified; a sync is
  usually "upload my 40 new takes, download Chris's 12". Re-record conflict
  (same filename, different hash, both sides) → keep both, rename the
  incoming one visibly, surface in the conflict list.
- **Seeding:** first 8 GB never goes over Papua internet — Companion
  supports import-from-folder/USB with manifest verification; only deltas
  sync thereafter.
- Growth path if free tier is outgrown: R2 is $0.015/GB-month (≈ $0.08/mo
  per extra 5 GB) — or a second free bucket per database.

### 4.5 Accounts & setup (the "free + friendly" answer)

- **Database owner (one-time, guided):** GitHub account + private repo —
  Companion uses GitHub's **device flow** sign-in (type an 8-character code
  into github.com; no manual PAT creation) with PAT entry as fallback;
  Worker deployed once from a template repo via GitHub Actions (the exact
  operational model flextext-r2-worker already uses).
- **Colleagues: zero accounts.** The owner mints a one-time invite link/QR
  (flextext enrollment pattern: secret in URL fragment, client-minted
  credentials, owner approval step). A colleague installs Companion, opens
  the invite, picks a folder — done. Their git access is mediated by the
  Worker (repo deploy key server-side), so they never touch GitHub.
- Everything rides free tiers: GitHub private repo, Workers free plan
  (100k req/day), R2 10 GB, D1.

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
  playable references + optional `pictures/`.
- **`.dekresult` ZIP:** task id + base checkpoint + collected cell values +
  new recordings (already named `<base><suffix>.wav`) + consent log —
  a constrained superset of the phone app's existing export.
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
  `recordingFilename` logic parameterized).
- Export produces `.dekresult`. Everything else (consent, temp-file
  recording safety, session resume, dedupe) is already in place.

## 6. Phases

| Phase | Delivers | Notes |
|---|---|---|
| **P0 Verify** | Format deltas of the Dec-2025 Dekereke rewrite vs legacy; backup filename scheme; unknown flat/nested tag survival through grid/save/Update-From-File (decides optional ID embedding); whether grid re-sort rewrites file record order on save (position-hint validity); its recorder's WAV spec | Empirical, on the Windows VM; blocks nothing else except final canonicalizer details |
| **P1 History** ("backup killer") | `dekereke_core` + Companion single-user: workspace adoption, save-watching auto-checkpoints, history/restore UI, DK-Backup sweep | Immediately useful to Seth alone; no server, no accounts |
| **P2 Sync** | GitHub device-flow setup, pull-merge-push, conflict UI, audio manifest + Worker/R2 + FLAC pipeline, invites for colleagues | The colleague send/receive request |
| **P3 Delegation (offline)** | Researcher task builder, `.dektask`/`.dekresult`, phone task mode | Phone changes land in Quickstart_Android |
| **P4 Online + polish** | Worker relay for phones (QR, polling), Mac support, multi-database | Optional niceties |

## 7. Open questions (please answer / decide)

1. ~~Which Dekereke build(s)~~ **RESOLVED (Seth, 2026-07-02): the system
   requires a pinned minimum Dekereke version, Windows only.** Remaining
   sub-decision: pin the legacy 1.0.0.313 build or the Dec-2025 rewrite
   (recommendation: the rewrite — actively developed, has built-in
   recording; P0 verifies its format).
2. **Hosting centralization:** OK to run the Worker + R2 on your Cloudflare
   account (colleagues enroll by invite, zero accounts for them), sharing
   the free tier with flextext? Or should each database owner deploy their
   own from a template?
3. **FLAC-at-rest tradeoff:** cloud/transfer in FLAC, but every machine
   keeps the full WAV working folder (disk is cheap locally). Acceptable?
4. **Reference block sizes:** identity is handled by `DkSyncID` (§4.2), but
   new-Reference *labels* still auto-assign from per-collaborator blocks —
   any preference on block layout (e.g. 1000-per-person), or should the
   Companion just pick?
5. **Where is the master audio folder today** — the Google Drive
   "Core Phonology DB/audio" copy, the dekereke-sync path in the settings
   file, or elsewhere? (Seeding + dedupe starts from the authoritative one.)
6. **Does your colleague's workflow ever edit the same columns you edit**,
   or are your domains mostly disjoint (e.g. they do `-bdoi`, you do
   `-phon`)? (Calibrates how much conflict UI matters in P2.)
7. **Desktop stack confirmation:** Flutter desktop (shares `dekereke_core`
   with the phone app, one language) vs a web app like the FlexText suite.
   Plan assumes Flutter desktop; a PWA can't watch the filesystem or run
   git, which this design leans on.
