import 'package:butlerly/design_system/tokens/butlerly_category_colors.dart';

/// Theme-independent identity for a category: stable ID, glyph asset, fixed
/// color identity, and localization reference. Labels are resolved elsewhere.
class ButlerlyCategoryIdentity {
  const ButlerlyCategoryIdentity._({
    required this.categoryId,
    required this.assetName,
    required this.colorId,
    required this.localizationKey,
  });

  final String categoryId;
  final String assetName;
  final ButlerlyCategoryColorId colorId;
  final String localizationKey;

  String get assetPath => 'assets/icons/categories/$assetName.svg';

  static const customCategoryId = 'custom';

  static ButlerlyCategoryIdentity forId(String categoryId) {
    final builtIn = _builtIns[categoryId];
    if (builtIn != null) {
      return builtIn._with(categoryId: categoryId, localizationKey: categoryId);
    }
    return ButlerlyCategoryIdentity._(
      categoryId: categoryId,
      assetName: 'custom',
      colorId: ButlerlyCategoryColors.forCustom(categoryId),
      localizationKey: 'category',
    );
  }

  ButlerlyCategoryIdentity _with({
    required String categoryId,
    required String localizationKey,
  }) => ButlerlyCategoryIdentity._(
    categoryId: categoryId,
    assetName: assetName,
    colorId: colorId,
    localizationKey: localizationKey,
  );

  static const builtInCategoryIds = <String>[
    'category.income',
    'category.income.salary',
    'category.income.bonus',
    'category.income.investment',
    'category.income.refund',
    'category.income.other',
    'category.food',
    'category.food.restaurants',
    'category.food.groceries',
    'category.food.coffee',
    'category.food.delivery',
    'category.transportation',
    'category.transportation.fuel',
    'category.transportation.public',
    'category.transportation.rideshare',
    'category.transportation.parking',
    'category.transportation.maintenance',
    'category.housing',
    'category.housing.rent_mortgage',
    'category.housing.utilities',
    'category.housing.maintenance',
    'category.shopping',
    'category.shopping.clothing',
    'category.shopping.electronics',
    'category.shopping.household',
    'category.health',
    'category.health.medical',
    'category.health.pharmacy',
    'category.health.fitness',
    'category.entertainment',
    'category.entertainment.streaming',
    'category.entertainment.events',
    'category.travel',
    'category.travel.airfare',
    'category.travel.hotel',
    'category.travel.local',
    'category.education',
    'category.personal',
    'category.gifts',
    'category.insurance',
    'category.taxes',
    'category.fees',
    'category.transfer',
    'category.uncategorized',
    'category.other',
  ];

  static const _builtIns = <String, ButlerlyCategoryIdentity>{
    'category.income': _income,
    'category.income.salary': _investments,
    'category.income.bonus': _investments,
    'category.income.investment': _investments,
    'category.income.refund': _refunds,
    'category.income.other': _other,
    'category.food': _food,
    'category.food.restaurants': _food,
    'category.food.groceries': _groceries,
    'category.food.coffee': _coffee,
    'category.food.delivery': _food,
    'category.transportation': _transport,
    'category.transportation.fuel': _fuel,
    'category.transportation.public': _transport,
    'category.transportation.rideshare': _car,
    'category.transportation.parking': _parking,
    'category.transportation.maintenance': _car,
    'category.housing': _home,
    'category.housing.rent_mortgage': _home,
    'category.housing.utilities': _utilities,
    'category.housing.maintenance': _homeServices,
    'category.shopping': _shopping,
    'category.shopping.clothing': _shopping,
    'category.shopping.electronics': _shopping,
    'category.shopping.household': _homeSupplies,
    'category.health': _health,
    'category.health.medical': _medical,
    'category.health.pharmacy': _medical,
    'category.health.fitness': _health,
    'category.entertainment': _entertainment,
    'category.entertainment.streaming': _subscriptions,
    'category.entertainment.events': _movies,
    'category.travel': _travel,
    'category.travel.airfare': _travel,
    'category.travel.hotel': _accommodation,
    'category.travel.local': _transport,
    'category.education': _education,
    'category.personal': _personalCare,
    'category.gifts': _gifts,
    'category.insurance': _insurance,
    'category.taxes': _taxes,
    'category.fees': _fees,
    'category.transfer': _other,
    'category.uncategorized': _other,
    'category.other': _other,
  };

  static const _income = ButlerlyCategoryIdentity._(
    categoryId: 'category.income',
    assetName: 'income',
    colorId: ButlerlyCategoryColorId.green,
    localizationKey: 'category.income',
  );
  static const _investments = ButlerlyCategoryIdentity._(
    categoryId: 'category.income.investment',
    assetName: 'investments',
    colorId: ButlerlyCategoryColorId.green,
    localizationKey: 'category.income.investment',
  );
  static const _refunds = ButlerlyCategoryIdentity._(
    categoryId: 'category.income.refund',
    assetName: 'refunds',
    colorId: ButlerlyCategoryColorId.teal,
    localizationKey: 'category.income.refund',
  );
  static const _food = ButlerlyCategoryIdentity._(
    categoryId: 'category.food',
    assetName: 'food_dining',
    colorId: ButlerlyCategoryColorId.orange,
    localizationKey: 'category.food',
  );
  static const _groceries = ButlerlyCategoryIdentity._(
    categoryId: 'category.food.groceries',
    assetName: 'groceries',
    colorId: ButlerlyCategoryColorId.green,
    localizationKey: 'category.food.groceries',
  );
  static const _coffee = ButlerlyCategoryIdentity._(
    categoryId: 'category.food.coffee',
    assetName: 'coffee',
    colorId: ButlerlyCategoryColorId.orange,
    localizationKey: 'category.food.coffee',
  );
  static const _transport = ButlerlyCategoryIdentity._(
    categoryId: 'category.transportation',
    assetName: 'transport',
    colorId: ButlerlyCategoryColorId.blue,
    localizationKey: 'category.transportation',
  );
  static const _fuel = ButlerlyCategoryIdentity._(
    categoryId: 'category.transportation.fuel',
    assetName: 'fuel',
    colorId: ButlerlyCategoryColorId.coral,
    localizationKey: 'category.transportation.fuel',
  );
  static const _car = ButlerlyCategoryIdentity._(
    categoryId: 'category.transportation.rideshare',
    assetName: 'car',
    colorId: ButlerlyCategoryColorId.blue,
    localizationKey: 'category.transportation.rideshare',
  );
  static const _parking = ButlerlyCategoryIdentity._(
    categoryId: 'category.transportation.parking',
    assetName: 'parking_tolls',
    colorId: ButlerlyCategoryColorId.purple,
    localizationKey: 'category.transportation.parking',
  );
  static const _home = ButlerlyCategoryIdentity._(
    categoryId: 'category.housing',
    assetName: 'home',
    colorId: ButlerlyCategoryColorId.purple,
    localizationKey: 'category.housing',
  );
  static const _utilities = ButlerlyCategoryIdentity._(
    categoryId: 'category.housing.utilities',
    assetName: 'utilities',
    colorId: ButlerlyCategoryColorId.gold,
    localizationKey: 'category.housing.utilities',
  );
  static const _homeServices = ButlerlyCategoryIdentity._(
    categoryId: 'category.housing.maintenance',
    assetName: 'home_services',
    colorId: ButlerlyCategoryColorId.slate,
    localizationKey: 'category.housing.maintenance',
  );
  static const _shopping = ButlerlyCategoryIdentity._(
    categoryId: 'category.shopping',
    assetName: 'shopping',
    colorId: ButlerlyCategoryColorId.coral,
    localizationKey: 'category.shopping',
  );
  static const _homeSupplies = ButlerlyCategoryIdentity._(
    categoryId: 'category.shopping.household',
    assetName: 'home_supplies',
    colorId: ButlerlyCategoryColorId.slate,
    localizationKey: 'category.shopping.household',
  );
  static const _health = ButlerlyCategoryIdentity._(
    categoryId: 'category.health',
    assetName: 'health_fitness',
    colorId: ButlerlyCategoryColorId.teal,
    localizationKey: 'category.health',
  );
  static const _medical = ButlerlyCategoryIdentity._(
    categoryId: 'category.health.medical',
    assetName: 'medical',
    colorId: ButlerlyCategoryColorId.teal,
    localizationKey: 'category.health.medical',
  );
  static const _entertainment = ButlerlyCategoryIdentity._(
    categoryId: 'category.entertainment',
    assetName: 'entertainment',
    colorId: ButlerlyCategoryColorId.purple,
    localizationKey: 'category.entertainment',
  );
  static const _subscriptions = ButlerlyCategoryIdentity._(
    categoryId: 'category.entertainment.streaming',
    assetName: 'subscriptions',
    colorId: ButlerlyCategoryColorId.purple,
    localizationKey: 'category.entertainment.streaming',
  );
  static const _movies = ButlerlyCategoryIdentity._(
    categoryId: 'category.entertainment.events',
    assetName: 'movies',
    colorId: ButlerlyCategoryColorId.purple,
    localizationKey: 'category.entertainment.events',
  );
  static const _travel = ButlerlyCategoryIdentity._(
    categoryId: 'category.travel',
    assetName: 'travel',
    colorId: ButlerlyCategoryColorId.blue,
    localizationKey: 'category.travel',
  );
  static const _accommodation = ButlerlyCategoryIdentity._(
    categoryId: 'category.travel.hotel',
    assetName: 'accommodation',
    colorId: ButlerlyCategoryColorId.blue,
    localizationKey: 'category.travel.hotel',
  );
  static const _education = ButlerlyCategoryIdentity._(
    categoryId: 'category.education',
    assetName: 'education',
    colorId: ButlerlyCategoryColorId.teal,
    localizationKey: 'category.education',
  );
  static const _personalCare = ButlerlyCategoryIdentity._(
    categoryId: 'category.personal',
    assetName: 'personal_care',
    colorId: ButlerlyCategoryColorId.orange,
    localizationKey: 'category.personal',
  );
  static const _gifts = ButlerlyCategoryIdentity._(
    categoryId: 'category.gifts',
    assetName: 'gifts_donations',
    colorId: ButlerlyCategoryColorId.coral,
    localizationKey: 'category.gifts',
  );
  static const _insurance = ButlerlyCategoryIdentity._(
    categoryId: 'category.insurance',
    assetName: 'insurance',
    colorId: ButlerlyCategoryColorId.green,
    localizationKey: 'category.insurance',
  );
  static const _taxes = ButlerlyCategoryIdentity._(
    categoryId: 'category.taxes',
    assetName: 'taxes',
    colorId: ButlerlyCategoryColorId.gold,
    localizationKey: 'category.taxes',
  );
  static const _fees = ButlerlyCategoryIdentity._(
    categoryId: 'category.fees',
    assetName: 'financial_fees',
    colorId: ButlerlyCategoryColorId.orange,
    localizationKey: 'category.fees',
  );
  static const _other = ButlerlyCategoryIdentity._(
    categoryId: 'category.other',
    assetName: 'other',
    colorId: ButlerlyCategoryColorId.slate,
    localizationKey: 'category.other',
  );
}
