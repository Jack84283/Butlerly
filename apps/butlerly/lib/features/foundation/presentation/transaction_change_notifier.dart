import 'package:flutter/foundation.dart';

/// Presentation invalidation signal for transaction-backed screens.
///
/// Persistent shell destinations remain mounted while modal transaction flows
/// are open, so navigation results alone cannot refresh every visible cache.
final transactionChanges = ValueNotifier<int>(0);

void notifyTransactionChanged() {
  transactionChanges.value++;
}

/// Presentation invalidation signal for payment-settlement tools.
///
/// Settlements live in a secondary Tools route while the primary shell keeps
/// the Tools destination mounted. Consumers can refresh action summaries
/// without coupling navigation results to persistence changes.
final paymentSettlementChanges = ValueNotifier<int>(0);

void notifyPaymentSettlementChanged() {
  paymentSettlementChanges.value++;
}

/// Physical Restore changes more than transactions, including financial
/// profiles and master-data catalogs that can remain mounted in a desktop
/// shell. Consumers with independent screen caches listen to this signal.
final workspaceRestoreChanges = ValueNotifier<int>(0);

void notifyWorkspaceRestored() {
  workspaceRestoreChanges.value++;
  notifyTransactionChanged();
}
