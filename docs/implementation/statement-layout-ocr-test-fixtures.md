# Statement OCR layout diagnostics and test fixtures

Statements need both **lossless OCR evidence** and **readable spatial text** so
dates, merchant descriptions, debits/credits and amounts can be compared across
the same visual rows. The implementation reuses the position-aware test
infrastructure introduced for receipt fixtures, without changing production
statement parsing, local storage, or the app UI.

## Paired files

```text
apps/butlerly/test/core/evidence/fixtures/statement_layout_card.json
apps/butlerly/test/core/evidence/fixtures/statement_layout_card.txt
```

The synthetic JSON includes page order, image dimensions, original text,
recognition confidence, reading order, X/Y coordinates, and independent
`expectedRows` for transaction date, posting date, description and amount.
The TXT file reconstructs approximate row-and-column alignment from the
**unmodified** OCR coordinates, including page separators and vertical spacing.
It is not parsed to create transactions.

Example:

```text
                   HARBOR CARD
   Statement period: 2026-08-01 - 2026-08-31

   Purchase Date Post Date   Description             Amount

   8/15         8/17         SAFEWAY STORE          $42.19
   8/16         8/18         CAFE                   $8.25
```

This is a test-only reconstruction, not a pixel-perfect statement layout.
Use a monospaced text editor, do not collapse spaces, and keep JSON as the
source of truth. A lack of OCR bounding boxes falls back to recognition
order; it does not invent columns.

## Generate a TXT companion

From `apps/butlerly`:

```bash
dart run tool/generate_statement_layout.dart test/core/evidence/fixtures/statement_layout_card.json
flutter test test/core/evidence/statement_layout_fixture_test.dart
```

For full validation, run `./tool/validate.sh flutter_application` from the
repository root. Tests ensure the TXT snapshot exactly matches the geometry
rendering, JSON retains all OCR observations and multi-page structure, and
expected transaction fields are evaluated by the existing production
`LocalStatementExtractor.extractDocument` using original OCR observations.

## Privacy and accuracy

Statements can contain personal information, complete account numbers,
balances, and a transaction history. **Never commit real statement content
without explicit authorization and thorough sanitization.** Create
representative synthetic fixtures instead. JSON and TXT must both be redacted
before sharing; the human-readable TXT is not automatically safe. Existing
PAN redaction in production is unchanged.

A future development-only diagnostic view may display the aligned text
alongside parsed rows, confidence, source observation indexes and mismatch
reasons. This task does not add any iPhone or desktop UI controls.
