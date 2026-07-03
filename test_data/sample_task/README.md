# Sample task — phone smoke test for task mode

`sample.dektask` is a ready-made task package for testing the app's task
mode end-to-end on a real device:

1. Get `sample.dektask` onto the phone (download from GitHub, or share
   from another device).
2. In the app: **Import Wordlist → select the file** (the picker accepts
   `.dektask` alongside `.xml`).
3. Elicitation now shows the task layout: Gloss + Indonesian prompts, a
   **Listen** button (records 0001/0002/0003/0005 have reference tones at
   different pitches; 0004/0006 have none on purpose), and a writable
   **Yohanis** section with a text box and its own mic.
4. Answer a few words (type and/or record), then **Export My Answers** —
   the app writes a `.dekresult` you can share off the phone.
5. To sanity-check the export, `dekereke_core`'s `decodeDekResult` /
   `validateResult` accept it (recordings should be named
   `<base>-yoh.wav`).

Import a plain `.xml` wordlist afterward to leave task mode.

Regenerate this package with
`dart tool/generate_sample_dektask.dart` from `packages/dekereke_core`.
