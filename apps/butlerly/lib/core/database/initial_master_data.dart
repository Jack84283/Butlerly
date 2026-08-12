import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

/// Versioned, idempotent Finance V1 system data. IDs are semantic and are
/// deliberately independent of the English fallback display names.
InitialMasterData buildInitialMasterData() => InitialMasterData(
  merchants: const [],
  categories: _categories,
  tags: _tags,
);

Category _category(String id, String name, {String? parent}) => Category(
  id: CategoryId('system-category-$id'),
  name: name,
  origin: CategoryOrigin.system,
  parentId: parent == null ? null : CategoryId('system-category-$parent'),
);

final _categories = <Category>[
  _category('income', 'Income'),
  _category('salary', 'Salary', parent: 'income'),
  _category('bonus', 'Bonus', parent: 'income'),
  _category('investment-income', 'Investment income', parent: 'income'),
  _category('interest', 'Interest', parent: 'income'),
  _category('refund', 'Refund', parent: 'income'),
  _category('other-income', 'Other income', parent: 'income'),
  _category('food-dining', 'Food & dining'),
  _category('groceries', 'Groceries', parent: 'food-dining'),
  _category('restaurants', 'Restaurants', parent: 'food-dining'),
  _category('coffee-drinks', 'Coffee & drinks', parent: 'food-dining'),
  _category('delivery', 'Delivery', parent: 'food-dining'),
  _category('housing', 'Housing'),
  _category('rent-mortgage', 'Rent & mortgage', parent: 'housing'),
  _category('utilities', 'Utilities', parent: 'housing'),
  _category('home-maintenance', 'Home maintenance', parent: 'housing'),
  _category('furniture', 'Furniture', parent: 'housing'),
  _category('transportation', 'Transportation'),
  _category('gas-fuel', 'Gas & fuel', parent: 'transportation'),
  _category('parking', 'Parking', parent: 'transportation'),
  _category('public-transit', 'Public transit', parent: 'transportation'),
  _category('ride-share', 'Ride share', parent: 'transportation'),
  _category('auto-maintenance', 'Auto maintenance', parent: 'transportation'),
  _category('auto-insurance', 'Auto insurance', parent: 'transportation'),
  _category('shopping', 'Shopping'),
  _category('general-shopping', 'General shopping', parent: 'shopping'),
  _category('clothing', 'Clothing', parent: 'shopping'),
  _category('electronics', 'Electronics', parent: 'shopping'),
  _category('household', 'Household', parent: 'shopping'),
  _category('health', 'Health'),
  _category('medical', 'Medical', parent: 'health'),
  _category('dental', 'Dental', parent: 'health'),
  _category('pharmacy', 'Pharmacy', parent: 'health'),
  _category('fitness', 'Fitness', parent: 'health'),
  _category('entertainment', 'Entertainment'),
  _category('movies-events', 'Movies & events', parent: 'entertainment'),
  _category('games', 'Games', parent: 'entertainment'),
  _category('hobbies', 'Hobbies', parent: 'entertainment'),
  _category('streaming', 'Streaming', parent: 'entertainment'),
  _category('travel', 'Travel'),
  _category('flights', 'Flights', parent: 'travel'),
  _category('hotels', 'Hotels', parent: 'travel'),
  _category('car-rental', 'Car rental', parent: 'travel'),
  _category('travel-activities', 'Travel activities', parent: 'travel'),
  _category('personal', 'Personal'),
  _category('personal-care', 'Personal care', parent: 'personal'),
  _category('education', 'Education', parent: 'personal'),
  _category('gifts', 'Gifts', parent: 'personal'),
  _category('subscriptions', 'Subscriptions', parent: 'personal'),
  _category('financial', 'Financial'),
  _category('bank-fees', 'Bank fees', parent: 'financial'),
  _category('taxes', 'Taxes', parent: 'financial'),
  _category('insurance', 'Insurance', parent: 'financial'),
  _category('investment', 'Investment', parent: 'financial'),
  _category('loan-payment', 'Loan payment', parent: 'financial'),
  _category('family', 'Family'),
  _category('childcare', 'Childcare', parent: 'family'),
  _category('school', 'School', parent: 'family'),
  _category('family-support', 'Family support', parent: 'family'),
  _category('other', 'Other'),
  _category('charity-donations', 'Charity & donations', parent: 'other'),
  _category('uncategorized', 'Uncategorized', parent: 'other'),
  _category('other-item', 'Other', parent: 'other'),
];

final _tags = <Tag>[
  for (final value in [
    'business',
    'personal',
    'family',
    'travel',
    'vacation',
    'work',
    'reimbursable',
    'tax-deductible',
    'subscription',
    'recurring',
    'gift',
    'shared',
  ])
    Tag(id: TagId('system-tag-$value'), name: _title(value)),
];

String _title(String value) => value
    .split('-')
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
