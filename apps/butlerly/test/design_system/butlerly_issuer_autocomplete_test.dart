import 'dart:io';

import 'package:butlerly/design_system/components/butlerly_issuer_autocomplete.dart';
import 'package:butlerly/design_system/components/butlerly_issuer_catalog.dart';
import 'package:butlerly/design_system/components/butlerly_payment_source_icon.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('issuer catalog contains 29 US and 30 Chinese institutions', () {
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
  });

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

  test('every declared local logo exists and unknown logos fall back', () {
    final withArtwork = issuerInstitutions
        .where((issuer) => issuer.assetPath != null)
        .toList();
    expect(withArtwork.length, 37);
    for (final issuer in withArtwork) {
      final path = issuer.assetPath!;
      final logo = File(path);
      expect(logo.existsSync(), isTrue, reason: path);
      final text = logo.readAsStringSync();
      expect(text, contains('<svg'), reason: issuer.name);
      expect(text, contains('</svg>'), reason: issuer.name);
      expect(text, isNot(contains('<script')), reason: issuer.name);
    }
    expect(issuerForName('Capital One')?.assetPath, isNull);
    expect(issuerForName('微众银行')?.assetPath, isNull);
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

  testWidgets('issuer-marked accounts use bank logos but wallets keep brands', (
    tester,
  ) async {
    final sources = [
      PaymentSource(
        id: PaymentSourceId('checking'),
        name: 'Checking',
        issuer: 'Bank of America',
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
    expect(find.byType(ButlerlyIssuerIcon), findsNWidgets(2));
    expect(find.byType(ButlerlyPaymentMarkIcon), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
