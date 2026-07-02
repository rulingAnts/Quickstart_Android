# P0 verification checklist — Dekereke on the Windows VM

Settles the P0 items in `docs/HANDOFF.md` (unknown-tag survival, save
order, backups, locking, recorder spec, separators) and the D1
sub-decision (which build to pin). Everything here uses **disposable
synthetic files** — nothing touches a real database.

**Time estimate: ~25 minutes.** Write answers in the blanks; when done,
zip the whole working folder and send it back (step 24).

## What's in this kit

| File | Purpose |
|---|---|
| `TestDB.xml` | 6-record database with planted probes (unknown flat tag on 0001, unknown *nested* tag on 0002, records deliberately out of order, pipe & comma multi-file cells, an empty-SoundFile record) |
| `TestDB-DkUserSettings.xml` | Suffix mappings: `Phonetic → -phon`, `SpeakerB → -spkB` |
| `TestDB-update.xml` | For *Update Current Data From File*: changes 0003, adds 0007, does NOT mention the probe records |
| `audio/*.wav` | Test tones at different pitches so you can tell files apart by ear (low = first file, high octave = second file) |

## A. Setup (steps 1–4)

1. ☐ On the VM, make a fresh folder, e.g. `C:\DekTest\`, and copy
   `TestDB.xml`, `TestDB-DkUserSettings.xml`, `TestDB-update.xml` and the
   `audio\` folder into it. (Getting the kit onto the VM: on GitHub,
   open the branch → **Code → Download ZIP**, then take
   `test_data/p0_test_kit/`.)
2. ☐ Open **the Dec-2025 rewrite** of Dekereke.
   Version shown (title bar / Help→About): ____________________
3. ☐ Open `C:\DekTest\TestDB.xml` as a database.
   Did it open without errors?  YES / NO — if no, what did it say?
   ____________________
4. ☐ In Dekereke's settings, point the **sound file folder** at
   `C:\DekTest\audio`.

## B. Probes in the grid (P0 #1 — look, don't touch)

5. ☐ Does the grid show a **ProbeFlatTag** column (record 0001 should
   show `PROBE-FLAT-SURVIVES`)?  YES / NO
6. ☐ Is the nested probe visible anywhere in the UI for record 0002
   (a `probe_nested_data` column, an odd cell, anything)?
   YES / NO — where? ____________________

## C. Save pass-through (P0 #1, #2, #3, #5)

7. ☐ **Without editing anything**, make Dekereke save the database
   (its usual save action). Then close Dekereke.
8. ☐ In Explorer, list `C:\DekTest\`. Write the **exact names** of every
   new file that appeared (this is the auto-backup pattern, P0 #5):
   ____________________
9. ☐ Open the saved `TestDB.xml` in **Notepad** and use Ctrl+F:
   - `PROBE-FLAT-SURVIVES` found?  YES / NO
   - `PROBE-NESTED-SURVIVES` found?  YES / NO
   - `<Confirmed` still present in record 0002?  YES / NO
10. ☐ Still in Notepad, check the order of `<Reference>` values in the
    file. The kit ships them as **0001, 0003, 0002, 0004, 0005, 0006**.
    Order in the saved file: ____________________
    (This tells us whether an untouched save rewrites record order.)
11. ☐ Reopen the database in Dekereke, click the **Reference column
    header** (or however you sort) so the grid re-sorts, save again,
    close. Reference order in the file now (Notepad):
    ____________________  ← P0 #3 answer
12. ☐ Did steps 7/11 change anything else visible in Notepad about the
    probe lines (attributes reordered, tags rewritten, spacing)?
    ____________________

## D. Update Current Data From File (P0 #1c)

13. ☐ In Dekereke, run **Tools → Update Current Data From File** with
    `TestDB-update.xml`.
14. ☐ Check the grid: 0003's Phonetic should now be `ɛnɔː` and a new
    record 0007 "star" should exist.  Both true?  YES / NO
15. ☐ Save, close, Notepad again:
    - `PROBE-FLAT-SURVIVES` still there?  YES / NO
    - `PROBE-NESTED-SURVIVES` still there?  YES / NO

## E. File locking / external edits (P0 #4)

16. ☐ Open the database in Dekereke and leave it open. In Explorer, try
    to **rename** `TestDB.xml`.  Windows lets you / refuses:
    ____________________
17. ☐ (Undo the rename if it worked.) With Dekereke still open, edit
    `TestDB.xml` in Notepad — change record 0004's Notes text — and
    save in Notepad. Does Dekereke react (warning, reload, nothing)?
    ____________________
18. ☐ Now save in Dekereke and check Notepad again: whose text is in the
    file (yours from Notepad, or Dekereke's copy)?
    ____________________

## F. Built-in recorder (P0 #6) — rewrite build only

19. ☐ Select record **0004 "sun"** (its SoundFile is empty on purpose)
    and record a short clip with Dekereke's built-in recorder.
    - Did the **SoundFile** cell get filled in?  YES / NO —
      with what value? ____________________
    - What file appeared in `C:\DekTest\audio\`? ____________________
20. ☐ If the recorder can target a **column** (e.g. SpeakerB, which is
    suffix-mapped to `-spkB`), record into it for record 0001.
    Filename created: ____________________
21. ☐ Keep every WAV the recorder created in the folder for the zip —
    we read sample rate / bit depth / channels from the file headers.

## G. Multi-file cells (P0 #7)

The two candidate separators each pair a LOW tone with a HIGH tone
(an octave up): low = first filename, high = second.

22. ☐ Record **0005 "go / walk"** — cell is `0005_go.wav|0005_go_alt.wav`
    (pipe). Trigger playback:
    - What plays? LOW tone / HIGH tone / both in a row / error
    - Does the UI show or offer both files? ____________________
23. ☐ Record **0006 "moon"** — cell is `0006_moon.wav, 0006_moon_alt.wav`
    (comma + space). Same questions:
    - What plays? LOW / HIGH / both / error
    - Both files offered? ____________________

## H. Report back

24. ☐ Zip the entire `C:\DekTest\` folder (saved XMLs, every backup file,
    all audio) and send it together with this filled-in checklist.
25. ☐ Optional but valuable (P0 #2): if the legacy 1.0.0.313 build is
    still installed, repeat sections A + C with a fresh copy of the kit
    in a second folder (e.g. `C:\DekTestLegacy\`) and include that
    folder in the zip too.

---

*Kit generated by `packages/dekereke_core/tool/generate_p0_kit.dart` —
regenerate with `dart tool/generate_p0_kit.dart` from the package root.*
