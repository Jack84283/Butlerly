import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

/// The MD-0001 V1 system catalog. Labels are persisted separately as
/// translations; these domain records contain stable semantic IDs.
InitialMasterData buildInitialMasterData() => InitialMasterData(
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
