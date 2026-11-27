import 'dart:io';

import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_issuer_autocomplete.dart';
import 'package:butlerly/design_system/components/butlerly_issuer_catalog.dart';
import 'package:butlerly/design_system/components/butlerly_payment_source_icon.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'issuer catalog preserves institution IDs, names and aliases in order',
    () {
      expect(
        issuerInstitutions.map(
          (issuer) => [issuer.id, issuer.name, ...issuer.aliases].join('|'),
        ),
        _catalogIdentity.trim().split('\n'),
      );
      for (final issuer in issuerInstitutions) {
        for (final label in [issuer.name, ...issuer.aliases]) {
          expect(issuerForName(label)?.id, issuer.id, reason: label);
        }
      }
      expect(issuerInstitutions.length, 59);
      expect(issuerInstitutions.map((issuer) => issuer.id).toSet().length, 59);
      expect(issuerForName('BoA')?.name, 'Bank of America');
      expect(issuerForName('B of A')?.name, 'Bank of America');
      expect(issuerForName('Citi Bank')?.name, 'Citibank');
      expect(issuerForName('CAPITAL ONE BANK')?.name, 'Capital One');
      expect(issuerForName('Wells Fargo Bank')?.name, 'Wells Fargo');
      expect(issuerForName('US Bank')?.name, 'U.S. Bank');
      expect(issuerForName('工行')?.name, '中国工商银行');
      expect(issuerForName('工商行')?.name, '中国工商银行');
      expect(issuerForName('农行')?.name, '中国农业银行');
      expect(issuerForName('Bank of China')?.name, '中国银行');
      expect(issuerForName('招行')?.name, '招商银行');
      expect(issuerForName('WeBank')?.name, '微众银行');
      expect(issuerForName('MYbank')?.name, '网商银行');
      expect(issuerForName('Not an actual issuer'), isNull);
      expect(issuerForName('Chase Sapphire'), isNull);
    },
  );

  test('search uses local aliases and no empty dropdown', () {
    expect(suggestIssuers(''), isEmpty);
    expect(suggestIssuers('BOA').first.name, 'Bank of America');
    expect(suggestIssuers('Citi Bank').first.name, 'Citibank');
    expect(suggestIssuers('工行').first.name, '中国工商银行');
    expect(suggestIssuers('农业行').first.name, '中国农业银行');
    expect(suggestIssuers('no matching bank name'), isEmpty);
    expect(suggestIssuers('Bank').length, lessThanOrEqualTo(8));
    expect(suggestIssuers('Bank', maxResults: 0), isEmpty);
  });

  test('issuer catalog and bundled offline SVGs agree exactly', () {
    final referenced = issuerInstitutions
        .where((issuer) => issuer.asset != null)
        .map((issuer) => '${issuer.asset}.svg')
        .toSet();
    final packaged = Directory('assets/icons/issuers')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.endsWith('.svg'))
        .toSet();

    expect(referenced, packaged);
    expect(referenced.length, 37);
    expect(
      issuerInstitutions.where((issuer) => issuer.asset == null).length,
      22,
    );
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('assets/icons/issuers/'),
    );
  });

  testWidgets('all bundled issuer SVGs decode and contain only local artwork', (
    tester,
  ) async {
    for (final issuer in issuerInstitutions.where(
      (issuer) => issuer.asset != null,
    )) {
      final source = File(issuer.assetPath!).readAsStringSync();
      expect(
        source,
        isNot(
          matches(
            RegExp(
              r'<(?:!DOCTYPE|!ENTITY|\?|(?:[\w.-]+:)?(?:script|foreignObject|image|style|a|animate\w*|set)\b)'
              r'|\b(?:href|src|on[\w.-]+)\s*=|\b(?:javascript|data)\s*:|@import|url\s*\(',
              caseSensitive: false,
            ),
          ),
        ),
        reason: issuer.assetPath,
      );
      // Exercise the same flutter_svg decoder used by the production icon.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SvgPicture.string(source, width: 30, height: 30),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: issuer.assetPath);
      expect(find.byType(SvgPicture), findsOneWidget);
    }
  });

  testWidgets('autocomplete canonicalizes aliases but keeps custom entries', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: ButlerlyIssuerAutocomplete(
              controller: controller,
              label: 'Issuer',
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'BoA');
    await tester.pumpAndSettle();
    expect(find.text('Bank of America'), findsWidgets);
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Bank of America'))
          .selected,
      isTrue,
    );
    await tester.tap(find.text('Bank of America').last);
    await tester.pumpAndSettle();
    expect(controller.text, 'Bank of America');
    expect(find.byType(SvgPicture), findsWidgets);

    await tester.enterText(find.byType(TextField), 'My local credit union');
    await tester.pumpAndSettle();
    expect(controller.text, 'My local credit union');
    expect(find.text('Bank of America'), findsNothing);

    await tester.enterText(find.byType(TextField), '工行');
    await tester.pumpAndSettle();
    expect(find.text('中国工商银行'), findsWidgets);
    await tester.tap(find.text('中国工商银行').last);
    await tester.pumpAndSettle();
    expect(controller.text, '中国工商银行');
    expect(tester.takeException(), isNull);
  });

  testWidgets('issuer artwork and fallback retain sizes and semantics', (
    tester,
  ) async {
    final branded = issuerForName('BoA')!;
    final fallback = issuerForName('WeBank')!;
    for (final theme in [AppTheme.light, AppTheme.navy, AppTheme.dark]) {
      for (final size in [24.0, 30.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Row(
                children: [
                  ButlerlyIssuerIcon(issuer: branded, size: size),
                  ButlerlyIssuerIcon(issuer: fallback, size: size),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(SvgPicture)), Size.square(size));
        expect(
          tester.getSize(find.byIcon(Icons.account_balance_outlined)),
          Size.square(size),
        );
        expect(find.bySemanticsLabel(branded.name), findsOneWidget);
        expect(find.bySemanticsLabel(fallback.name), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('issuer-marked accounts use bank logos but wallets keep brands', (
    tester,
  ) async {
    final sources = [
      PaymentSource(
        id: PaymentSourceId('checking'),
        name: 'Checking',
        issuer: 'BoA',
        type: PaymentSourceType.account,
      ),
      PaymentSource(
        id: PaymentSourceId('credit'),
        name: 'Chase card',
        issuer: 'Chase',
        network: 'visa',
        type: PaymentSourceType.card,
        lastFour: '1234',
      ),
      PaymentSource(
        id: PaymentSourceId('wallet'),
        name: 'PayPal',
        issuer: 'Chase',
        network: 'paypal',
        type: PaymentSourceType.wallet,
      ),
      PaymentSource(
        id: PaymentSourceId('no-logo'),
        name: 'Capital One card',
        issuer: 'Capital One',
        network: 'visa',
        type: PaymentSourceType.card,
        lastFour: '5678',
      ),
      PaymentSource(
        id: PaymentSourceId('custom-issuer'),
        name: 'Credit union debit card',
        issuer: 'My local credit union',
        network: 'mastercard',
        type: PaymentSourceType.debitCard,
      ),
      PaymentSource(
        id: PaymentSourceId('network-only'),
        name: 'Visa card',
        network: 'visa',
        type: PaymentSourceType.card,
      ),
      PaymentSource(
        id: PaymentSourceId('legacy-wallet'),
        name: 'PayPal',
        type: PaymentSourceType.account,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final source in sources)
                ButlerlyPaymentSourceIcon(source: source),
            ],
          ),
        ),
      ),
    );
    // Three recognized issuers, including Capital One with no official logo.
    expect(find.byType(ButlerlyIssuerIcon), findsNWidgets(3));
    // Capital One and an unrecognized credit union use neutral bank imagery,
    // not the separately selected Visa/Mastercard network marks.
    expect(find.byIcon(Icons.account_balance_outlined), findsNWidgets(2));
    // Wallets and card sources with no specified issuer retain provider/
    // network artwork, including old account-typed wallet records.
    expect(find.byType(ButlerlyPaymentMarkIcon), findsNWidgets(3));
    expect(sources.first.issuer, 'BoA');
    expect(sources[1].network, 'visa');
    expect(sources[2].network, 'paypal');
    expect(tester.takeException(), isNull);
  });
}

const _catalogIdentity = '''
chase|Chase|Chase Bank|JPMorgan Chase|JP Morgan
bankofamerica|Bank of America|BoA|BofA|B of A
citibank|Citibank|Citi|CitiBank|Citi Bank
capitalone|Capital One|CapitalOne|Capital One Bank
wellsfargo|Wells Fargo|Wells Fargo Bank
usbank|U.S. Bank|US Bank|USBank|U S Bank
pnc|PNC Bank|PNC
truist|Truist Bank|Truist
tdbank|TD Bank|TD
bmo|BMO Bank|BMO|BMO Harris
citizens|Citizens Bank|Citizens
fifththird|Fifth Third Bank|Fifth Third|5/3 Bank
huntington|Huntington Bank|Huntington|Huntington National Bank
keybank|KeyBank|Key Bank
regions|Regions Bank|Regions
mtbank|M&T Bank|M&T
santander|Santander Bank|Santander
firstcitizens|First Citizens Bank|First Citizens
firsthorizon|First Horizon Bank|First Horizon
ally|Ally Bank|Ally
sofi|SoFi Bank|SoFi
americanexpress|American Express|Amex|American Express National Bank
discover|Discover|Discover Bank
synchrony|Synchrony Bank|Synchrony
barclays|Barclays|Barclays Bank|Barclaycard
goldmansachs|Goldman Sachs Bank|Goldman Sachs|Marcus
schwab|Charles Schwab Bank|Schwab Bank|Schwab
usaa|USAA|USAA Federal Savings Bank
navyfederal|Navy Federal Credit Union|Navy Federal|NFCU
icbc|中国工商银行|工商银行|工商行|工行|ICBC|Industrial and Commercial Bank of China
abchina|中国农业银行|农业银行|农业行|农行|ABC|Agricultural Bank of China
boc|中国银行|中行|BOC|Bank of China
ccb|中国建设银行|建设银行|建行|CCB|China Construction Bank
bankcomm|交通银行|交行|BOCOM|Bank of Communications
psbc|中国邮政储蓄银行|邮储银行|邮储|邮政储蓄银行|PSBC|Postal Savings Bank of China
cmbchina|招商银行|招行|CMB|China Merchants Bank
citicbank|中信银行|中信|CITIC Bank
cebbank|中国光大银行|光大银行|光大|CEB|China Everbright Bank
hxb|华夏银行|华夏|Hua Xia Bank
cmbc|中国民生银行|民生银行|民生|CMBC|China Minsheng Bank
spdb|上海浦东发展银行|浦发银行|浦发|SPDB
cgbchina|广发银行|广发|广东发展银行|CGB
pingan|平安银行|平安|Ping An Bank
cib|兴业银行|兴业|Industrial Bank|CIB
czbank|浙商银行|浙商|CZBank|China Zheshang Bank
cbhb|渤海银行|渤海|Bohai Bank
hfbank|恒丰银行|恒丰|Hengfeng Bank
bankofbeijing|北京银行|Bank of Beijing
bosc|上海银行|Bank of Shanghai
jsbchina|江苏银行|Bank of Jiangsu
njcb|南京银行|Bank of Nanjing
nbcb|宁波银行|Bank of Ningbo
hzbank|杭州银行|Bank of Hangzhou
bocd|成都银行|Bank of Chengdu
hsbank|徽商银行|Huishang Bank
cqcbank|重庆银行|Bank of Chongqing
gzcb|广州银行|Bank of Guangzhou
webank|微众银行|WeBank|微众
mybank|网商银行|MYbank|浙江网商银行
''';
