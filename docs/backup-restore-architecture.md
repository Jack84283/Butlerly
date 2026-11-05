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

## Backup & Restore status notifications

- The shared `ButlerlyToast` component uses the app's semantic success
  (green) and error (red) colors in both light and dark themes.
- Successful Backup, Merge, Replace, and Privacy & Data operations show a green
  toast with a five-second lifetime.
- Failed operations show a red toast that does not time out during normal use.
  **Details** opens the localized reason and corrective action without closing
  the notification. **Close** is an explicit user action.
- Restore/Backup failure details must never expose a backup password, private
  SQLite records, local file paths, or raw stack traces.
- Canceled platform sharing is informational, not a successful saved backup.
- This PR wires the new shared toast component into the Privacy & Data screen.
  Other screens with legacy inline SnackBars should adopt the shared helper
  separately to enforce the same app-wide policy.

## Review hardening — missing evidence, Merge identity, and UI refresh

- **Verified export warnings:** raw archive packaging records missing referenced
  evidence. The application gateway returns the count to desktop and mobile
  callers without a second expensive decrypt/inspection pass. A published
  backup with missing attachments triggers a localized, persistent warning
  dialog; it must not be represented as a complete evidence backup.
- **Foreign-key identity preflight:** before staging SQL writes, Merge compares
  referenced parent rows in the backup and live database for each child row
  being imported. If matching parent keys contain different values, it
  conservatively rejects the entire Merge rather than reassign the imported
  child to a potentially different category, merchant, or payment source.
  This can reject a valid merge when only timestamps differ; resolving these
  conflicts safely requires an explicit reconciliation policy, not guessing.
- **Staging write detection:** a Merge records the live connection's
  `total_changes()`, SQLite `PRAGMA data_version`, and schema version before
  the local snapshot. After staging and WAL checkpoint, it rechecks all three.
  A change aborts without moving original database or evidence files.
  Normal application use-case writes are serialized by
  `AnalysisConsistencyGate` during Restore, but the revision check is an
  extra fail-closed safeguard for direct or external database writes.
- **Final concurrency gate:** revision checks are supplemented by an
  application repository-access fence and a POSIX exclusive SQLite file lock
  after closing the live connection. SQLite writers in another process must
  fail to obtain a conflicting lock during the physical Merge rename. The
  final file fingerprint is read through the *locked descriptor*, never by
  reopening the original path (which can release POSIX locks). On Windows,
  physical Merge fails closed pending a Windows-compatible activation design.
  This protects cooperating SQLite connections; independent tools using
  nonstandard VFS/locking or directly modifying files remain unsupported.
- **Post-Restore refresh:** the committed Restore emits
  `workspaceRestoreChanges`, also invalidating transaction and budget data.
  Mounted profile, master data, payment sources, budgets, rules and payment
  settlement pages refresh their cached snapshots; stale editors are reset
  rather than allowed to overwrite restored records.

## P1 data-safety hardening (follow-up review)

- **Source foreign keys:** before merging anything, validate the archived
  SQLite database's own foreign-key constraints. An orphaned source child
  cannot borrow an unrelated destination parent merely because the IDs match.
  Reject the entire merge with no live mutation and keep the archive unchanged.
- **Final activation fence:** normal repository SQLite connection access is
  suspended before the last live revision check and remains suspended until
  activation succeeds or rollback completes. The workspace consistency gate
  continues to serialize regular financial mutations. A Merge additionally
  fingerprints the checkpointed live SQLite file before close and again after
  close to detect commits from a raw handle retained before the fence. If the
  file changed, abort activation and recover the original database, retaining
  the committed late write.
- **Uncertain rollback:** a failed journal recovery keeps normal repository
  access fenced and raises RestoreRecoveryRequiredException. The production
  gateway persists a recovery-only application state and leaves the raw journal
  and private original files intact; a subsequent successful startup journal
  rollback clears only the corresponding raw-restore recovery state.
- **Unresolved journal at startup:** if the raw recovery journal is corrupt or
  otherwise cannot be replayed, Butlerly does not open SQLite or expose normal
  navigation. It shows a localized recovery-only startup screen with a retry
  action and instructions to preserve the original journal and prior files.
- **Recovery retry safety:** the app's restore fence remains active while the
  persistence connection is closed *before* raw journaled files are moved.
  Connection close failure stops recovery without deleting the marker.
- **Independent SQLite writers:** the POSIX nonblocking exclusive database
  lock is held through the swap, while normal writers use the application
  consistency gate. A separate-process SQLite regression test verifies the
  lock on CI Linux. This is not an authorization boundary against arbitrary
  raw filesystem writes, nor a substitute for disposable macOS/iOS acceptance.
  Windows Merge remains intentionally unsupported by this activation code.

## Performance optimizations (PR #396)

The raw archive is streamed, and financial/business rules never run during
backup or restore. Performance improvements must retain authenticated encryption,
byte-level SHA-256 verification, path containment, and rollback guarantees.

- **Backup packaging:** source SQLite and attachments are each fingerprinted
  for the manifest, and the *written archive* is independently verified.
  The former extra full-source hash pass after copying has been eliminated;
  same-size content changes still fail archive verification.
- **Restore preview:** the encrypted archive is authenticated, every archived
  attachment is hashed, but **only SQLite is written** to temporary storage for
  the schema/version check. No temporary copies of receipt files are created
  merely to display a confirmation prompt.
- **Restore extraction:** the validated manifest guides direct extraction;
  every resulting file is independently hashed against its manifest SHA-256.
  A redundant preliminary full-archive inspection pass has been removed.
- **Still intentionally retained:** SQLite `VACUUM INTO` for an atomic,
  consistent snapshot; Argon2id + AES-GCM; safe destination publication;
  staging/rollback; staged SQLite physical integrity and schema migration.

Performance acceptance should compare elapsed Backup, Restore-preview, Replace,
and Merge times on the **same disposable dataset**, including a collection with
many receipt files, and should verify exact post-restore SQLite and attachment
bytes. No percentage speed-up should be asserted without such measurements.

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

## Legacy-file dependency audit (PR #396)

A legacy filename does **not** imply an unused file. The following files
remain referenced by installed-app startup, publication rollback, or recovery
logic, so their deletion is **blocked until recovery is migrated and proven**:

| File | Current consumer / reason to retain | Action |
| --- | --- | --- |
| `local_backup_manager.dart` | Dependency injection, app startup recovery, portable publication recovery, and controlled restore recovery | Rewrite/split after recovery parity |
| `local_backup_engine.dart` | Still called by `local_backup_manager.dart` for legacy backup inspection, safety-copy restore, and controlled recovery | Retain until no recovery dependency |
| `local_backup_snapshot_writer.dart` | Still writes old-format pre-restore safety copies from the manager | Retain until safety-copy workflow migrated |
| `backup_container_format.dart` | Old persisted-backup protocol used by manager/engine/writer | Retain until legacy recovery resolved |
| `duplicate_group_backup_policy.dart` | Imported by engine and old snapshot writer | Retain with dependent files |
| `local_restore_recovery.dart` | Rollback recovery for interrupted legacy restore | Retain until proven unnecessary |
| `staged_evidence_restore_reconciliation.dart` | Used by restore recovery and legacy engine to preserve evidence | Retain |
| `backup_destination_writer.dart`, `backup_encryption.dart`, `evidence_path_safety.dart` | Shared by new raw backup and existing publication/recovery paths | Keep |
| `backup_publication_recovery_state.dart`, `restore_recovery_state.dart` | Active startup/UI recovery state | Keep |

The new raw backup/restore services and their regression tests are active,
not unused. Database schema/migration SQL and historical backup files are
permanently protected from cleanup.

**Safe retirement gate:** complete raw Replace/Merge and interrupted-operation
tests on disposable data; preserve the ability to recover existing legacy
safety copies; update all production imports and startup/UI recovery paths;
then remove the superseded engine, snapshot writer, schema constants and tests
*in one focused, verified change*. Do not drop tests merely to make CI green.

## Definition of done

A new encrypted Butlerly backup restores all original financial records and
available attachment bytes to a disposable installation. The restored
application reopens normally. Missing optional evidence is reported, not
repaired or used as a backup/restore gate. No old business-rule validation or
superseded backup implementation remains in the production path.
