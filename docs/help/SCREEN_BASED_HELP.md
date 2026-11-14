# Butlerly screen-based Help — implementation mapping

Source approved for implementation: https://docs.google.com/document/d/1Ja-o0oqlYivVvWFoxVeHYxguCg5XgmuGCJbZlxJkVtM/edit

The application bundles three offline Help languages (English, Simplified Chinese, Spanish). The approved nine chapters are the sole visible guide structure, with 42 screen/function topics nested in the appropriate chapter. Detailed instructions formerly stored in chapters 1–25 and appendices A–D have been migrated into their new target articles; the legacy entries are removed. FAQ links have been migrated to new stable topic IDs. Each topic uses the same stable ID in each language. The English screen topic uses the approved Google Doc text; the Chinese and Spanish editions include localized screen guidance and retain the migrated, locally bundled detailed instructions.

## Routes and contextual Help

| Route | Topic ID |
| --- | --- |
| `/welcome` | `ch-2` |
| `/` | `home.overview` |
| `/transactions` | `transactions.list` |
| `/transactions/add` | `add.manual` |
| `/add` | `add.overview` |
| `/tools` | `tools.overview` |
| `/rules` | `tools.rules` |
| `/payment-settlements` | `tools.settlements` |
| `/settings` | `more.overview` |
| `/legal-licenses` | `more.about` |
| `/analysis` | `tools.analysis` |
| `/insights` | `tools.insights` |
| `/budgets` | `tools.budgets` |
| `/financial-profile` | `more.financial-profile` |
| `/review` | `tools.review` |
| `/search` | `transactions.search` |
| `/payment-sources` | `add.payment-source` |
| `/import-export` | `add.import` |
| `/statements` | `add.statement` |
| `/receipts/capture` | `add.receipt` |
| `/privacy-data` | `more.privacy` |
| `/master-data` | `tools.master-data` |
| `/notifications` | `more.operational-features` |
| `/assistant` | `tools.assistant` |

Fallback for a new route: `guide.getting-started`. `/help` and `/launch` intentionally have no contextual Help button.

## Verification before merging

- Run `./tool/validate.sh flutter_application` and all help/catalog tests.
- Check in-app Help index grouping on narrow and desktop layouts, search, direct deep links, return navigation, and offline behavior.
- Check the question-mark targets on every route, plus modal/bottom-sheet overrides for settlement detail, receipt capture, transaction editors and restore.
- Check all three translations in both mobile and desktop views and confirm financial terminology.
- Keep FAQ IDs intact and verify old FAQ cross-links resolve.
- Verify the Export-to-File plaintext warning in all three languages.
- Do not merge until CI passes and manual verification is completed.
