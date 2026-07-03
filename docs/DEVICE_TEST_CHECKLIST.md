# Device test checklist — Android + Windows

What Seth needs to verify by hand on real hardware (or the emulator —
see [`EMULATOR_SMOKE_TEST.md`](EMULATOR_SMOKE_TEST.md)). Tick the boxes,
note anything odd next to them. Total: ~45 min Android, ~40 min Windows.

## Android (phone or AVD) — the elicitation app

Install: **Actions → newest green CI run → `wordlist-elicitation-apk`
artifact** → unzip → install `app-release.apk` (sideload / drag onto
emulator).

### A. Plain mode (~15 min — this also closes PR #5's pending smoke test)

1. ☐ Import a Dekereke XML (use `test_data/p0_test_kit/TestDB.xml` —
   already UTF-16 like real files). Import report shows 6 entries,
   with a duplicate/missing-Reference note? (TestDB has none of those;
   `test_data/dekereke_fixtures/synthetic_db.xml` has both if you want
   to see the skip messages.)
2. ☐ Start Elicitation → the consent screen appears BEFORE any word.
   Complete it (try the verbal option: record spoken assent).
3. ☐ Elicit 2–3 words: type an IPA transcription, record audio, play it
   back, Save & Next. Progress counter and green checkmarks update.
4. ☐ Recording safety: start recording, press Previous mid-recording →
   no broken take saved; re-record a word, DON'T save, leave → the old
   recording is untouched.
5. ☐ Force-close the app, reopen, Start Elicitation → it resumes at the
   first incomplete word.
6. ☐ Export Data → ZIP is created and shareable. (Keep this ZIP — you'll
   open its `wordlist_data.xml` on Windows in step F3.)
7. ☐ Deny the mic permission once (fresh install or via app settings) →
   recording shows a clear error, no crash; re-grant → works.

### B. Task mode (~15 min)

8. ☐ Import `test_data/sample_task/sample.dektask` (picker accepts it).
   Status shows the task title + "6 words to work on".
9. ☐ Elicitation shows the TASK layout: big Gloss, Indonesian below,
   a **Listen** row, and a **Yohanis** section with text box + its own
   mic.
10. ☐ Listen plays a tone on words 0001/0002/0003/0005; words 0004 and
    0006 say the recording wasn't included (that's on purpose).
11. ☐ Answer a few words (text and/or recording), Save & Next; go back —
    saved answers reload.
12. ☐ Export → button reads **Export My Answers** and produces a
    `.dekresult` file; share it off the device. (Keep it for F4.)
13. ☐ Import a plain XML again → app returns to normal (non-task) mode,
    with a warning that collected answers would be replaced.

### C. Audio quality spot-check (~5 min, can be done on Windows)

14. ☐ Pull one recorded WAV out of an export, open in Audacity (or file
    properties): **16-bit PCM, mono, 44.1 kHz** (decision D3), name is
    `<SoundFile base>.wav` (plain) / `<base>-yoh.wav` (task).

## Windows — Dekereke VM + Companion

### D. Dekereke P0 verification (~25 min, the important one)

15. ☐ Run **[`test_data/p0_test_kit/CHECKLIST.md`](../test_data/p0_test_kit/CHECKLIST.md)**
    end-to-end on the Dec-2025 build; fill in the blanks; zip the folder
    back. This settles the pinned-build decision (D1) and all seven P0
    format unknowns — it unblocks the canonicalizer details and the
    recorder/separator questions.

### E. Companion desktop scaffold (~5 min)

16. ☐ **Actions → "Companion desktop" workflow → newest run →
    `dekereke-companion-windows` artifact** → unzip → run
    `dekereke_companion.exe`. It opens with three areas in a left rail.
17. ☐ Health check → Open database… → the P0 kit's `TestDB.xml` →
    "6 words". With the kit's `audio` folder sitting next to the XML it
    should also report missing suffix recordings; with
    `synthetic_db.xml` (fixtures folder) it must flag one duplicate
    Reference and one empty Reference, in plain language.
18. ☐ History and Sync tabs show their "coming later" descriptions
    (checking the shell renders, nothing more).

### F. Cross-device round trips (~10 min — the real proof)

19. ☐ Phone plain-mode export from step 6: unzip on Windows, open
    `wordlist_data.xml` in Dekereke. It loads; transcriptions are in
    Phonetic; special characters (ɔ, ɸ, ʔ) look right; audio files play
    from the bundled `audio/` folder once pointed at it.
20. ☐ Phone task export from step 12: unzip the `.dekresult`;
    `result.json` lists your values/recordings keyed by ID; the WAVs
    play and follow the `-yoh` suffix naming.

## Reporting back

For anything that fails: which step number, what you saw (screenshot if
easy), and — for Dekereke steps — the exact build version. Everything
else in the project is CI-verified; these 20 boxes are precisely the
part machines can't do.
