# Backup & Restore — Simplified Architecture

This document records the approved replacement for Butlerly's previous
validation-oriented backup implementation. It applies to the draft clean-branch
rewrite and is not a claim that the replacement is production-ready.

## Contract

- **Backup copies source data.** Capture a consistent, byte-for-byte SQLite
  snapshot with SQLite's native snapshot operation. Package all available
  original attachment files. Record unavailable attachments as warnings.
- **Restore recovers source data.** Authenticate the archive, extract to a new
  private staging directory, verify checksums and physical SQLite integrity,
  and activate only with a separately tested rollback/restart strategy.
- **Reports diagnose data.** No analysis-rule, merchant, category, budget,
  generated-finding, or other business-rule validation runs in backup/restore.
  Data Integrity Reports must remain read-only and independent.
- **No automatic repair.** Never rewrite original financial records to make an
  archive pass; never reconstruct an absent receipt from unrelated data.
- **Privacy and safety.** Encrypt and authenticate the exported package; keep
  cryptographic verification, path containment, crash consistency, and safe
  destination publication.
- **Legacy formats.** New backups need not support old archive formats. Existing
  backup files must not be removed or modified. An older unsupported archive
  must be rejected with a clear explanation, not called corrupt.
- **Historical SQLite schemas.** Before activation, read the decrypted SQLite
  source version and physical integrity. If the source schema is older, apply
  the app's ordered database migrations on the extracted *staging database*,
  with catalog seeding disabled. The encrypted archive stays unchanged.
  Reject future, unversioned, malformed, or un-migratable SQLite schemas.
  This applies to both Replace and Merge and is not business-rule repair.

## Device-independent compatibility contract

A backup is portable across Butlerly installations. Restore does not attempt to
identify its original device or distinguish same-device recovery from transfer.
The encrypted archive includes a full native SQLite snapshot, original evidence
bytes, relative evidence paths, timestamps, archive format metadata, and
checksums. It does **not** include any source device ID, hardware identifier,
installation ID, source OS, or device fingerprint for compatibility decisions.
SQLite's `PRAGMA user_version` within the snapshot is the authoritative
database schema version; no duplicate device-specific field is necessary.

Compatibility always compares the backup SQLite schema against the **installed
destination app's supported SQLite schema**, regardless of where or when the
backup was created:

| Backup schema | Installed app supports | Restore behavior |
| --- | --- | --- |
| 17 | 17 | Restore without a schema migration |
| 17 | 19 | Migrate staged SQLite 17→18→19, then Restore |
| 19 | 17 | Reject before confirmation and explain how to update Butlerly |
| 19 | 19 | Restore without a schema migration |

These rules apply to both **Replace** and **Merge**, and to backups made before
or after an app update on the *same* device. A backup from a newer schema must
never downgrade or mutate the installed app's database. The original encrypted
archive is never modified by restore or migration. After an app update,
users may retry the same backup without recreating it.

The update prompt provides Apple App Store, Google Play, Mac App Store, or
trusted desktop source guidance, selected by the **destination platform only
for presentation**. No listing URL is invented when Butlerly's official
store destinations have not been configured.

## Modules

- `raw_backup_archive.dart` — streaming container, manifest, checksums,
  optional attachment warnings, isolated extraction. Knows nothing about
  Butlerly financial tables.
- `raw_backup_service.dart` — SQLite `VACUUM INTO` snapshot, attachment
  reference collection, encryption, publication, and read-only staging.
- `raw_restore_service.dart` — decrypts, verifies, migrates staged SQLite
  snapshots using native database deployment SQL, then activates Replace with
  a restore journal, previous-data copies, and connection reopen.
- `raw_merge_service.dart` — runs a local-wins SQL merge on disposable staged
  SQLite, then uses the same guarded activation path as Replace. Tombstones and
  unresolved evidence conflicts must be respected. Not byte concatenation.

## Implementation sequence

1. Prove archive codec round-trips a real SQLite file and optional attachments.
2. Prove encrypted backup and read-only restore staging on macOS.
3. Implement Replace activation with rollback, restart/reopen, and interruption
   tests; verify on a disposable populated installation.
4. Wire the new implementation to the existing Backup & Restore UI.
5. Remove superseded engine/serializer and obsolete semantic validator code,
   together with unused DTOs, dependencies, tests, UI routes, and localization.
6. Preserve shared evidence safety, database migration history, existing user
   databases, original attachments, and historical backup files.
7. Keep the draft PR unmerged until actual Mac backup/save/decrypt/restore and
   automated CI acceptance are complete.

## File cleanup rule

Classify each old backup file as **keep**, **rewrite**, **consolidate**, or
**delete**. Delete after all production imports have been replaced and the
replacement passes functional tests. Do not preserve two competing engines
in the completed implementation; do not delete shared components needed by
other features.

## Definition of done

A new encrypted Butlerly backup restores all original financial records and
available attachment bytes to a disposable installation. The restored
application reopens normally. Missing optional evidence is reported, not
repaired or used as a backup/restore gate. No old business-rule validation or
superseded backup implementation remains in the production path.
