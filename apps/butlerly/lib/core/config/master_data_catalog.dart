import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

List<MasterTranslation> systemMasterTranslations() => [
  for (final entry in _en.entries)
    MasterTranslation(
      masterType: entry.key.startsWith('category.') ? 'category' : 'tag',
      masterId: entry.key,
      locale: 'en',
      label: entry.value,
    ),
  for (final entry in _zh.entries)
    MasterTranslation(
      masterType: entry.key.startsWith('category.') ? 'category' : 'tag',
      masterId: entry.key,
      locale: 'zh-Hans',
      label: entry.value,
    ),
  for (final entry in _es.entries)
    MasterTranslation(
      masterType: entry.key.startsWith('category.') ? 'category' : 'tag',
      masterId: entry.key,
      locale: 'es',
      label: entry.value,
    ),
];

/// Resolves Butlerly-owned labels without changing the stable domain value.
/// User/source text deliberately bypasses this catalog.
String categoryDisplayLabel(Category value, String languageCode) {
  if (value.origin == CategoryOrigin.user) return value.name;
  return _systemLabel(value.id.value, languageCode) ??
      _systemLabelByEnglish(value.name, languageCode) ??
      value.name;
}

String tagDisplayLabel(Tag value, String languageCode) {
  final catalogId = value.id.value.startsWith('system-tag-')
      ? 'tag.${value.id.value.substring('system-tag-'.length)}'
      : value.id.value;
  if (catalogId.startsWith('tag.') == false) return value.name;
  return _systemLabel(catalogId, languageCode) ??
      _systemLabelByEnglish(value.name, languageCode) ??
      value.name;
}

String? _systemLabelByEnglish(String name, String languageCode) {
  final normalized = name.trim().toLowerCase();
  final id = _en.entries
      .where((entry) => entry.value.toLowerCase() == normalized)
      .map((entry) => entry.key)
      .firstOrNull;
  return id == null ? null : _systemLabel(id, languageCode);
}

String? _systemLabel(String id, String languageCode) {
  final zh = languageCode == 'zh' || languageCode == 'zh-Hans';
  return (zh
      ? _zh
      : languageCode == 'es'
      ? _es
      : _en)[id];
}

const _en = <String, String>{
  'category.income': 'Income',
  'category.income.salary': 'Salary',
  'category.income.bonus': 'Bonus',
  'category.income.investment': 'Investment Income',
  'category.income.refund': 'Refund',
  'category.income.other': 'Other Income',
  'category.food': 'Food & Dining',
  'category.food.restaurants': 'Restaurants',
  'category.food.groceries': 'Groceries',
  'category.food.coffee': 'Coffee & Drinks',
  'category.food.delivery': 'Delivery & Takeout',
  'category.transportation': 'Transportation',
  'category.transportation.fuel': 'Fuel',
  'category.transportation.public': 'Public Transit',
  'category.transportation.rideshare': 'Taxi & Rideshare',
  'category.transportation.parking': 'Parking',
  'category.transportation.maintenance': 'Vehicle Maintenance',
  'category.housing': 'Housing',
  'category.housing.rent_mortgage': 'Rent & Mortgage',
  'category.housing.utilities': 'Utilities',
  'category.housing.maintenance': 'Home Maintenance',
  'category.shopping': 'Shopping',
  'category.shopping.clothing': 'Clothing',
  'category.shopping.electronics': 'Electronics',
  'category.shopping.household': 'Household',
  'category.health': 'Health',
  'category.health.medical': 'Medical',
  'category.health.pharmacy': 'Pharmacy',
  'category.health.fitness': 'Fitness',
  'category.entertainment': 'Entertainment',
  'category.entertainment.streaming': 'Streaming & Subscriptions',
  'category.entertainment.events': 'Events',
  'category.travel': 'Travel',
  'category.travel.airfare': 'Airfare',
  'category.travel.hotel': 'Hotels',
  'category.travel.local': 'Local Transportation',
  'category.education': 'Education',
  'category.personal': 'Personal Care',
  'category.gifts': 'Gifts & Donations',
  'category.insurance': 'Insurance',
  'category.taxes': 'Taxes',
  'category.fees': 'Fees & Charges',
  'category.transfer': 'Transfer',
  'category.uncategorized': 'Uncategorized',
  'category.other': 'Other',
  'tag.business': 'Business',
  'tag.personal': 'Personal',
  'tag.reimbursable': 'Reimbursable',
  'tag.tax_related': 'Tax Related',
  'tag.travel': 'Travel',
  'tag.recurring': 'Recurring',
  'tag.subscription': 'Subscription',
};

const _zh = <String, String>{
  'category.income': '收入',
  'category.income.salary': '工资',
  'category.income.bonus': '奖金',
  'category.income.investment': '投资收入',
  'category.income.refund': '退款',
  'category.income.other': '其他收入',
  'category.food': '餐饮',
  'category.food.restaurants': '餐厅',
  'category.food.groceries': '食品杂货',
  'category.food.coffee': '咖啡与饮品',
  'category.food.delivery': '外卖与外带',
  'category.transportation': '交通',
  'category.transportation.fuel': '燃油',
  'category.transportation.public': '公共交通',
  'category.transportation.rideshare': '出租车与网约车',
  'category.transportation.parking': '停车',
  'category.transportation.maintenance': '车辆维护',
  'category.housing': '住房',
  'category.housing.rent_mortgage': '房租与房贷',
  'category.housing.utilities': '水电燃气',
  'category.housing.maintenance': '房屋维护',
  'category.shopping': '购物',
  'category.shopping.clothing': '服装',
  'category.shopping.electronics': '电子产品',
  'category.shopping.household': '家居用品',
  'category.health': '医疗健康',
  'category.health.medical': '医疗',
  'category.health.pharmacy': '药品',
  'category.health.fitness': '健身',
  'category.entertainment': '娱乐',
  'category.entertainment.streaming': '流媒体与订阅',
  'category.entertainment.events': '活动',
  'category.travel': '旅行',
  'category.travel.airfare': '机票',
  'category.travel.hotel': '酒店',
  'category.travel.local': '当地交通',
  'category.education': '教育',
  'category.personal': '个人护理',
  'category.gifts': '礼物与捐赠',
  'category.insurance': '保险',
  'category.taxes': '税费',
  'category.fees': '手续费与费用',
  'category.transfer': '转账',
  'category.uncategorized': '未分类',
  'category.other': '其他',
  'tag.business': '商务',
  'tag.personal': '个人',
  'tag.reimbursable': '可报销',
  'tag.tax_related': '税务相关',
  'tag.travel': '旅行',
  'tag.recurring': '定期',
  'tag.subscription': '订阅',
};

const _es = <String, String>{
  'category.income': 'Ingresos',
  'category.income.salary': 'Salario',
  'category.income.bonus': 'Bonificación',
  'category.income.investment': 'Ingresos por inversiones',
  'category.income.refund': 'Reembolso',
  'category.income.other': 'Otros ingresos',
  'category.food': 'Comida y restaurantes',
  'category.food.restaurants': 'Restaurantes',
  'category.food.groceries': 'Comestibles',
  'category.food.coffee': 'Café y bebidas',
  'category.food.delivery': 'Entrega y comida para llevar',
  'category.transportation': 'Transporte',
  'category.transportation.fuel': 'Combustible',
  'category.transportation.public': 'Transporte público',
  'category.transportation.rideshare': 'Taxi y transporte compartido',
  'category.transportation.parking': 'Estacionamiento',
  'category.transportation.maintenance': 'Mantenimiento del vehículo',
  'category.housing': 'Vivienda',
  'category.housing.rent_mortgage': 'Alquiler e hipoteca',
  'category.housing.utilities': 'Servicios públicos',
  'category.housing.maintenance': 'Mantenimiento del hogar',
  'category.shopping': 'Compras',
  'category.shopping.clothing': 'Ropa',
  'category.shopping.electronics': 'Electrónica',
  'category.shopping.household': 'Hogar',
  'category.health': 'Salud',
  'category.health.medical': 'Atención médica',
  'category.health.pharmacy': 'Farmacia',
  'category.health.fitness': 'Fitness',
  'category.entertainment': 'Entretenimiento',
  'category.entertainment.streaming': 'Streaming y suscripciones',
  'category.entertainment.events': 'Eventos',
  'category.travel': 'Viajes',
  'category.travel.airfare': 'Vuelos',
  'category.travel.hotel': 'Hoteles',
  'category.travel.local': 'Transporte local',
  'category.education': 'Educación',
  'category.personal': 'Cuidado personal',
  'category.gifts': 'Regalos y donaciones',
  'category.insurance': 'Seguros',
  'category.taxes': 'Impuestos',
  'category.fees': 'Comisiones y cargos',
  'category.transfer': 'Transferencia',
  'category.uncategorized': 'Sin categoría',
  'category.other': 'Otros',
  'tag.business': 'Negocios',
  'tag.personal': 'Personal',
  'tag.reimbursable': 'Reembolsable',
  'tag.tax_related': 'Relacionado con impuestos',
  'tag.travel': 'Viajes',
  'tag.recurring': 'Recurrente',
  'tag.subscription': 'Suscripción',
};
