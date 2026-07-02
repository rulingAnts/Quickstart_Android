# Synthetic Dekereke fixtures

**Entirely synthetic data** (no Fayu or QWOM content — see licensing notes in
the main README), but **format-faithful**: structure and quirks were verified
against real Dekereke files and Casali (2019) on 2026-07-02. See
`docs/HANDOFF.md` for the verified ground-truth list.

Both files are genuine **UTF-16 LE with BOM and CRLF line endings** — exactly
what Dekereke writes. Do not "fix" their encoding; tests must consume them
as-is (`git diff` will treat them as binary; that's expected).

## `synthetic_db.xml`

A `<phon_data>` database exhibiting every quirk the core library must handle:

| Record | Exercises |
|---|---|
| 0001 body | boolean presence tag (`<loan />`), empty writable column |
| 0002 water (fresh) | nested `<qvp_acoustic_data_>` fragment (must round-trip verbatim), meaningful double space in Notes, filename with spaces/parens |
| 0002 water (in river) | **duplicate Reference** (legal in Dekereke, must merge losslessly) |
| (blank) ear | **missing Reference** (legal in Dekereke) |
| 0005 go / walk | multi-file SoundFile cell (`a.wav\|b.wav`), `<Confirmed />` boolean, gloss with `/` |

## `synthetic-DkUserSettings.xml`

Settings file with: machine-local paths (must NOT sync), TAB-separated
column→suffix mappings including irregular suffix styles (`-tf_Xhi` vs
`-tf-Xko`), `user_column_order`, `hidden_columns`, analysis settings.

Sound mapping rule: audio for a suffix-mapped column of a record =
`<SoundFile value minus .wav><suffix>.wav`
(e.g. record 0001, column Phonetic → `0001_body-phon.wav`).
