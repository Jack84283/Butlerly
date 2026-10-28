import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Chinese brand name is consistent across user-facing messages', () {
    const zh = AppLocalizations(Locale('zh', 'CN'));
    const en = AppLocalizations(Locale('en'));

    expect(zh.text('appName'), '账房先生');
    expect(zh.text('about'), '关于 账房先生');
    expect(zh.text('welcomeTitle'), '欢迎使用 账房先生');
    expect(zh.text('builtin'), '账房先生');
    expect(zh.text('eraseAllTitle'), contains('账房先生'));
    expect(zh.text('eraseComplete'), contains('账房先生'));
    expect(en.text('appName'), 'Butlerly');
    expect(en.text('about'), 'About Butlerly');
  });
}
