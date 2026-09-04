import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import 'master_data_seed.dart';
import 'reference_data_seed.dart';

/// The MD-0001 V1 system catalog. Labels are persisted separately as
/// translations; these domain records contain stable semantic IDs.
InitialMasterData buildInitialMasterData() => InitialMasterData(
  merchants: [
    for (final row in _merchants)
      Merchant(
        id: MerchantId(row.$1),
        name: row.$2,
        normalizedName: normalizeMerchantName(row.$2),
        defaultCategoryId: CategoryId(row.$3),
        defaultSubcategoryId: row.$4 == null ? null : CategoryId(row.$4!),
        isBuiltIn: true,
      ),
  ],
  categories: [
    for (final row in _categories)
      Category(
        id: CategoryId(row.$1),
        name: row.$2,
        origin: CategoryOrigin.system,
        parentId: row.$3 == null ? null : CategoryId(row.$3!),
      ),
  ],
  tags: [for (final row in _tags) Tag(id: TagId(row.$1), name: row.$2)],
  translations: systemMasterTranslations(),
  referenceData: [for (final row in md0001ReferenceData) row.value],
  referenceTranslations: [
    for (final row in md0001ReferenceData)
      for (final translation in row.translations)
        MasterTranslation(
          masterType: 'reference_data',
          masterId: translation.id.value,
          locale: translation.locale,
          label: translation.label,
        ),
  ],
);

const _categories = <(String, String, String?)>[
  ('category.income', 'Income', null),
  ('category.income.salary', 'Salary', 'category.income'),
  ('category.income.bonus', 'Bonus', 'category.income'),
  ('category.income.investment', 'Investment Income', 'category.income'),
  ('category.income.refund', 'Refund', 'category.income'),
  ('category.income.other', 'Other Income', 'category.income'),
  ('category.food', 'Food & Dining', null),
  ('category.food.restaurants', 'Restaurants', 'category.food'),
  ('category.food.groceries', 'Groceries', 'category.food'),
  ('category.food.coffee', 'Coffee & Drinks', 'category.food'),
  ('category.food.delivery', 'Delivery & Takeout', 'category.food'),
  ('category.transportation', 'Transportation', null),
  ('category.transportation.fuel', 'Fuel', 'category.transportation'),
  (
    'category.transportation.public',
    'Public Transit',
    'category.transportation',
  ),
  (
    'category.transportation.rideshare',
    'Taxi & Rideshare',
    'category.transportation',
  ),
  ('category.transportation.parking', 'Parking', 'category.transportation'),
  (
    'category.transportation.maintenance',
    'Vehicle Maintenance',
    'category.transportation',
  ),
  ('category.housing', 'Housing', null),
  ('category.housing.rent_mortgage', 'Rent & Mortgage', 'category.housing'),
  ('category.housing.utilities', 'Utilities', 'category.housing'),
  ('category.housing.maintenance', 'Home Maintenance', 'category.housing'),
  ('category.shopping', 'Shopping', null),
  ('category.shopping.clothing', 'Clothing', 'category.shopping'),
  ('category.shopping.electronics', 'Electronics', 'category.shopping'),
  ('category.shopping.household', 'Household', 'category.shopping'),
  ('category.health', 'Health', null),
  ('category.health.medical', 'Medical', 'category.health'),
  ('category.health.pharmacy', 'Pharmacy', 'category.health'),
  ('category.health.fitness', 'Fitness', 'category.health'),
  ('category.entertainment', 'Entertainment', null),
  (
    'category.entertainment.streaming',
    'Streaming & Subscriptions',
    'category.entertainment',
  ),
  ('category.entertainment.events', 'Events', 'category.entertainment'),
  ('category.travel', 'Travel', null),
  ('category.travel.airfare', 'Airfare', 'category.travel'),
  ('category.travel.hotel', 'Hotels', 'category.travel'),
  ('category.travel.local', 'Local Transportation', 'category.travel'),
  ('category.education', 'Education', null),
  ('category.personal', 'Personal Care', null),
  ('category.gifts', 'Gifts & Donations', null),
  ('category.insurance', 'Insurance', null),
  ('category.taxes', 'Taxes', null),
  ('category.fees', 'Fees & Charges', null),
  ('category.transfer', 'Transfer', null),
  ('category.uncategorized', 'Uncategorized', null),
  ('category.other', 'Other', null),
];

const _tags = <(String, String)>[
  ('tag.business', 'Business'),
  ('tag.personal', 'Personal'),
  ('tag.reimbursable', 'Reimbursable'),
  ('tag.tax_related', 'Tax Related'),
  ('tag.travel', 'Travel'),
  ('tag.recurring', 'Recurring'),
  ('tag.subscription', 'Subscription'),
];

const _merchants = <(String, String, String, String?)>[
  ('merchant.safeway', 'Safeway', 'category.food', 'category.food.groceries'),
  ('merchant.costco', 'Costco', 'category.food', 'category.food.groceries'),
  ('merchant.walmart', 'Walmart', 'category.shopping', null),
  ('merchant.amazon', 'Amazon', 'category.shopping', null),
  ('merchant.starbucks', 'Starbucks', 'category.food', 'category.food.coffee'),
  ('merchant.target', 'Target', 'category.shopping', null),
  (
    'merchant.whole_foods',
    'Whole Foods',
    'category.food',
    'category.food.groceries',
  ),
  (
    'merchant.trader_joes',
    "Trader Joe's",
    'category.food',
    'category.food.groceries',
  ),
  (
    'merchant.walgreens',
    'Walgreens',
    'category.health',
    'category.health.pharmacy',
  ),
  ('merchant.cvs', 'CVS', 'category.health', 'category.health.pharmacy'),
  (
    'merchant.home_depot',
    'Home Depot',
    'category.housing',
    'category.housing.maintenance',
  ),
  (
    'merchant.shell',
    'Shell',
    'category.transportation',
    'category.transportation.fuel',
  ),
  (
    'merchant.chevron',
    'Chevron',
    'category.transportation',
    'category.transportation.fuel',
  ),
  (
    'merchant.uber',
    'Uber',
    'category.transportation',
    'category.transportation.rideshare',
  ),
  (
    'merchant.lyft',
    'Lyft',
    'category.transportation',
    'category.transportation.rideshare',
  ),
];
