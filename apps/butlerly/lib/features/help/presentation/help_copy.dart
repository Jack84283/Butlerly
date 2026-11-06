import 'package:flutter/widgets.dart';

/// Feature-scoped presentation labels. FAQ text itself lives in bundled JSON.
class HelpCopy {
  const HelpCopy._();

  static const _labels = <String, Map<String, String>>{
    'en': {
      'title': 'Help & FAQ',
      'subtitle': 'Answers and guides stored on your device',
      'search': 'Search help',
      'clear': 'Clear search',
      'topics': 'Browse topics',
      'all': 'All topics',
      'popular': 'Popular questions',
      'fullGuide': 'View full User Guide',
      'guide': 'User Guide',
      'guideSubtitle': 'Complete guide · Available offline',
      'faq': 'FAQ',
      'guideArticle': 'Guide',
      'readMore': 'Read detailed guide',
      'noResults': 'No matching help topics',
      'noResultsBody': 'Try another phrase or choose a topic below.',
      'suggestedTopics': 'Suggested topics',
      'reportProblem': 'How to report an Alpha problem safely',
      'loadFailed': 'Help could not be opened. Please try again.',
      'retry': 'Try again',
      'back': 'Back',
      'category:Getting Started': 'Getting started',
      'category:Transactions': 'Transactions',
      'category:Imports': 'Imports',
      'category:Receipts': 'Receipts',
      'category:Review': 'Review & duplicates',
      'category:Analysis': 'Analysis',
      'category:Budgets': 'Budgets',
      'category:Backup & Recovery': 'Backup & recovery',
      'category:Privacy': 'Privacy',
      'category:Plans': 'Plans',
      'category:Help': 'Help',
      'category:Troubleshooting': 'Troubleshooting',
    },
    'zh': {
      'title': '帮助与常见问题',
      'subtitle': '保存在设备上的使用指南与解答',
      'search': '搜索帮助',
      'clear': '清除搜索',
      'topics': '按主题浏览',
      'all': '全部主题',
      'popular': '常见问题',
      'fullGuide': '查看完整用户指南',
      'guide': '用户指南',
      'guideSubtitle': '完整指南 · 支持离线阅读',
      'faq': '常见问题',
      'guideArticle': '指南',
      'readMore': '阅读详细指南',
      'noResults': '未找到相关帮助',
      'noResultsBody': '请尝试其他关键词，或浏览下方主题。',
      'suggestedTopics': '推荐主题',
      'reportProblem': '如何安全反馈 Alpha 问题',
      'loadFailed': '无法打开帮助内容，请重试。',
      'retry': '重试',
      'back': '返回',
      'category:Getting Started': '开始使用',
      'category:Transactions': '交易记录',
      'category:Imports': '导入',
      'category:Receipts': '收据',
      'category:Review': '审核与重复记录',
      'category:Analysis': '财务分析',
      'category:Budgets': '预算',
      'category:Backup & Recovery': '备份与恢复',
      'category:Privacy': '隐私',
      'category:Plans': '套餐',
      'category:Help': '帮助',
      'category:Troubleshooting': '问题排查',
    },
    'es': {
      'title': 'Ayuda y preguntas frecuentes',
      'subtitle': 'Guías y respuestas guardadas en tu dispositivo',
      'search': 'Buscar ayuda',
      'clear': 'Borrar búsqueda',
      'topics': 'Explorar temas',
      'all': 'Todos los temas',
      'popular': 'Preguntas populares',
      'fullGuide': 'Ver guía completa',
      'guide': 'Guía del usuario',
      'guideSubtitle': 'Guía completa · Disponible sin conexión',
      'faq': 'Preguntas frecuentes',
      'guideArticle': 'Guía',
      'readMore': 'Leer guía detallada',
      'noResults': 'No hay resultados',
      'noResultsBody': 'Prueba otra frase o elige uno de estos temas.',
      'suggestedTopics': 'Temas sugeridos',
      'reportProblem': 'Cómo informar de un problema de Alpha',
      'loadFailed': 'No se pudo abrir la ayuda. Inténtalo de nuevo.',
      'retry': 'Reintentar',
      'back': 'Volver',
      'category:Getting Started': 'Primeros pasos',
      'category:Transactions': 'Transacciones',
      'category:Imports': 'Importaciones',
      'category:Receipts': 'Recibos',
      'category:Review': 'Revisión y duplicados',
      'category:Analysis': 'Análisis',
      'category:Budgets': 'Presupuestos',
      'category:Backup & Recovery': 'Copias y recuperación',
      'category:Privacy': 'Privacidad',
      'category:Plans': 'Planes',
      'category:Help': 'Ayuda',
      'category:Troubleshooting': 'Solución de problemas',
    },
  };

  static String text(BuildContext context, String key) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return _labels[languageCode]?[key] ?? _labels['en']![key] ?? key;
  }

  static String category(BuildContext context, String name) =>
      text(context, 'category:$name');

  static Set<String> missingKeysFor(String languageCode) =>
      _labels['en']!.keys.toSet().difference(
        (_labels[languageCode] ?? const <String, String>{}).keys.toSet(),
      );
}
