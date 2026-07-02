# `.dektask` / `.dekresult` — package formats

Status: implemented in `lib/src/task/task_package.dart`; tested in
`test/task_package_test.dart`. Plan §5.2.

Both are plain ZIP files. Encoding is deterministic (fixed timestamps,
sorted member order): the same package always produces the same bytes.

## `.dektask` — researcher → phone

| Member | Content |
|---|---|
| `task.json` | envelope below |
| `wordlist.xml` | the subset database, **canonical UTF-8** (`doc/canonical_form.md`) — the phone parser accepts it as-is |
| `audio/<name>` | reference recordings for playable fields — WAV, or FLAC-compressed to save bandwidth (decision D3's single FLAC exception: DB→phone, playback-only) |
| `pictures/<name>` | optional picture prompts |

`task.json`:

```json
{
  "format": "dektask",
  "version": 1,
  "taskId": "task-001",
  "title": "Yohanis records his pronunciation",
  "baseCheckpointId": "checkpoint-42",
  "createdAt": "2026-07-02T12:00:00Z",
  "fields": [
    {"column": "Gloss",    "role": "visible"},
    {"column": "SoundFile","role": "playable", "suffix": ""},
    {"column": "Yohanis",  "role": "writable", "input": "both", "suffix": "-yoh"}
  ],
  "records": [
    {"id": "<DkSyncID>", "reference": "0001"}
  ],
  "consent": { "…phone app's consent config, passed through verbatim…" }
}
```

- `records` is the **ID map**: entry *N* gives the DkSyncID of record *N*
  of `wordlist.xml` (aligned by position — mandatory, enforced on decode).
  Per decision D2, IDs travel here and in the sidecar, **never inside the
  wordlist XML**.
- `reference` is a display label only.
- `role`: `visible` (read-only prompt) / `playable` (audio per the suffix
  rule) / `writable`. Writable fields must declare `input`:
  `text` | `audio` | `both`. Audio-collecting fields carry the `suffix`
  their recordings are named with (`<SoundFile base minus .wav><suffix>.wav`).
- `baseCheckpointId` names the checkpoint the subset was cut from;
  merge-back is 3-way against exactly that checkpoint (plan §5.3).

## `.dekresult` — phone → researcher

| Member | Content |
|---|---|
| `result.json` | envelope below |
| `audio/<name>` | new recordings, already named `<base><suffix>.wav` — ALWAYS 16-bit mono WAV (decision D3); never FLAC in this direction |

`result.json`:

```json
{
  "format": "dekresult",
  "version": 1,
  "taskId": "task-001",
  "baseCheckpointId": "checkpoint-42",
  "completedAt": "2026-07-03T09:00:00Z",
  "values":     [{"id": "<DkSyncID>", "column": "Yohanis", "value": "bɔdi"}],
  "recordings": [{"id": "<DkSyncID>", "column": "Yohanis", "filename": "0001_body-yoh.wav"}],
  "consentLog": [ "…phone app's consent log entries, verbatim…" ]
}
```

`validateResult()` checks a result against its task (task/checkpoint match,
known record IDs, writable columns only, audio-collecting columns only,
listed recordings present) and returns plain-language problems.
`applyResultValues()` turns a result into the "theirs" side of the 3-way
merge-back, so only cells in (task records × writable columns) can differ.

## Versioning

Both envelopes carry `format` + integer `version`. Decoders accept
`version <= supported` and refuse newer files with an "update the app"
message. Additions must be backward-compatible within a version (readers
ignore unknown keys); breaking changes bump `version`.
