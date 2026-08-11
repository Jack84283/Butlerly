import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

InitialMasterData buildInitialMasterData() => InitialMasterData(
  merchants: [
    Merchant(id: MerchantId('system-merchant-grocery'), name: 'Grocery Store'),
    Merchant(id: MerchantId('system-merchant-coffee'), name: 'Coffee Shop'),
    Merchant(id: MerchantId('system-merchant-restaurant'), name: 'Restaurant'),
    Merchant(id: MerchantId('system-merchant-pharmacy'), name: 'Pharmacy'),
    Merchant(id: MerchantId('system-merchant-fuel'), name: 'Gas Station'),
    Merchant(id: MerchantId('system-merchant-online'), name: 'Online Store'),
  ],
  categories: [
    Category(
      id: CategoryId('system-category-groceries'),
      name: 'Groceries',
      origin: CategoryOrigin.system,
    ),
    Category(
      id: CategoryId('system-category-dining'),
      name: 'Dining',
      origin: CategoryOrigin.system,
    ),
    Category(
      id: CategoryId('system-category-transportation'),
      name: 'Transportation',
      origin: CategoryOrigin.system,
    ),
    Category(
      id: CategoryId('system-category-housing'),
      name: 'Housing',
      origin: CategoryOrigin.system,
    ),
    Category(
      id: CategoryId('system-category-utilities'),
      name: 'Utilities',
      origin: CategoryOrigin.system,
    ),
    Category(
      id: CategoryId('system-category-health'),
      name: 'Health',
      origin: CategoryOrigin.system,
    ),
    Category(
      id: CategoryId('system-category-shopping'),
      name: 'Shopping',
      origin: CategoryOrigin.system,
    ),
    Category(
      id: CategoryId('system-category-entertainment'),
      name: 'Entertainment',
      origin: CategoryOrigin.system,
    ),
    Category(
      id: CategoryId('system-category-income'),
      name: 'Income',
      origin: CategoryOrigin.system,
    ),
    Category(
      id: CategoryId('system-category-other'),
      name: 'Other',
      origin: CategoryOrigin.system,
    ),
  ],
  tags: [
    Tag(id: TagId('system-tag-essential'), name: 'Essential'),
    Tag(id: TagId('system-tag-recurring'), name: 'Recurring'),
    Tag(id: TagId('system-tag-personal'), name: 'Personal'),
    Tag(id: TagId('system-tag-work'), name: 'Work'),
    Tag(id: TagId('system-tag-travel'), name: 'Travel'),
    Tag(id: TagId('system-tag-reimbursable'), name: 'Reimbursable'),
    Tag(id: TagId('system-tag-tax-deductible'), name: 'Tax-deductible'),
  ],
);
