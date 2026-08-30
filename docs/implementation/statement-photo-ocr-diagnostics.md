# Statement-photo OCR diagnostics and hardening

Date: 2026-08-29

Base: `d574d51d3b036a2d9635ee3b3e300ac31c0ca53e` (merged statement review UX).

## Confirmed diagnosis

Synthetic observations reproducing normal Vision column output exposed a
deterministic reconstruction failure. With a small photo-perspective slope,
the amount at `top=.29`, merchant at `.31`, and date at `.33` were separate
visual groups. The old reconstruction loop discarded the amount and merchant
before encountering its required date anchor. It then discarded the date-only
group. Useful OCR therefore produced **zero candidates**.

A merchant-plus-amount row with an unreadable date was also discarded because
the reconstruction loop never started a row without a date. Both cases were
first added as regression tests and failed with an empty result before the fix.

Additional reproduced defects were:

- a separately recognized `$` remained in the merchant description;
- the first two transaction dates anywhere in the source were treated as a
  statement period, permitting unsupported year inference;
- `02/30` could overflow to March 2 during inferred-year construction;
- a native observation with `order=0` on a later page was renumbered by Dart;
- the capture/review UI displayed a generic no-rows state even when a stored
  extraction message identified a different failure.

The original physical-iPhone photo and its native output were not supplied.
These are confirmed pipeline defects, **not proof that Vision succeeded on that
particular photo**. The new device diagnostics distinguish that remaining case
without requiring the owner to share financial text or the image.

## Pipeline and privacy

1. The selected photo is copied byte-for-byte into Butlerly's local evidence
   directory before OCR.
2. Native diagnostics mark invocation, image decoding, pixel dimensions,
   UIImage orientation, Vision observations, recognized lines, valid bounding
   boxes, and minimum/average/maximum OCR confidence.
3. All eight UIImage orientations retain their corresponding Vision orientation,
   including mirroring. No image preprocessing, rescaling, cloud service, or
   network dependency was introduced.
4. The MethodChannel retains observation text, confidence, geometry, page, and
   order. A native/received count mismatch is a technical channel failure, not
   an empty successful extraction.
5. Reconstruction estimates bounded page skew from matching OCR columns,
   compares adjusted row geometry, then revisits isolated fragments after
   neighboring rows exist. Equally plausible associations and unsupported
   sparse-column extrapolation stay unresolved. Currency and direction defaults remain at the
   application intake boundary; a bare dollar sign is not asserted as USD.
6. The original image remains unchanged. OCR source text is retained as a
   separate extraction record, with the existing PAN redaction, while edited
   row fields remain separate from original row evidence.
7. Debug output contains only stage labels, format categories, counts,
   dimensions, orientation, and confidence summaries. It does not print paths,
   filenames, merchant descriptions, amounts, account numbers, PANs, or raw OCR
   text. No redacted text samples were necessary.

## Real-device diagnostic procedure

1. Run this branch as a **Debug** build on the physical iPhone.
2. Open Statements and capture or select the same statement photograph.
3. Open that statement's overflow menu and choose **Extraction diagnostics**.
4. Choose **Copy** and share the compact summary. Do not share full statement
   text or an unredacted photograph.

The same summary appears in the debug console under `Butlerly statement OCR`.
Native stage summaries use `ButlerlyLocalOcr`. The menu entry is absent from
release builds. Diagnostics are held only for captures in the current session;
capture the photo again after restarting if the entry is unavailable.

Example shape (illustrative counts, not a claim about the owner's photo):

```text
OCR: 84 observations
Native: 84 Vision observations, 84 channel observations, 84 lines, 84 bounded
Image: 3024x4032, orientation right
OCR confidence: 0.410 / 0.870 / 0.990 (min/avg/max)
Visual rows: 27
Candidates: 18
Unresolved: 4
Ignored: 5 rows, 12 observations
Outcome: reconstructedCandidates
```

Interpretation:

- `noText`: the native call succeeded but no readable text was available.
- `textWithoutCandidates`: text existed but no plausible transaction region was
  reconstructed.
- `unresolvedEvidence`: all surviving candidates require field correction.
- `reconstructedCandidates`: at least one candidate has the core date, amount,
  and description; partial candidates may also be present.
- `technicalOcrFailure`: inspect `Failure stage` (`imageOpen`,
  `visionRecognition`, or `methodChannel`) and the safe error code.

An absent extracted currency/direction is not a fabricated fact. The existing
application intake defaults are explicitly recorded in row source context.
Extraction confidence remains separate from duplicate confidence; `.49` and
`.50` require review, while `.51` does not solely because of confidence.

## Verification coverage

| Requirement | Verification |
| --- | --- |
| Offset/skewed date, merchant, amount observations | `statement_extractor_test.dart` geometry regressions, including amount-first zero-row reproduction and adjacent rows |
| MM/DD, two/four-digit year, ISO date, posting date | Extractor date and posting-date tests |
| Reliable year context and invalid dates | Period-label and calendar-overflow regressions |
| Multiline descriptions and numeric merchant text | Extractor multiline and amount-column tests |
| Split dollar sign, grouped/negative/parenthesized amounts, CR/CREDIT/DR/DEBIT | Extractor amount-format matrix |
| Missing date/amount/description survives | Extractor partial-row regressions and capture-to-SQLite reload test |
| Headers/balances excluded and ignored counts | Extractor diagnostics test |
| Empty OCR vs text without candidates vs technical failure | Channel-to-parser tests plus capture/review UI tests |
| Native fields survive MethodChannel | `statement_ocr_pipeline_test.dart`, including later-page `order=0` |
| `.49`, `.50`, `.51` review threshold | Existing `statement_batch_import_test.dart` retained |
| Original bytes/raw text retained, intake defaults do not rewrite evidence | Capture/evidence/SQLite integration test and PAN-redaction regression |
| Native JPEG/HEIC and all orientations | `RunnerTests.swift` native tests |
| Diagnostics do not expose financial content | Content-free summary assertions and native log audit |

## Validation and review evidence

- Toolchain: Flutter 3.47.1 / Dart 3.13.1 on macOS arm64, matching the repository pin.
- Focused extractor, MethodChannel, receipt OCR regression, platform-support,
  and capture/reload tests: **72 passed**.
- `./tool/validate.sh`: domain **28 passed**, database **28 passed**,
  application **75 passed**; static analysis clean in all packages and Flutter.
  Flutter tests: **165 passed, 5 failed**. The same five failures were reproduced
  on unchanged `main` before implementation: the macOS Home golden and four
  add-editor duplicate-dialog interaction tests (Use Existing, Continue Anyway,
  Cancel, multiple candidates). No Home or transaction-editor changes were made.
- The validation script stops at those failures. `flutter build web` was run
  separately and passed, including its Wasm dry run.
- Final `flutter build ios --simulator --no-codesign`: passed.
- Native `RunnerTests`: **4 passed** on iPhone 17 Pro / iOS 26.5 simulator:
  actual Vision recognition of generated JPEG and HEIC files, all eight
  orientation mappings, and explicit image-open failure. Neither format test
  was skipped.
- Two end-to-end self-review cycles covered requirements and UI reachability,
  channel/capture/application integration, evidence write/read/reload,
  amount/date/default semantics, failure outcomes, privacy, and adjacent receipt
  regressions. The first cycle corrected close posting-date column grouping,
  ambiguous multi-year inference, currency-code substrings in merchant names,
  complete credit/debit markers, and accidental merging of a later undated row.
  Each has regression coverage. The second cycle found no further consequential
  defect; full validation was repeated after the corrections.
- `git diff --check`: passed. Validation-induced application lockfile changes
  were excluded; no dependency or schema changes are part of this task.
- The first fresh independent review found two P2 issues: split currency
  symbols combined with numeric merchants and amount headers could select the
  merchant number, and a dated NEW BALANCE purchase could be excluded as a
  summary. Both were reproduced with failing tests and corrected. Monetary
  component matching now retains geometry across split symbols; equally
  positioned alternatives remain unresolved. Dated NEW BALANCE purchases are
  retained. Three regression tests
  cover these combinations and ambiguous single-observation amounts. An
  additional self-review covered the corrected production path and repeated
  validation. The second fresh review found a P2 regression where the broad
  dated-row exemption admitted balance summaries. The exemption was narrowed;
  balance-forward, previous/opening/closing/statement-balance labels remain
  excluded even with dates. A regression matrix reproduced the failure and
  verifies all five labels. A further self-review and full validation followed.
  The third fresh review found P2 issues with a numeric merchant beside an
  unreadable amount, and cross-associated dates in densely spaced skewed rows.
  Unformatted integers now require actual amount-column evidence; a global
  header is insufficient. Grouping retains neighboring compatible rows and
  preserves vertical column order instead of considering only the newest row.
  Combined regressions cover missing amounts, actual integer amounts, and dense
  rows in both slope directions. Self-review and validation were repeated.
  The fourth review found a P1 missing-amount attribution regression in that
  first-compatible grouping. It was replaced by bounded skew estimation,
  adjusted-position matching, and a second isolated-fragment pass. Nearly tied
  matches and unsupported extrapolation explicitly clear uncertain financial
  fields and cap confidence at .50. Regression matrices cover missing dates
  and amounts in aligned and both skew directions; a separate tie case proves
  no financial value is guessed and the original amount evidence survives.
  Existing complete-row tests still assert exact dates/amounts. Self-review and
  full validation were repeated after these corrections.
  The fifth review found a P2 continuation merge between a dated row missing
  its amount and an undated merchant/amount row. Independent transaction-like
  groups now stay separate when the pending row already has merchant or amount
  evidence. Date-only continuations remain supported. Text-fallback and
  Vision-observation regressions assert two unresolved rows and unchanged
  original evidence. Self-review and validation were repeated.
  The sixth review found a P2 integration gap where an unreadable description
  could survive extraction but miss Needs Review after batch import. Unresolved
  required-field evidence now caps extraction confidence at .50, and capture
  respects the unresolved reason when setting row status. A real capture →
  batch import → SQLite reopen → Review query test reproduces and verifies the
  persisted review issue, imported amount, and unchanged original text.
  A final fresh independent review was started in a separate read-only
  context after these corrections, but the reviewer hit the account usage
  limit before returning a verdict. This environment therefore cannot claim
  an independent no-findings result; the completed self-review and validation
  evidence above remain the available pre-push quality evidence.

## Remaining limitations

- The exact failure stage of the owner's physical-iPhone photo still needs one
  captured diagnostic summary. Synthetic and simulator evidence cannot replace
  that observation.
- This remains deterministic OCR reconstruction, not a universal statement
  parser. Severe blur, occlusion, extreme perspective, or unsupported layouts
  may produce unresolved candidates or no candidates; the UI now states which.
- Native image tests use generated non-sensitive statement-like text. They do
  not claim device-camera validation or access to personal financial evidence.
