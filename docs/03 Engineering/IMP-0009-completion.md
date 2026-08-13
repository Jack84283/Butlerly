# IMP-0009 — Local Evidence Storage Completion

Status: Implemented local P0 slice

## Delivered

- Local receipt, photo, and PDF selection from transaction detail.
- App-owned private evidence directory with opaque local filenames.
- SQLite evidence metadata and transaction attachment links.
- Retrieval of linked evidence metadata in transaction detail.
- Explicit evidence removal that deletes metadata, links, and local bytes.
- Permanent transaction deletion cleanup for linked evidence.
- Erase-all cleanup for all evidence metadata and local files.
- Local export copies evidence alongside the structured finance JSON export.
- No evidence contents or sensitive local paths are written to application logs.

## Semantics

- Archiving a transaction retains linked evidence so restoration is complete.
- Permanent transaction deletion removes linked evidence first.
- Erase-all removes every local evidence file and all SQLite user data.
- Unsupported source processing remains disabled; attaching evidence does not imply extraction succeeded.

## Verification

- SQLite repository round-trip and removal coverage.
- Local export/erase integration coverage with a temporary evidence directory.
- Flutter analysis and transaction lifecycle coverage.
