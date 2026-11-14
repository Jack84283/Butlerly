# Receipt layout-preserving OCR fixtures (test infrastructure)

## Purpose

Retail receipt field extraction can misidentify a merchant or payable total
even when OCR recognized every word. Flat text examples hide left/right
alignment and the relationship between labels and amounts. This test-only
format keeps the *actual OCR observation stream* and renders a readable
receipt-like view for diagnosis.

It does **not** replace the OCR engine, change production extraction
algorithms, add application UI, or change SQLite/evidence persistence.

## Fixture format

See `apps/butlerly/test/core/evidence/fixtures/receipt_layout_grocery.json`.

Each fixture has:

- `id`: stable synthetic scenario name.
- `pages`: page index, optional image dimensions/orientation, and original OCR
  observations. Each observation keeps text, confidence, order, page index and
  either original `bounds` or the original `left/top/width/height` values.
  Positions are in the same coordinate system as the OCR contract (typically
  normalized).
- `fullText`: optional unaltered OCR document text.
- `diagnostics`: source type and selected OCR counters.
- `expected`: independent, manually verified field labels, such as merchant,
  amount, currency, date, tax and tip.

The source of truth is the observation array, **not** the reconstructed
receipt view. The test calls production `ReceiptExtractor.extract` with
`document.text` and **the original observations**, without normalizing,
merging, or repairing text first.

## Example

The sample fixture renders approximately as:

```text
          WHOLE FOODS MARKET
                Palo Alto, CA
      Date: 11/12/2026

      Organic Milk                                     5.99
      Bread                                            4.50
      SUBTOTAL                                        10.49
      TAX                                              0.42
      TOTAL                                          $10.91
      VISA                                            10.91
      CHANGE                                           0.00
```

This is a *human-readable approximation* derived from normalized X/Y
coordinates, not a pixel-perfect reconstruction. If positions are absent,
the output uses the untouched OCR reading order rather than inventing
columns. Multi-page fixtures have visible page separators.

## Companion aligned text file

Each JSON fixture can have a generated `.txt` file next to it:

```text
receipt_layout_grocery.json   # Original OCR observations + expected fields
receipt_layout_grocery.txt    # Generated spatial preview, NOT parser input
```

From `apps/butlerly`, run:

```bash
dart run tool/generate_receipt_layout.dart test/core/evidence/fixtures/receipt_layout_grocery.json
```

The command writes or updates `receipt_layout_grocery.txt` next to the JSON,
keeping recognized text in its approximate horizontal and vertical positions.
The output is plain UTF-8 text; open it using a **monospaced font** with
whitespace preservation. Incomplete geometry falls back to the OCR reading
order rather than inventing an alignment. It cannot reconstruct icons or
images; original image data is not embedded in the text.

The checked-in sample `.txt` is asserted in tests to be identical to the
rendering produced from the corresponding `.json`, preventing stale or
manually altered snapshots. Do not feed the formatted text back into
`ReceiptExtractor`: the JSON observations retain authoritative coordinates
and are the sole source for extraction regression tests.

**Privacy:** Both files can contain readable financial and personal
information. Generate locally and redact source observations *before*
exporting fixtures for review or committing them. The sample is synthetic.

## TXT-first derived JSON (developer workflow)

Receipt scan diagnostics now use the same two-stage workflow as statement
fixtures:

```text
Original receipt OCR evidence (*.json, including coordinates)
  -> render and write position-aligned *.txt FIRST
  -> read the saved TXT contents back from disk
  -> derive *.extracted.json from that saved TXT
```

The new `receipt_layout_grocery.extracted.json` contains conservative,
line-referenced candidates for merchant, date, subtotal, tax, tip and total,
plus unparsed source lines. It distinguishes SUBTOTAL from TOTAL and does not
invent missing amounts or OCR confidence. Ambiguous names are explicitly
labeled `merchantCandidate`, not treated as verified merchants.

Run from `apps/butlerly`:

```bash
dart run tool/generate_receipt_layout.dart test/core/evidence/fixtures/receipt_layout_grocery.json
```

This writes `receipt_layout_grocery.txt` and then derives
`receipt_layout_grocery.extracted.json` from the text **as saved**. The
original OCR evidence JSON remains necessary because exact bounding boxes,
reading order and confidence cannot be reconstructed from plain text.

This functionality is developer/test tooling only. It does **not** yet change
the live iPhone receipt scanning pipeline, saved transactions, or production
extraction heuristics. Tests compare the derived JSON to the TXT snapshot
without using fixture expected values. Do not share generated outputs before
redacting private receipt or card information.

## iPhone receipt capture: position-aligned preview

The receipt capture page now uses the original OCR observations' normalized
bounding boxes to display `Extracted source text` approximately as laid out
in the scanned receipt. It uses a monospaced font and horizontal scrolling so
left-hand labels and right-hand values are not flattened into reading order.

This **only changes the live diagnostic preview**. The original OCR text and
observations remain the inputs for parsing and the original source evidence
remains preserved. If all geometry is missing, the preview falls back to unchanged reading-order
text. With partial geometry, bounded observations remain position-aligned and
unbounded lines are listed in a clearly marked reading-order fallback section.

The on-device view is a selectable approximation, not a new persisted TXT
attachment. The offline developer generator above is still the tool for
creating paired `.txt` and `.extracted.json` regression artifacts. OCR may
misread or miss labels; no coordinates are fabricated and no existing
transaction values are silently rewritten.

## Running

From `apps/butlerly`:

```bash
flutter test test/core/evidence/receipt_layout_fixture_test.dart
```

Run the full Flutter validation gate before merging:

```bash
./tool/validate.sh flutter_application
```

The latter command is executed from the **repository root**.

`ReceiptLayoutFixture.encodeDocument(...)` accepts an `OcrDocument` and
writes JSON with the original observation geometry; it intentionally has no
OCR-provider dependency. The fixture's `layout` and `diagnosticReport` are
for test-failure output only. The report compares selected fields, shows
expected/actual values and the production extractor's field evidence.

## Failure triage

1. Capture one failed receipt's OCR observations *locally*.
2. Inspect the original OCR lines and bounding boxes, not just flattened text.
3. Create a fixture after redacting personal information, card data, addresses,
   loyalty numbers and other sensitive values; use a synthetic reconstruction
   when possible. Never commit raw user receipts or personal data.
4. Write independently verified `expected` fields.
5. Reproduce the mismatch with the **unchanged** production extractor.
6. Only then change extraction/ranking logic in a separate focused PR.

Test fixtures must not automatically rewrite actual or expected values to make
tests pass. Actual receipts may reveal new layout problems beyond the synthetic
sample; this first PR supplies the test format and baseline, not a claim that
the existing extractor is accurate on all merchant layouts.
