/// Local-only issuer suggestions. Alias matching never changes existing records.
/// Artwork is available only for verified assets bundled under assets/icons/issuers/.
class IssuerInstitution {
  const IssuerInstitution({
    required this.id,
    required this.name,
    required this.aliases,
    this.asset,
  });

  final String id;
  final String name;
  final List<String> aliases;
  final String? asset;

  String? get assetPath =>
      asset == null ? null : 'assets/icons/issuers/$asset.svg';
}

/// 29 US and 30 Chinese institutions, in stable display order.
const issuerInstitutions = <IssuerInstitution>[
  IssuerInstitution(
    id: 'chase',
    name: 'Chase',
    aliases: ['Chase Bank', 'JPMorgan Chase', 'JP Morgan'],
    asset: 'chase',
  ),
  IssuerInstitution(
    id: 'bankofamerica',
    name: 'Bank of America',
    aliases: ['BoA', 'BofA', 'B of A'],
    asset: 'bankofamerica',
  ),
  IssuerInstitution(
    id: 'citibank',
    name: 'Citibank',
    aliases: ['Citi', 'CitiBank', 'Citi Bank'],
    asset: 'citibank',
  ),
  IssuerInstitution(
    id: 'capitalone',
    name: 'Capital One',
    aliases: ['CapitalOne', 'Capital One Bank'],
  ),
  IssuerInstitution(
    id: 'wellsfargo',
    name: 'Wells Fargo',
    aliases: ['Wells Fargo Bank'],
    asset: 'wellsfargo',
  ),
  IssuerInstitution(
    id: 'usbank',
    name: 'U.S. Bank',
    aliases: ['US Bank', 'USBank', 'U S Bank'],
  ),
  IssuerInstitution(
    id: 'pnc',
    name: 'PNC Bank',
    aliases: ['PNC'],
  ),
  IssuerInstitution(
    id: 'truist',
    name: 'Truist Bank',
    aliases: ['Truist'],
  ),
  IssuerInstitution(
    id: 'tdbank',
    name: 'TD Bank',
    aliases: ['TD'],
  ),
  IssuerInstitution(
    id: 'bmo',
    name: 'BMO Bank',
    aliases: ['BMO', 'BMO Harris'],
    asset: 'bmo',
  ),
  IssuerInstitution(
    id: 'citizens',
    name: 'Citizens Bank',
    aliases: ['Citizens'],
  ),
  IssuerInstitution(
    id: 'fifththird',
    name: 'Fifth Third Bank',
    aliases: ['Fifth Third', '5/3 Bank'],
  ),
  IssuerInstitution(
    id: 'huntington',
    name: 'Huntington Bank',
    aliases: ['Huntington', 'Huntington National Bank'],
  ),
  IssuerInstitution(
    id: 'keybank',
    name: 'KeyBank',
    aliases: ['Key Bank'],
  ),
  IssuerInstitution(
    id: 'regions',
    name: 'Regions Bank',
    aliases: ['Regions'],
  ),
  IssuerInstitution(
    id: 'mtbank',
    name: 'M&T Bank',
    aliases: ['M&T'],
  ),
  IssuerInstitution(
    id: 'santander',
    name: 'Santander Bank',
    aliases: ['Santander'],
  ),
  IssuerInstitution(
    id: 'firstcitizens',
    name: 'First Citizens Bank',
    aliases: ['First Citizens'],
  ),
  IssuerInstitution(
    id: 'firsthorizon',
    name: 'First Horizon Bank',
    aliases: ['First Horizon'],
  ),
  IssuerInstitution(
    id: 'ally',
    name: 'Ally Bank',
    aliases: ['Ally'],
  ),
  IssuerInstitution(
    id: 'sofi',
    name: 'SoFi Bank',
    aliases: ['SoFi'],
  ),
  IssuerInstitution(
    id: 'americanexpress',
    name: 'American Express',
    aliases: ['Amex', 'American Express National Bank'],
    asset: 'americanexpress',
  ),
  IssuerInstitution(
    id: 'discover',
    name: 'Discover',
    aliases: ['Discover Bank'],
    asset: 'discover',
  ),
  IssuerInstitution(
    id: 'synchrony',
    name: 'Synchrony Bank',
    aliases: ['Synchrony'],
  ),
  IssuerInstitution(
    id: 'barclays',
    name: 'Barclays',
    aliases: ['Barclays Bank', 'Barclaycard'],
    asset: 'barclays',
  ),
  IssuerInstitution(
    id: 'goldmansachs',
    name: 'Goldman Sachs Bank',
    aliases: ['Goldman Sachs', 'Marcus'],
    asset: 'goldmansachs',
  ),
  IssuerInstitution(
    id: 'schwab',
    name: 'Charles Schwab Bank',
    aliases: ['Schwab Bank', 'Schwab'],
  ),
  IssuerInstitution(
    id: 'usaa',
    name: 'USAA',
    aliases: ['USAA Federal Savings Bank'],
  ),
  IssuerInstitution(
    id: 'navyfederal',
    name: 'Navy Federal Credit Union',
    aliases: ['Navy Federal', 'NFCU'],
  ),
  IssuerInstitution(
    id: 'icbc',
    name: '中国工商银行',
    aliases: [
      '工商银行',
      '工商行',
      '工行',
      'ICBC',
      'Industrial and Commercial Bank of China',
    ],
    asset: 'icbc',
  ),
  IssuerInstitution(
    id: 'abchina',
    name: '中国农业银行',
    aliases: ['农业银行', '农业行', '农行', 'ABC', 'Agricultural Bank of China'],
    asset: 'abchina',
  ),
  IssuerInstitution(
    id: 'boc',
    name: '中国银行',
    aliases: ['中行', 'BOC', 'Bank of China'],
    asset: 'boc',
  ),
  IssuerInstitution(
    id: 'ccb',
    name: '中国建设银行',
    aliases: ['建设银行', '建行', 'CCB', 'China Construction Bank'],
    asset: 'ccb',
  ),
  IssuerInstitution(
    id: 'bankcomm',
    name: '交通银行',
    aliases: ['交行', 'BOCOM', 'Bank of Communications'],
    asset: 'bankcomm',
  ),
  IssuerInstitution(
    id: 'psbc',
    name: '中国邮政储蓄银行',
    aliases: ['邮储银行', '邮储', '邮政储蓄银行', 'PSBC', 'Postal Savings Bank of China'],
    asset: 'psbc',
  ),
  IssuerInstitution(
    id: 'cmbchina',
    name: '招商银行',
    aliases: ['招行', 'CMB', 'China Merchants Bank'],
    asset: 'cmbchina',
  ),
  IssuerInstitution(
    id: 'citicbank',
    name: '中信银行',
    aliases: ['中信', 'CITIC Bank'],
    asset: 'citicbank',
  ),
  IssuerInstitution(
    id: 'cebbank',
    name: '中国光大银行',
    aliases: ['光大银行', '光大', 'CEB', 'China Everbright Bank'],
    asset: 'cebbank',
  ),
  IssuerInstitution(
    id: 'hxb',
    name: '华夏银行',
    aliases: ['华夏', 'Hua Xia Bank'],
    asset: 'hxb',
  ),
  IssuerInstitution(
    id: 'cmbc',
    name: '中国民生银行',
    aliases: ['民生银行', '民生', 'CMBC', 'China Minsheng Bank'],
    asset: 'cmbc',
  ),
  IssuerInstitution(
    id: 'spdb',
    name: '上海浦东发展银行',
    aliases: ['浦发银行', '浦发', 'SPDB'],
    asset: 'spdb',
  ),
  IssuerInstitution(
    id: 'cgbchina',
    name: '广发银行',
    aliases: ['广发', '广东发展银行', 'CGB'],
    asset: 'cgbchina',
  ),
  IssuerInstitution(
    id: 'pingan',
    name: '平安银行',
    aliases: ['平安', 'Ping An Bank'],
    asset: 'pingan',
  ),
  IssuerInstitution(
    id: 'cib',
    name: '兴业银行',
    aliases: ['兴业', 'Industrial Bank', 'CIB'],
    asset: 'cib',
  ),
  IssuerInstitution(
    id: 'czbank',
    name: '浙商银行',
    aliases: ['浙商', 'CZBank', 'China Zheshang Bank'],
    asset: 'czbank',
  ),
  IssuerInstitution(
    id: 'cbhb',
    name: '渤海银行',
    aliases: ['渤海', 'Bohai Bank'],
    asset: 'cbhb',
  ),
  IssuerInstitution(
    id: 'hfbank',
    name: '恒丰银行',
    aliases: ['恒丰', 'Hengfeng Bank'],
    asset: 'hfbank',
  ),
  IssuerInstitution(
    id: 'bankofbeijing',
    name: '北京银行',
    aliases: ['Bank of Beijing'],
    asset: 'bankofbeijing',
  ),
  IssuerInstitution(
    id: 'bosc',
    name: '上海银行',
    aliases: ['Bank of Shanghai'],
    asset: 'bosc',
  ),
  IssuerInstitution(
    id: 'jsbchina',
    name: '江苏银行',
    aliases: ['Bank of Jiangsu'],
    asset: 'jsbchina',
  ),
  IssuerInstitution(
    id: 'njcb',
    name: '南京银行',
    aliases: ['Bank of Nanjing'],
    asset: 'njcb',
  ),
  IssuerInstitution(
    id: 'nbcb',
    name: '宁波银行',
    aliases: ['Bank of Ningbo'],
    asset: 'nbcb',
  ),
  IssuerInstitution(
    id: 'hzbank',
    name: '杭州银行',
    aliases: ['Bank of Hangzhou'],
    asset: 'hzbank',
  ),
  IssuerInstitution(
    id: 'bocd',
    name: '成都银行',
    aliases: ['Bank of Chengdu'],
    asset: 'bocd',
  ),
  IssuerInstitution(
    id: 'hsbank',
    name: '徽商银行',
    aliases: ['Huishang Bank'],
    asset: 'hsbank',
  ),
  IssuerInstitution(
    id: 'cqcbank',
    name: '重庆银行',
    aliases: ['Bank of Chongqing'],
    asset: 'cqcbank',
  ),
  IssuerInstitution(
    id: 'gzcb',
    name: '广州银行',
    aliases: ['Bank of Guangzhou'],
    asset: 'gzcb',
  ),
  IssuerInstitution(
    id: 'webank',
    name: '微众银行',
    aliases: ['WeBank', '微众'],
  ),
  IssuerInstitution(
    id: 'mybank',
    name: '网商银行',
    aliases: ['MYbank', '浙江网商银行'],
  ),
];

String _issuerSearchKey(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[\\s._,&/\\-]+'), '')
    .trim();

/// Exact issuer/alias match, for display only; never rewrites stored values.
IssuerInstitution? issuerForName(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final key = _issuerSearchKey(text);
  for (final issuer in issuerInstitutions) {
    if (_issuerSearchKey(issuer.name) == key ||
        issuer.aliases.any((alias) => _issuerSearchKey(alias) == key)) {
      return issuer;
    }
  }
  return null;
}

/// Local, case/spacing-insensitive suggestions (including Chinese aliases).
List<IssuerInstitution> suggestIssuers(String query, {int maxResults = 8}) {
  final key = _issuerSearchKey(query);
  if (key.isEmpty || maxResults < 1) return const [];
  final matches = <(int, IssuerInstitution)>[];
  for (final issuer in issuerInstitutions) {
    final labels = [issuer.name, ...issuer.aliases];
    final terms = labels.map(_issuerSearchKey);
    if (!terms.any((term) => term.contains(key))) continue;
    final exact = terms.any((term) => term == key);
    final prefix = terms.any((term) => term.startsWith(key));
    matches.add((exact ? 0 : prefix ? 1 : 2, issuer));
  }
  matches.sort((a, b) => a.$1.compareTo(b.$1));
  return matches.take(maxResults).map((match) => match.$2).toList();
}
