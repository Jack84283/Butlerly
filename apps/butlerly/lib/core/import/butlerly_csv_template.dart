/// Butlerly CSV V1: receipt and transaction templates in supported languages.
///
/// The canonical column identities remain stable even if the downloaded
/// headers are translated. The importer accepts the original technical V1
/// headers for backward compatibility and any supported localized version.
/// A template never contains a sample transaction that could be imported.
enum ButlerlyCsvKind { receipts, transactions }

final class ButlerlyCsvTemplate {
  const ButlerlyCsvTemplate._();

  static const receiptHeaders = <String>[
    'receipt_id',
    'date',
    'merchant',
    'total',
    'currency',
    'notes',
  ];

  static const legacySimpleReceiptHeaders = <String>[
    'date',
    'merchant',
    'total',
    'currency',
    'notes',
  ];

  /// Receipt columns emitted by the pre-V1 importer. Tax and tip are not
  /// separate transaction fields in the current model; the importer accepts
  /// this shape for compatibility and preserves those values in notes.
  static const legacyTaxTipReceiptHeaders = <String>[
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
        'Receipt ID',
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
      ButlerlyCsvKind.receipts: ['收据编号', '日期', '商家', '实付总额', '币种', '备注'],
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
        'ID de recibo',
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

  static const _legacySimpleReceiptLabels = <String, List<String>>{
    'en': ['Date', 'Merchant', 'Total Paid', 'Currency', 'Notes'],
    'zh': ['日期', '商家', '实付总额', '币种', '备注'],
    'es': ['Fecha', 'Comercio', 'Total pagado', 'Moneda', 'Notas'],
  };

  static const _legacyTaxTipReceiptLabels = <String, List<String>>{
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
    'zh': ['收据编号', '日期', '商家', '实付总额', '币种', '税费', '小费', '备注'],
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

  static bool matchesHeaders(ButlerlyCsvKind kind, List<String> actual) =>
      recognizedHeaders(kind, actual) != null;

  static List<String>? recognizedHeaders(
    ButlerlyCsvKind kind,
    List<String> actual,
  ) {
    bool same(List<String> expected) {
      if (actual.length != expected.length) return false;
      for (var i = 0; i < actual.length; i++) {
        if (actual[i].replaceFirst('﻿', '').trim().toLowerCase() !=
            expected[i].toLowerCase()) {
          return false;
        }
      }
      return true;
    }

    if (same(headers(kind))) return headers(kind);
    if (kind == ButlerlyCsvKind.receipts &&
        (same(legacyTaxTipReceiptHeaders) ||
            languages.any((code) => same(_legacyTaxTipReceiptLabels[code]!)))) {
      return legacyTaxTipReceiptHeaders;
    }
    if (kind == ButlerlyCsvKind.receipts &&
        (same(legacySimpleReceiptHeaders) ||
            languages.any((code) => same(_legacySimpleReceiptLabels[code]!)))) {
      return legacySimpleReceiptHeaders;
    }
    if (languages.any(
      (code) => same(displayHeaders(kind, languageCode: code)),
    )) {
      return headers(kind);
    }
    return null;
  }

  static String filename(ButlerlyCsvKind kind, {String languageCode = 'en'}) {
    final suffix = languageCode == 'en' ? '' : '_${language(languageCode)}';
    return 'butlerly_${kind.name}_v1$suffix.csv';
  }

  static String content(ButlerlyCsvKind kind, {String languageCode = 'en'}) {
    final normalizedLanguage = languageCode == 'en'
        ? 'en'
        : language(languageCode);
    final headers = normalizedLanguage == 'en'
        ? ButlerlyCsvTemplate.headers(kind)
        : displayHeaders(kind, languageCode: normalizedLanguage);
    return '\ufeff${headers.join(',')}\r\n';
  }

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

  static List<String> exampleValues(
    ButlerlyCsvKind kind, {
    String languageCode = 'en',
  }) {
    final lang = language(languageCode);
    if (kind == ButlerlyCsvKind.receipts) {
      return [
        'receipt-100',
        '2026-10-15',
        switch (lang) {
          'zh' => '示例商店',
          'es' => 'Tienda ejemplo',
          _ => 'Example Store',
        },
        '22.50',
        '',
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
