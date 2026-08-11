import 'package:flutter/foundation.dart';

/// Presentation invalidation signal for transaction-backed screens.
///
/// Persistent shell destinations remain mounted while modal transaction flows
/// are open, so navigation results alone cannot refresh every visible cache.
final transactionChanges = ValueNotifier<int>(0);

void notifyTransactionChanged() {
  transactionChanges.value++;
}
