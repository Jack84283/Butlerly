/// Butlerly CSV V1: two explicit, versioned, header-only templates.
///
/// These are CSV transaction facts; receipt rows do not imply an attached
/// receipt image or an OCR result. Source rows are retained as import
/// provenance, and potential duplicates require user confirmation.
enum ButlerlyCsvKind { receipts, transactions }

final class ButlerlyCsvTemplate {
  const ButlerlyCsvTemplate._();

  static const receiptHeaders = <String>[
    'receipt_id',
    'date',
    'merchant',
    'total',
    'currency',
    'tax',
    'tip',
    'notes',
  ];

  static const transactionHeaders = <String>[
    'date',
    'description',
    'amount',
    'currency',
    'direction',
    'merchant',
    'transaction_id',
    'account_reference',
    'notes',
  ];

  static List<String> headers(ButlerlyCsvKind kind) => switch (kind) {
    ButlerlyCsvKind.receipts => receiptHeaders,
    ButlerlyCsvKind.transactions => transactionHeaders,
  };

  static String filename(ButlerlyCsvKind kind) => switch (kind) {
    ButlerlyCsvKind.receipts => 'butlerly_receipts_v1.csv',
    ButlerlyCsvKind.transactions => 'butlerly_transactions_v1.csv',
  };

  /// UTF-8 without a BOM and with a CRLF row ending for spreadsheet tools.
  static String content(ButlerlyCsvKind kind) =>
      '${headers(kind).join(',')}\r\n';
}
