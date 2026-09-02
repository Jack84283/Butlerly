import 'package:butlerly/design_system/tokens/butlerly_category_colors.dart';

/// Persistent visual identity for a category.
///
/// Application theme controls surfaces and text. Category identity controls
/// the category glyph and fixed color. User-facing labels remain in the
/// localization/master-data layer and are never used as lookup keys.
enum ButlerlyCategoryIdentityKind { builtIn, custom }

final class ButlerlyCategoryIdentity {
  const ButlerlyCategoryIdentity._({
    required this.kind,
    required this.categoryId,
    required this.assetName,
    required this.categoryColorId,
    required this.localizationKey,
  });

  final ButlerlyCategoryIdentityKind kind;
  final String categoryId;
  final String assetName;
  final ButlerlyCategoryColorId categoryColorId;
  final String localizationKey;

  String get assetPath => 'assets/icons/categories/$assetName.svg';

  /// Resolves a system category. Unknown IDs return null and are not custom.
  static ButlerlyCategoryIdentity? forBuiltInId(String categoryId) =>
      _builtIns[categoryId];

  /// Creates the identity for a persisted user category.
  ///
  /// The color must come from the persisted custom-category record. The
  /// current Category domain entity has no color field yet, so callers must
  /// supply that value when the persistence model gains this capability.
  static ButlerlyCategoryIdentity custom({
    required String categoryId,
    required ButlerlyCategoryColorId categoryColorId,
  }) => ButlerlyCategoryIdentity._(
    kind: ButlerlyCategoryIdentityKind.custom,
    categoryId: categoryId,
    assetName: 'custom',
    categoryColorId: categoryColorId,
    localizationKey: 'category',
  );

  /// The keys are the authoritative built-in category IDs represented here.
  static Iterable<String> get builtInCategoryIds => _builtIns.keys;

  static const _builtIns = <String, ButlerlyCategoryIdentity>{
    'category.income': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.income',
      assetName: 'income',
      categoryColorId: ButlerlyCategoryColorId.green,
      localizationKey: 'category.income',
    ),
    'category.income.salary': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.income.salary',
      assetName: 'investments',
      categoryColorId: ButlerlyCategoryColorId.green,
      localizationKey: 'category.income.salary',
    ),
    'category.income.bonus': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.income.bonus',
      assetName: 'investments',
      categoryColorId: ButlerlyCategoryColorId.green,
      localizationKey: 'category.income.bonus',
    ),
    'category.income.investment': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.income.investment',
      assetName: 'investments',
      categoryColorId: ButlerlyCategoryColorId.green,
      localizationKey: 'category.income.investment',
    ),
    'category.income.refund': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.income.refund',
      assetName: 'refunds',
      categoryColorId: ButlerlyCategoryColorId.teal,
      localizationKey: 'category.income.refund',
    ),
    'category.income.other': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.income.other',
      assetName: 'other',
      categoryColorId: ButlerlyCategoryColorId.slate,
      localizationKey: 'category.income.other',
    ),
    'category.food': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.food',
      assetName: 'food_dining',
      categoryColorId: ButlerlyCategoryColorId.orange,
      localizationKey: 'category.food',
    ),
    'category.food.restaurants': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.food.restaurants',
      assetName: 'food_dining',
      categoryColorId: ButlerlyCategoryColorId.orange,
      localizationKey: 'category.food.restaurants',
    ),
    'category.food.groceries': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.food.groceries',
      assetName: 'groceries',
      categoryColorId: ButlerlyCategoryColorId.green,
      localizationKey: 'category.food.groceries',
    ),
    'category.food.coffee': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.food.coffee',
      assetName: 'coffee',
      categoryColorId: ButlerlyCategoryColorId.orange,
      localizationKey: 'category.food.coffee',
    ),
    'category.food.delivery': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.food.delivery',
      assetName: 'food_dining',
      categoryColorId: ButlerlyCategoryColorId.orange,
      localizationKey: 'category.food.delivery',
    ),
    'category.transportation': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.transportation',
      assetName: 'transport',
      categoryColorId: ButlerlyCategoryColorId.blue,
      localizationKey: 'category.transportation',
    ),
    'category.transportation.fuel': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.transportation.fuel',
      assetName: 'fuel',
      categoryColorId: ButlerlyCategoryColorId.coral,
      localizationKey: 'category.transportation.fuel',
    ),
    'category.transportation.public': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.transportation.public',
      assetName: 'transport',
      categoryColorId: ButlerlyCategoryColorId.blue,
      localizationKey: 'category.transportation.public',
    ),
    'category.transportation.rideshare': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.transportation.rideshare',
      assetName: 'car',
      categoryColorId: ButlerlyCategoryColorId.blue,
      localizationKey: 'category.transportation.rideshare',
    ),
    'category.transportation.parking': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.transportation.parking',
      assetName: 'parking_tolls',
      categoryColorId: ButlerlyCategoryColorId.purple,
      localizationKey: 'category.transportation.parking',
    ),
    'category.transportation.maintenance': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.transportation.maintenance',
      assetName: 'car',
      categoryColorId: ButlerlyCategoryColorId.blue,
      localizationKey: 'category.transportation.maintenance',
    ),
    'category.housing': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.housing',
      assetName: 'home',
      categoryColorId: ButlerlyCategoryColorId.purple,
      localizationKey: 'category.housing',
    ),
    'category.housing.rent_mortgage': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.housing.rent_mortgage',
      assetName: 'home',
      categoryColorId: ButlerlyCategoryColorId.purple,
      localizationKey: 'category.housing.rent_mortgage',
    ),
    'category.housing.utilities': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.housing.utilities',
      assetName: 'utilities',
      categoryColorId: ButlerlyCategoryColorId.gold,
      localizationKey: 'category.housing.utilities',
    ),
    'category.housing.maintenance': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.housing.maintenance',
      assetName: 'home_services',
      categoryColorId: ButlerlyCategoryColorId.slate,
      localizationKey: 'category.housing.maintenance',
    ),
    'category.shopping': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.shopping',
      assetName: 'shopping',
      categoryColorId: ButlerlyCategoryColorId.coral,
      localizationKey: 'category.shopping',
    ),
    'category.shopping.clothing': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.shopping.clothing',
      assetName: 'shopping',
      categoryColorId: ButlerlyCategoryColorId.coral,
      localizationKey: 'category.shopping.clothing',
    ),
    'category.shopping.electronics': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.shopping.electronics',
      assetName: 'shopping',
      categoryColorId: ButlerlyCategoryColorId.coral,
      localizationKey: 'category.shopping.electronics',
    ),
    'category.shopping.household': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.shopping.household',
      assetName: 'home_supplies',
      categoryColorId: ButlerlyCategoryColorId.slate,
      localizationKey: 'category.shopping.household',
    ),
    'category.health': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.health',
      assetName: 'health_fitness',
      categoryColorId: ButlerlyCategoryColorId.teal,
      localizationKey: 'category.health',
    ),
    'category.health.medical': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.health.medical',
      assetName: 'medical',
      categoryColorId: ButlerlyCategoryColorId.teal,
      localizationKey: 'category.health.medical',
    ),
    'category.health.pharmacy': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.health.pharmacy',
      assetName: 'medical',
      categoryColorId: ButlerlyCategoryColorId.teal,
      localizationKey: 'category.health.pharmacy',
    ),
    'category.health.fitness': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.health.fitness',
      assetName: 'health_fitness',
      categoryColorId: ButlerlyCategoryColorId.teal,
      localizationKey: 'category.health.fitness',
    ),
    'category.entertainment': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.entertainment',
      assetName: 'entertainment',
      categoryColorId: ButlerlyCategoryColorId.purple,
      localizationKey: 'category.entertainment',
    ),
    'category.entertainment.streaming': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.entertainment.streaming',
      assetName: 'subscriptions',
      categoryColorId: ButlerlyCategoryColorId.purple,
      localizationKey: 'category.entertainment.streaming',
    ),
    'category.entertainment.events': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.entertainment.events',
      assetName: 'movies',
      categoryColorId: ButlerlyCategoryColorId.purple,
      localizationKey: 'category.entertainment.events',
    ),
    'category.travel': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.travel',
      assetName: 'travel',
      categoryColorId: ButlerlyCategoryColorId.blue,
      localizationKey: 'category.travel',
    ),
    'category.travel.airfare': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.travel.airfare',
      assetName: 'travel',
      categoryColorId: ButlerlyCategoryColorId.blue,
      localizationKey: 'category.travel.airfare',
    ),
    'category.travel.hotel': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.travel.hotel',
      assetName: 'accommodation',
      categoryColorId: ButlerlyCategoryColorId.blue,
      localizationKey: 'category.travel.hotel',
    ),
    'category.travel.local': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.travel.local',
      assetName: 'transport',
      categoryColorId: ButlerlyCategoryColorId.blue,
      localizationKey: 'category.travel.local',
    ),
    'category.education': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.education',
      assetName: 'education',
      categoryColorId: ButlerlyCategoryColorId.teal,
      localizationKey: 'category.education',
    ),
    'category.personal': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.personal',
      assetName: 'personal_care',
      categoryColorId: ButlerlyCategoryColorId.orange,
      localizationKey: 'category.personal',
    ),
    'category.gifts': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.gifts',
      assetName: 'gifts_donations',
      categoryColorId: ButlerlyCategoryColorId.coral,
      localizationKey: 'category.gifts',
    ),
    'category.insurance': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.insurance',
      assetName: 'insurance',
      categoryColorId: ButlerlyCategoryColorId.green,
      localizationKey: 'category.insurance',
    ),
    'category.taxes': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.taxes',
      assetName: 'taxes',
      categoryColorId: ButlerlyCategoryColorId.gold,
      localizationKey: 'category.taxes',
    ),
    'category.fees': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.fees',
      assetName: 'financial_fees',
      categoryColorId: ButlerlyCategoryColorId.orange,
      localizationKey: 'category.fees',
    ),
    'category.transfer': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.transfer',
      assetName: 'other',
      categoryColorId: ButlerlyCategoryColorId.slate,
      localizationKey: 'category.transfer',
    ),
    'category.uncategorized': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.uncategorized',
      assetName: 'other',
      categoryColorId: ButlerlyCategoryColorId.slate,
      localizationKey: 'category.uncategorized',
    ),
    'category.other': ButlerlyCategoryIdentity._(
      kind: ButlerlyCategoryIdentityKind.builtIn,
      categoryId: 'category.other',
      assetName: 'other',
      categoryColorId: ButlerlyCategoryColorId.slate,
      localizationKey: 'category.other',
    ),
  };
}
