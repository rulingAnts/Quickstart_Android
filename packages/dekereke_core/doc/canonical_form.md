# Dekereke canonical form — specification

Status: implemented in `lib/src/codec/`; tested in `test/db_codec_test.dart`
against `test_data/dekereke_fixtures/` (format-faithful synthetic files,
verified against real Dekereke output 2026-07-02 — see `docs/HANDOFF.md`).

## Purpose

History and sync (plan §4.1) never store Dekereke's working file directly.
They store a **canonical form**: a deterministic, line-oriented, UTF-8/LF
rendering of the same database, so that

- editing one field changes exactly one line (meaningful diffs, tractable
  merges),
- identical content always renders to identical bytes (stable content
  hashes for identity, change-gating and dedupe),
- the working file Dekereke needs can be materialized from it exactly.

## The two representations

| | Working format (Dekereke's) | Canonical form (history's) |
|---|---|---|
| Encoding | UTF-16 LE **with BOM** | UTF-8, **no BOM** |
| Newlines | CRLF | LF |
| Declaration | `<?xml version="1.0" encoding="utf-16" standalone="yes"?>` | same with `encoding="utf-8"` |

Everything between the declaration and EOF is otherwise identical, so the
transforms are:

- canonical → working: swap declaration encoding, LF → CRLF (whole-string —
  safe because escaping guarantees no raw newlines inside values), encode
  UTF-16 LE + BOM.
- working → canonical: decode (BOM/sniff per `encoding.dart`), parse,
  re-render.

## Round-trip guarantees

1. **Byte-identity for Dekereke-written files:**
   `encodeWorkingFile(parseDekerekeFile(bytes)) == bytes` for files in
   Dekereke's own layout (tab indentation, CRLF, self-closed empties,
   trailing newline). Proven in tests against `synthetic_db.xml`.
2. **Fixed point for anything parseable:** one parse→render pass normalizes
   layout; further passes are byte-stable. Nothing semantic is ever lost.

## Document layout

```
<?xml version="1.0" encoding="utf-8" standalone="yes"?>        (line 1)
<phon_data>
	<data_form>          (one tab)
		<Field>…</Field>   (two tabs, ONE FIELD PER LINE)
	</data_form>
</phon_data>
                       (file ends with exactly one trailing newline)
```

An empty database renders as `<phon_data />`.

## Record model

Each `<data_form>` child becomes one of:

- **Value field** — element with no attributes and only text content: the
  cell of a named column. Text is preserved **exactly** (no trimming;
  interior whitespace runs, e.g. a meaningful double space in an IPA
  transcription, survive). Presence-only booleans (`<loan />`) are value
  fields with an empty value; *presence vs. absence* is the datum, so
  absent ≠ empty everywhere in this package.
- **Fragment field** — anything else (child elements — e.g. QuickVPlot's
  `<qvp_acoustic_data_>` — attributes, CDATA): preserved as raw XML and
  re-emitted verbatim (see Fragments below). Comments/CDATA/processing
  instructions sitting directly inside a record are kept as fragments under
  the reserved name `#raw`.

Field order within a record and record order within the file are preserved
exactly.

## Normalizations (deliberate, all semantic no-ops)

Applied when rendering; these are the only ways a re-rendered file can
differ from its source:

1. **Empty elements** render self-closing with a space (`<Notes />`),
   Dekereke's own style; `<Notes></Notes>` input is normalized to it.
2. **Escaping is pinned** (matching .NET's XmlWriter, which Dekereke uses,
   except where noted): text escapes `&` `<` `>` and additionally CR/LF as
   `&#xD;`/`&#xA;` (the LF escape deviates from .NET, which writes raw LF —
   required for the one-field-per-line property and the safe whole-string
   newline conversion; Dekereke reads `&#xA;` identically). Attributes
   escape `&` `<` the quote character and CR/LF/TAB.
3. **Structural whitespace** (indentation between elements) is regenerated
   deterministically for records; inside fragments it is preserved verbatim
   modulo CRLF → LF.
4. **Declaration** is regenerated exactly as shown above.

## Fragments (unknown XML)

Fragments round-trip verbatim: element structure, attribute order and quote
style, self-closing vs. `<x></x>` style, whitespace-only text nodes,
comments, CDATA and processing instructions are all preserved. The only
transformations are the pinned escaping (semantic no-op) and newline
normalization (CRLF ↔ LF between the two representations).

## Record order: preserved, not sorted

Plan §4.1 (draft v1) sketched "records in Reference order". This spec
deliberately **preserves file order** instead (decision D8 in
`docs/HANDOFF.md`):

- exact inverse: sorting is lossy — Dekereke's own record order could not
  be reconstructed, and whether that order matters to Dekereke is exactly
  open question P0 #3 (grid re-sort vs. file order);
- Reference is not a usable sort key anyway (duplicates and blanks are
  legal and present in real data);
- the identity ladder (plan §4.2) uses file position as a matching signal,
  which sorting would destroy.

Reference-ordered *views* are a display concern, not a storage one.

## Encoding detection (`encoding.dart`)

UTF-16 LE/BE BOM → UTF-8 BOM → sniff (`<` next to a zero byte ⇒ UTF-16 of
the corresponding endianness) → default UTF-8. Odd-byte-length UTF-16 is
rejected as corruption. This is the phone app's proven detector, ported
unchanged.
