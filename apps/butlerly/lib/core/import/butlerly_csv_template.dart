/// Butlerly CSV V1: receipt and transaction templates in supported languages.
///
/// The canonical column identities remain stable even if the downloaded
/// headers are translated. The importer accepts the original technical V1
/// headers for backward compatibility and any supported localized version.
/// A template never contains a sample transaction that could be imported.
enum ButlerlyCsvKind { receipts, transactions }

final class ButlerlyCsvTemplate {
  const ButlerlyCsvTemplate._();

  // The recommended receipt template contains only financial facts. There
  // is no required merchant receipt number or receipt-level accounting.
  static const receiptHeaders = <String>[
    'date',
    'merchant',
    'total',
    'currency',
    'notes',
  ];

  // Previously downloaded V1 templates remain valid and importable.
  static const legacyReceiptHeaders = <String>[
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

  static const languages = <String>['en', 'zh', 'es'];

  static const _labels = <String, Map<ButlerlyCsvKind, List<String>>>{
    'en': {
      ButlerlyCsvKind.receipts: [
        'Date',
        'Merchant',
        'Total Paid',
        'Currency',
        'Notes',
      ],
      ButlerlyCsvKind.transactions: [
        'Date',
        'Description',
        'Amount',
        'Currency',
        'Type',
        'Merchant',
        'Transaction ID',
        'Account Reference',
        'Notes',
      ],
    },
    'zh': {
      ButlerlyCsvKind.receipts: ['日期', '商家', '实付总额', '币种', '备注'],
      ButlerlyCsvKind.transactions: [
        '日期',
        '描述',
        '金额',
        '币种',
        '类型',
        '商家',
        '交易编号',
        '账户参考',
        '备注',
      ],
    },
    'es': {
      ButlerlyCsvKind.receipts: [
        'Fecha',
        'Comercio',
        'Total pagado',
        'Moneda',
        'Notas',
      ],
      ButlerlyCsvKind.transactions: [
        'Fecha',
        'Descripción',
        'Importe',
        'Moneda',
        'Tipo',
        'Comercio',
        'ID de transacción',
        'Referencia de cuenta',
        'Notas',
      ],
    },
  };

  static String language(String? languageCode) {
    final short = languageCode?.split(RegExp('[-_]')).first.toLowerCase();
    return languages.contains(short) ? short! : 'en';
  }

  // Original translated V1 receipt headers shipped before the simplified
  // template. Keep recognizing these files without requiring any user edits.
  static const _legacyReceiptLabels = <String, List<String>>{
    'en': [
      'Receipt ID',
      'Date',
      'Merchant',
      'Total Paid',
      'Currency',
      'Tax',
      'Tip',
      'Notes',
    ],
    'zh': ['收据编号', '日期', '商家', '实付总额', '币种', '税额', '小费', '备注'],
    'es': [
      'ID de recibo',
      'Fecha',
      'Comercio',
      'Total pagado',
      'Moneda',
      'Impuesto',
      'Propina',
      'Notas',
    ],
  };

  static List<String> headers(ButlerlyCsvKind kind) => switch (kind) {
    ButlerlyCsvKind.receipts => receiptHeaders,
    ButlerlyCsvKind.transactions => transactionHeaders,
  };

  static List<String> displayHeaders(
    ButlerlyCsvKind kind, {
    String languageCode = 'en',
  }) => _labels[language(languageCode)]![kind]!;

  /// Column positions are fixed; translated names don't change the mapping.
  /// This also recognizes files created by the original English-only V1.
  static bool matchesHeaders(ButlerlyCsvKind kind, List<String> actual) =>
      recognizedHeaders(kind, actual) != null;

  /// Returns canonical positional fields for either downloaded V1 layout.
  /// Null means an unrecognized template, which must never be guessed.
  static List<String>? recognizedHeaders(
    ButlerlyCsvKind kind,
    List<String> actual,
  ) {
    bool same(List<String> expected) {
      if (actual.length != expected.length) return false;
      for (var i = 0; i < expected.length; i++) {
        if (actual[i].replaceFirst('\ufeff', '').trim().toLowerCase() !=
            expected[i].toLowerCase()) {
          return false;
        }
      }
      return true;
    }

    if (same(headers(kind)) ||
        languages.any(
          (code) => same(displayHeaders(kind, languageCode: code)),
        )) {
      return headers(kind);
    }
    if (kind == ButlerlyCsvKind.receipts &&
        (same(legacyReceiptHeaders) ||
            languages.any((code) => same(_legacyReceiptLabels[code]!)))) {
      return legacyReceiptHeaders;
    }
    return null;
  }

  static String filename(ButlerlyCsvKind kind, {String languageCode = 'en'}) =>
      'butlerly_${kind.name}_v1_${language(languageCode)}.csv';

  /// UTF-8 BOM helps Excel recognize Chinese/Spanish headers without mojibake.
  /// The CSV is intentionally header-only; examples are shown in the app.
  static String content(ButlerlyCsvKind kind, {String languageCode = 'en'}) =>
      '\ufeff${displayHeaders(kind, languageCode: languageCode).join(',')}\r\n';

  /// Canonical English data values continue to work in every locale.
  static const _localizedDirections = <String, String>{
    'expense': 'expense',
    'income': 'income',
    'transfer': 'transfer',
    'refund': 'refund',
    'adjustment': 'adjustment',
    '支出': 'expense',
    '收入': 'income',
    '转账': 'transfer',
    '退款': 'refund',
    '调整': 'adjustment',
    'gasto': 'expense',
    'ingreso': 'income',
    'transferencia': 'transfer',
    'reembolso': 'refund',
    'ajuste': 'adjustment',
  };

  static String? canonicalDirection(String value) =>
      _localizedDirections[value.trim().toLowerCase()];

  static String allowedDirections(String languageCode) =>
      switch (language(languageCode)) {
        'zh' => '支出、收入、转账、退款、调整',
        'es' => 'gasto, ingreso, transferencia, reembolso, ajuste',
        _ => 'expense, income, transfer, refund, adjustment',
      };

  /// Safe illustrative values; do not include in the downloadable CSV.
  static List<String> exampleValues(
    ButlerlyCsvKind kind, {
    String languageCode = 'en',
  }) {
    final lang = language(languageCode);
    if (kind == ButlerlyCsvKind.receipts) {
      return [
        '2026-10-15',
        switch (lang) {
          'zh' => '示例商店',
          'es' => 'Tienda ejemplo',
          _ => 'Example Store',
        },
        '22.50',
        '', // Currency is optional; defaults to the user's configured currency.
        '',
      ];
    }
    return [
      '2026-10-15',
      switch (lang) {
        'zh' => '示例购物',
        'es' => 'Compra de ejemplo',
        _ => 'Example purchase',
      },
      '22.50',
      'USD',
      switch (lang) {
        'zh' => '支出',
        'es' => 'gasto',
        _ => 'expense',
      },
      switch (lang) {
        'zh' => '示例商店',
        'es' => 'Tienda ejemplo',
        _ => 'Example Store',
      },
      '',
      '',
      '',
    ];
  }
}
