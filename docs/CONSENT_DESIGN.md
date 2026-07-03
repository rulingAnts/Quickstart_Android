# Consent for wordlist collection — design (v1.1, panel-reviewed)

Adapts the FlexText suite's consent system (spec provided by Seth,
2026-07-02) to this project. v1.1 incorporates an adversarial design
review (field-usability, IRB-auditability, implementation-fit lenses);
§7 lists what the review changed. Status: **awaiting Seth's answers to
the decisions in §6** — record them in the HANDOFF decision log.

## 1. What transplants unchanged from FlexText

- **Two independent, composable, multi-select axes** — one engine for
  literate and non-literate deployments:
  - **the ask** (`ask`: any of `text`, `audio`) — written statement
    and/or researcher-pre-recorded audio statement in the local
    language;
  - **the response** (`confirm`: any of `yesno`, `record`,
    `signature`) — explicit tap, spoken assent recording, typed name.
    All enabled confirmations must be satisfied together.
- Coherence validation (`text` ⇒ message required; `audio` ⇒ prompt
  recording required) — enforced when the Companion builds the task AND
  when the phone imports it.
- Prompt content is **data, not code**.
- The exact prompt is **frozen into the receipt**.
- Consent artifacts **travel inside the data exports** (machine JSON +
  human text), never as a detachable record.
- Offline-tolerant: never block on the *network*; context fields the
  device can't provide are `"unavailable"`.
- Empty on both axes ⇒ ceremony skipped (the "optional").

Permission-prompt timing (adapted): the mic permission needed by a
`record` confirmation is requested **once, on entering the ceremony**,
never mid-flow. If audio is the *only* ask mode and the prompt audio
cannot be played (missing/corrupt asset), the ceremony **blocks with a
plain-language error** rather than degrading to an unreadable text
fallback — a speaker must never "consent" to a prompt they couldn't
access.

## 2. The wordlist adaptation: consent covers a scope

### 2.1 One ceremony per consent scope

A **consent scope** is one *(speaker × wordlist-as-imported)*. The
ceremony runs once, BEFORE elicitation, and its frozen prompt includes a
researcher-supplied **scope statement** — prospective consent: *"the
words you are about to record in this task, however many sessions that
takes."*

### 2.2 Every collected item binds to its receipt — verifiably

Each recording and typed value is stamped, at collection time, with the
covering receipt's **id AND content hash** (see §3 tamper evidence).
Audit chain for any exported WAV:
`file → export row (receiptId + receiptSha256) → receipt JSON → frozen prompt`.

**Format carriers** (today's formats have none — this is an explicit,
versioned extension): `.dekresult`'s `values[]` and `recordings[]`
entries gain optional `receiptId`/`receiptSha256` fields; receipts and
their audio ship in a `consent/` ZIP member; the plain-mode ZIP export
gains the same `consent/` member. Old readers ignore unknown JSON keys;
a Companion that *requires* consent evidence emits the task at a bumped
`.dektask` format version, which old apps already refuse with "update
the app" — that is the mechanism preventing an outdated app from
silently collecting under a weaker ceremony than the researcher
configured.

**"Covering receipt" is defined precisely.** `validateResult` (and the
Companion at merge-back) accepts a recording/value as covered iff:

1. its stamped id resolves to a **bundled** receipt whose content hash
   matches the stamp;
2. that receipt's `kind` is `ceremony` or `continuation` (never
   `withdrawal`);
3. a `continuation` chains (via `refersTo` + hash) to a bundled
   `ceremony` receipt;
4. the receipt's scope matches the result (`taskId` and
   `baseCheckpointId` for task mode; wordlist fingerprint for plain
   mode);
5. the item's collection timestamp is not after a bundled withdrawal
   that refers to the same ceremony.

The check applies when the governing consent config has any axis
enabled; consent-off tasks and pre-consent format versions are exempt
(documented, not silent).

### 2.3 Ceremony triggers

A new **full ceremony** is required when the consent scope changes:

1. **Any import that replaces the wordlist** — a `.dektask` (new or
   re-issued: same `taskId` with a NEW `baseCheckpointId` is a new
   scope) or a plain-mode XML import. This single rule closes both
   review-found holes: plain-mode list swaps and task re-issues can
   never ride on a stale receipt.
2. **Speaker change** (per decision Q-C).
3. **After a withdrawal.**

Re-entering elicitation for an unchanged, already-consented scope never
re-runs the full ceremony (continuation policy below governs it).

### 2.4 Lightweight continuation

Configurable per task: `none` | `perDay` | `perSession`.

- `perDay`: fires on the first *entry into elicitation* on a new local
  calendar date — it never interrupts a running session at midnight.
- `perSession`: every entry into elicitation. (Note for researchers:
  low-end Android kills backgrounded apps aggressively; this can prompt
  often.)
- **Continuation content is researcher data too** (review finding):
  `ConsentConfig` carries a *short* `continuationMessage` and/or
  `continuationAudio` — e.g. a 5-second "Shall we keep recording words
  today?" in the local language — validated as required for each
  enabled ask mode when policy ≠ `none`. The full ceremony prompt is
  NOT replayed daily; that would make the anti-annoyance mechanism
  maximally annoying for exactly the non-literate speakers it serves.
- The continuation screen offers affirm AND "not now" (exit without a
  receipt, nothing recorded, elicitation stays closed); decline-forever
  is the withdrawal flow.
- Affirm logs a `continuation` receipt chaining to its ceremony.

### 2.5 Withdrawal

**Correction from v1**: the shipped app's data model supports
withdrawal ("latest record wins") but has **no UI route to it once
assent is given** — the design adds one (an always-visible option in
the elicitation screen's menu). Withdrawal:

- records a `withdrawal` receipt chaining to the ceremony;
- blocks collection until a new full ceremony;
- keeps already-collected items with their (valid-at-the-time) stamps;
  exports mark them *collected before a later withdrawal* and the
  Companion surfaces that in plain language at merge-back (exact export
  behavior: decision Q-D). Nothing is silently deleted or silently
  kept.

## 3. Receipts (`deksync-consent-receipt`, v1)

One JSON per ceremony/continuation/withdrawal. **The JSON is
canonical**; the human-readable `.txt` is a deterministic rendering of
it, footered with the JSON's sha256, and regenerable — divergence is
detectable by regeneration (review finding C5).

```jsonc
{
  "format": "deksync-consent-receipt",
  "version": 1,
  "id": "<128-bit hex>",
  "kind": "ceremony" | "continuation" | "withdrawal",
  "refersTo": "<ceremony id>",            // + refersToSha256; non-ceremony kinds
  "prevReceiptSha256": "…",               // per-device hash chain (see below)
  "scope": {
    "taskId": "…", "baseCheckpointId": "…",        // task mode
    "wordlistFingerprint": "<sha256 of canonical wordlist>",  // plain mode
    "wordlistDescription": "<auto: filename, N words, imported <date>>",
    "statement": "<frozen researcher scope text>"
  },
  "prompt": {
    "modes": ["text", "audio"],
    "message": "<exact text shown>",
    "audioFile": "prompt-<sha256 first 8>.wav",    // content-addressed name
    "audioSha256": "…",
    "playback": { "completed": true, "playCount": 2 }   // evidence it PLAYED
  },
  "response": {
    "types": ["yesno", "record", "signature"],
    "signatureName": "…",
    "assentFile": "assent-<receipt id>.wav",
    "assentSha256": "…"
  },
  "speakerName": "…",                                    // per Q-C
  "timestamp": { "iso": "…", "local": "…", "timezone": "…" },
  "device": { "deviceId": "…", "appVersion": "…", "platform": "…" },
  "context": { "ipAddress": "unavailable", "approxLocation": "unavailable" }, // per Q-B
  "contentSha256": "<sha256 of canonical JSON minus this field>"
}
```

**Tamper evidence** (review finding C3 — must-fix): a random id proves
nothing about content. Three cheap, layered mechanisms:

1. `contentSha256` — hash of the canonicalized receipt JSON (excluding
   the hash field itself); every stamped item carries
   `receiptId + receiptSha256`, so editing a receipt after the fact
   orphans every stamp;
2. `prevReceiptSha256` — an append-only per-device hash chain across
   receipts, so deleting or reordering receipts breaks the chain;
3. prompt/assent audio hashes (as before) tie the audio bytes in.

**Playback evidence** (review finding C6): the hash proves which audio
was *configured*; `prompt.playback` records that it actually played.
UI rule: when `audio` is an enabled ask mode, the affirm control stays
disabled until the prompt audio has played to completion at least once.

Plain-mode scope identity (review finding S4): no task id exists, so
the receipt carries a **wordlist fingerprint** (sha256 of the imported
list's canonical form — the core already computes this) plus an
auto-generated human description.

## 4. Where each piece lives

| Piece | Home |
|---|---|
| `ConsentConfig` (axes, message, prompt-audio ref, scope statement, continuation policy + continuation content) + coherence validation | `dekereke_core`, parsed from `task.json`'s `consent` block (schema'd; unknown keys pass through) |
| `ConsentReceipt` build/parse/canonical-hash/chain/validate + deterministic `.txt` rendering + the §2.2 covering-receipt check in `validateResult` | `dekereke_core` |
| Prompt + continuation audio distribution | `.dektask` `consent/` member |
| Receipts + assent/prompt audio in results | `.dekresult` `consent/` member; `values[]`/`recordings[]` gain `receiptId`/`receiptSha256`; plain-mode ZIP gains the same `consent/` member |
| Ceremony + continuation UI, withdrawal route, receipt stamping, per-device chain | phone app (generalizes the consent screen; additive DB migration) |
| Consent config UI in the task builder; receipt archive alongside checkpoints (plan §5.3); withdrawal surfacing at merge-back | Companion (P3) |

Gate migration (review finding S5): today's `hasAssent()` (latest
consent row wins, device-lifetime) becomes *"a valid, unwithdrawn
receipt exists for the current scope"*. Existing `consent_records` rows
remain readable and continue to satisfy the gate ONLY for data
collected before the upgrade; the first post-upgrade import triggers a
proper ceremony (which trigger #1 does anyway).

## 5. Explicitly out of scope for v1

- Cryptographic *signatures* on receipts (device keys exist in the
  Worker design and could sign the chain later; the hash chain gives
  tamper *evidence* now, signatures would add tamper *attribution*).
- IP/geolocation capture unless Q-B says otherwise.
- Multi-speaker rosters on one device beyond the Q-C name field.

## 6. Decisions for Seth (record in HANDOFF log)

- **Q-A Continuation default**: `perDay` (recommended), `none`, or
  `perSession`?
- **Q-B IP/location capture**: omit in v1 (recommended — offline
  fieldwork, no location permission in the app today), or FlexText-style
  best-effort with a one-time permission ask?
- **Q-C Speaker identity**: optional free-text speaker-name field in the
  ceremony, researcher-configurable required/optional/off?
  (Recommended: yes, optional by default.)
- **Q-D Withdrawal + already-collected items**: export them normally but
  flagged (recommended — the researcher's own procedure decides), or
  hold them back until the researcher confirms?

## 7. Review log (what the adversarial panel changed in v1.1)

Confirmed findings folded in: plain-mode/task-re-issue scope hole →
trigger rule 2.3#1; non-configurable continuation content → 2.4;
receipts not tamper-evident → contentSha256 + stamps + chain (§3);
"covering receipt" undefined → §2.2 five-point definition; `.txt`
divergence undetectable → canonical-JSON rule (§3); playback
unevidenced → `prompt.playback` + UI gating (§3). Self-verified against
the code: no withdrawal UI route exists today (§2.5 correction); export
formats lacked a stamp carrier (§2.2); fixed prompt filename collided →
content-addressed names; plain-mode scope identity → wordlist
fingerprint; gate migration semantics (§4). Raised but unadjudicated
(session limit cut verification; judged low-risk or config-level):
signature-required configs vs non-literate speakers are the
researcher's configuration responsibility; aggressive OS app-kills make
`perSession` chatty (noted in 2.4); device-clock skew can misfire
`perDay` (accepted — receipts record the timestamps used).
