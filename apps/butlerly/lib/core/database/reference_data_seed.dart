import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

final class ReferenceSeedRow {
  const ReferenceSeedRow(this.id, this.english, this.chinese);
  final String id;
  final String english;
  final String chinese;
  String get type => id.substring(0, id.lastIndexOf('.'));
  String get code => id.substring(id.lastIndexOf('.') + 1);
  ReferenceData get value =>
      ReferenceData(id: ReferenceDataId(id), code: code, type: type);
  List<ReferenceTranslationSeed> get translations => [
    ReferenceTranslationSeed(value.id, 'en', english),
    ReferenceTranslationSeed(value.id, 'zh-Hans', chinese),
  ];
}

final class ReferenceTranslationSeed {
  const ReferenceTranslationSeed(this.id, this.locale, this.label);
  final ReferenceDataId id;
  final String locale;
  final String label;
}

/// Exact simple-reference identities and labels from MD-0001 sections 5–12.
const md0001ReferenceData = <ReferenceSeedRow>[
  ReferenceSeedRow('transaction.direction.expense', 'Expense', '支出'),
  ReferenceSeedRow('transaction.direction.income', 'Income', '收入'),
  ReferenceSeedRow('transaction.direction.transfer', 'Transfer', '转账'),
  ReferenceSeedRow('payment_source.type.credit_card', 'Credit Card', '信用卡'),
  ReferenceSeedRow('payment_source.type.debit_card', 'Debit Card', '借记卡'),
  ReferenceSeedRow('payment_source.type.bank_account', 'Bank Account', '银行账户'),
  ReferenceSeedRow('payment_source.type.cash', 'Cash', '现金'),
  ReferenceSeedRow(
    'payment_source.type.digital_wallet',
    'Digital Wallet',
    '数字钱包',
  ),
  ReferenceSeedRow('payment_source.type.other', 'Other', '其他'),
  ReferenceSeedRow('card_network.visa', 'Visa', 'Visa'),
  ReferenceSeedRow('card_network.mastercard', 'Mastercard', 'Mastercard'),
  ReferenceSeedRow(
    'card_network.american_express',
    'American Express',
    'American Express',
  ),
  ReferenceSeedRow('card_network.discover', 'Discover', 'Discover'),
  ReferenceSeedRow('card_network.unionpay', 'UnionPay', '银联'),
  ReferenceSeedRow('card_network.jcb', 'JCB', 'JCB'),
  ReferenceSeedRow('card_network.other', 'Other', '其他'),
  ReferenceSeedRow('card_network.unknown', 'Unknown', '未知'),
  ReferenceSeedRow('evidence.type.receipt', 'Receipt', '收据'),
  ReferenceSeedRow('evidence.type.statement', 'Statement', '账单'),
  ReferenceSeedRow(
    'evidence.type.card_notification',
    'Card Notification',
    '银行卡通知',
  ),
  ReferenceSeedRow('evidence.type.import', 'Imported Record', '导入记录'),
  ReferenceSeedRow('evidence.type.manual', 'Manual Entry', '手动录入'),
  ReferenceSeedRow('evidence.type.other', 'Other Evidence', '其他凭证'),
  ReferenceSeedRow('review.status.none', 'No Review Needed', '无需审核'),
  ReferenceSeedRow('review.status.needs_review', 'Needs Review', '需要审核'),
  ReferenceSeedRow('review.status.in_review', 'In Review', '审核中'),
  ReferenceSeedRow('review.status.resolved', 'Resolved', '已解决'),
  ReferenceSeedRow('reconciliation.status.unmatched', 'Unmatched', '未匹配'),
  ReferenceSeedRow('reconciliation.status.candidate', 'Candidate', '候选匹配'),
  ReferenceSeedRow('reconciliation.status.confirmed', 'Confirmed', '已确认'),
  ReferenceSeedRow('reconciliation.status.rejected', 'Rejected', '已拒绝'),
  ReferenceSeedRow('reconciliation.status.superseded', 'Superseded', '已取代'),
  ReferenceSeedRow('analysis.finding.status.active', 'Active', '有效'),
  ReferenceSeedRow(
    'analysis.finding.status.acknowledged',
    'Acknowledged',
    '已确认',
  ),
  ReferenceSeedRow('analysis.finding.status.dismissed', 'Dismissed', '已忽略'),
  ReferenceSeedRow('analysis.finding.status.superseded', 'Superseded', '已取代'),
  ReferenceSeedRow(
    'analysis.finding.spending_increase',
    'Spending Increase',
    '支出增加',
  ),
  ReferenceSeedRow(
    'analysis.finding.spending_decrease',
    'Spending Decrease',
    '支出减少',
  ),
  ReferenceSeedRow(
    'analysis.finding.large_transaction',
    'Large Transaction',
    '大额交易',
  ),
  ReferenceSeedRow(
    'analysis.finding.recurring_payment',
    'Recurring Payment',
    '定期付款',
  ),
  ReferenceSeedRow(
    'analysis.finding.unusual_spending',
    'Unusual Spending',
    '异常支出',
  ),
  ReferenceSeedRow(
    'analysis.finding.category_concentration',
    'Category Concentration',
    '类别集中',
  ),
  ReferenceSeedRow(
    'analysis.finding.merchant_concentration',
    'Merchant Concentration',
    '商户集中',
  ),
  ReferenceSeedRow('analysis.finding.missing_data', 'Missing Data', '数据缺失'),
  ReferenceSeedRow('analysis.finding.data_quality', 'Data Quality', '数据质量'),
];

/// Legacy IDs found in pre-MD-0001 local databases.
const md0001ReferenceAliases = <String, String>{
  'transaction_direction.expense': 'transaction.direction.expense',
  'transaction_direction.income': 'transaction.direction.income',
  'transaction_direction.transfer': 'transaction.direction.transfer',
  'payment_source_type.card': 'payment_source.type.credit_card',
  'payment_source_type.debit_card': 'payment_source.type.debit_card',
  'payment_source_type.account': 'payment_source.type.bank_account',
  'payment_source_type.cash': 'payment_source.type.cash',
  'payment_source_type.wallet': 'payment_source.type.digital_wallet',
  'payment_source_type.other': 'payment_source.type.other',
  'card_network.amex': 'card_network.american_express',
  'evidence_type.imported_record': 'evidence.type.import',
};
