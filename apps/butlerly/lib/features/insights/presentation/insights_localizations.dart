import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';

String insightText(BuildContext context, String key) {
  final languageCode = Localizations.localeOf(context).languageCode;
  final localized = _strings[languageCode]?[key] ?? _strings['en']?[key];
  return localized ?? context.l10n.text(key);
}

const _strings = <String, Map<String, String>>{
  'en': {
    'insightsPositiveChanges': 'Positive changes',
    'analysis.rule.r027.name': 'Spending decreased',
    'analysis.rule.r027.description':
        'You spent at least 20% less than in the previous equivalent period.',
    'analysis.rule.r028.name': 'Category spending decreased',
    'analysis.rule.r028.description':
        'Spending in this category fell by at least 20% from the previous equivalent period.',
    'analysis.rule.r029.name': 'Savings improved',
    'analysis.rule.r029.description':
        'Net savings improved compared with the previous equivalent period.',
  },
  'es': {
    'insightsPositiveChanges': 'Cambios positivos',
    'analysis.rule.r027.name': 'El gasto disminuyó',
    'analysis.rule.r027.description':
        'Gastaste al menos un 20 % menos que en el período equivalente anterior.',
    'analysis.rule.r028.name': 'El gasto por categoría disminuyó',
    'analysis.rule.r028.description':
        'El gasto en esta categoría bajó al menos un 20 % frente al período equivalente anterior.',
    'analysis.rule.r029.name': 'El ahorro mejoró',
    'analysis.rule.r029.description':
        'El ahorro neto mejoró frente al período equivalente anterior.',
  },
  'zh': {
    'insightsPositiveChanges': '积极变化',
    'analysis.rule.r027.name': '支出下降',
    'analysis.rule.r027.description': '与上一等效期间相比，你的支出至少下降了 20%。',
    'analysis.rule.r028.name': '分类支出下降',
    'analysis.rule.r028.description': '该分类的支出较上一等效期间至少下降了 20%。',
    'analysis.rule.r029.name': '储蓄改善',
    'analysis.rule.r029.description': '净储蓄较上一等效期间有所改善。',
  },
};
