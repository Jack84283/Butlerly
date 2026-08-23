import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

final class ReferenceSeedRow {
  const ReferenceSeedRow(this.type, this.code, this.english, this.chinese);
  final String type;
  final String code;
  final String english;
  final String chinese;

  ReferenceData get value =>
      ReferenceData(id: ReferenceDataId('$type.$code'), code: code, type: type);

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

const md0001ReferenceData = <ReferenceSeedRow>[
  ReferenceSeedRow('transaction_direction', 'expense', 'Expense', '支出'),
  ReferenceSeedRow('transaction_direction', 'income', 'Income', '收入'),
  ReferenceSeedRow('transaction_direction', 'transfer', 'Transfer', '转账'),
  ReferenceSeedRow('transaction_direction', 'refund', 'Refund', '退款'),
  ReferenceSeedRow('transaction_direction', 'adjustment', 'Adjustment', '调整'),
  ReferenceSeedRow('transaction_type', 'manual', 'Manual', '手动'),
  ReferenceSeedRow('transaction_type', 'import', 'Import', '导入'),
  ReferenceSeedRow(
    'transaction_type',
    'evidence_capture',
    'Receipt capture',
    '收据采集',
  ),
  ReferenceSeedRow('transaction_type', 'integration', 'Integration', '集成'),
  ReferenceSeedRow('payment_source_type', 'account', 'Account', '账户'),
  ReferenceSeedRow('payment_source_type', 'card', 'Credit card', '信用卡'),
  ReferenceSeedRow('payment_source_type', 'debit_card', 'Debit card', '借记卡'),
  ReferenceSeedRow('payment_source_type', 'cash', 'Cash', '现金'),
  ReferenceSeedRow('payment_source_type', 'wallet', 'Wallet', '钱包'),
  ReferenceSeedRow('payment_source_type', 'other', 'Other', '其他'),
  ReferenceSeedRow('card_network', 'visa', 'Visa', 'Visa'),
  ReferenceSeedRow('card_network', 'mastercard', 'Mastercard', 'Mastercard'),
  ReferenceSeedRow('card_network', 'amex', 'American Express', '美国运通'),
  ReferenceSeedRow('card_network', 'unionpay', 'UnionPay', '银联'),
  ReferenceSeedRow('card_network', 'other', 'Other', '其他'),
  ReferenceSeedRow('evidence_type', 'receipt_image', 'Receipt image', '收据图片'),
  ReferenceSeedRow('evidence_type', 'document', 'Document', '文档'),
  ReferenceSeedRow(
    'evidence_type',
    'imported_record',
    'Imported record',
    '导入记录',
  ),
  ReferenceSeedRow('evidence_type', 'other', 'Other', '其他'),
  ReferenceSeedRow('review_status', 'clear', 'Clear', '无须审核'),
  ReferenceSeedRow('review_status', 'needs_review', 'Needs review', '需要审核'),
  ReferenceSeedRow('review_status', 'active', 'Active', '进行中'),
  ReferenceSeedRow('review_status', 'resolved', 'Resolved', '已解决'),
  ReferenceSeedRow('review_status', 'dismissed', 'Dismissed', '已忽略'),
  ReferenceSeedRow('reconciliation_status', 'proposed', 'Proposed', '待确认'),
  ReferenceSeedRow('reconciliation_status', 'confirmed', 'Confirmed', '已确认'),
  ReferenceSeedRow('reconciliation_status', 'rejected', 'Rejected', '已拒绝'),
  ReferenceSeedRow('reconciliation_status', 'undone', 'Undone', '已撤销'),
  ReferenceSeedRow('analysis_finding_lifecycle', 'proposed', 'Proposed', '待处理'),
  ReferenceSeedRow('analysis_finding_lifecycle', 'accepted', 'Accepted', '已接受'),
  ReferenceSeedRow('analysis_finding_lifecycle', 'rejected', 'Rejected', '已拒绝'),
  ReferenceSeedRow('analysis_finding_lifecycle', 'expired', 'Expired', '已过期'),
  ReferenceSeedRow('analysis_finding_type', 'incomplete', 'Incomplete', '不完整'),
  ReferenceSeedRow('analysis_finding_type', 'uncertain', 'Uncertain', '不确定'),
  ReferenceSeedRow('analysis_finding_type', 'conflict', 'Conflict', '冲突'),
  ReferenceSeedRow(
    'analysis_finding_type',
    'duplicate_candidate',
    'Duplicate candidate',
    '重复候选',
  ),
  ReferenceSeedRow('analysis_finding_type', 'other', 'Other', '其他'),
];
