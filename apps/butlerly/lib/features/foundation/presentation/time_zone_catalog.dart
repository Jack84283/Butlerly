import 'package:flutter/material.dart';

final class ButlerlyTimeZone {
  const ButlerlyTimeZone(this.id, this.english, this.chinese);
  final String id;
  final String english;
  final String chinese;
  String label(Locale locale) =>
      locale.languageCode == 'zh' ? chinese : english;
}

const timeZoneCatalog = <ButlerlyTimeZone>[
  ButlerlyTimeZone('UTC', 'UTC', '协调世界时'),
  ButlerlyTimeZone('America/Los_Angeles', 'Pacific Time', '太平洋时间'),
  ButlerlyTimeZone('America/Denver', 'Mountain Time', '山地时间'),
  ButlerlyTimeZone('America/Chicago', 'Central Time', '中部时间'),
  ButlerlyTimeZone('America/New_York', 'Eastern Time', '东部时间'),
  ButlerlyTimeZone('Europe/London', 'London', '伦敦'),
  ButlerlyTimeZone('Europe/Paris', 'Paris', '巴黎'),
  ButlerlyTimeZone('Asia/Shanghai', 'China Standard Time', '中国标准时间'),
  ButlerlyTimeZone('Asia/Tokyo', 'Japan Standard Time', '日本标准时间'),
  ButlerlyTimeZone('Australia/Sydney', 'Australian Eastern Time', '澳大利亚东部时间'),
];
