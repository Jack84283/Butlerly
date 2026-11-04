import 'package:flutter/foundation.dart';

/// Presentation invalidation signal for transaction-backed screens.
///
/// Persistent shell destinations remain mounted while modal transaction flows
/// are open, so navigation results alone cannot refresh every visible cache.
final transactionChanges = ValueNotifier<int>(0);

void notifyTransactionChanged() {
  transactionChanges.value++;
}

/// Physical Restore changes more than transactions, including financial
/// profiles and master-data catalogs that can remain mounted in a desktop
/// shell. Consumers with independent screen caches listen to this signal.
final workspaceRestoreChanges = ValueNotifier<int>(0);

void notifyWorkspaceRestored() {
  workspaceRestoreChanges.value++;
  notifyTransactionChanged();
}
