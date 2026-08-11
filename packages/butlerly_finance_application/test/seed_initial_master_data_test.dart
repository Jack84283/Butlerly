import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test(
    'seeds missing master data without replacing existing records',
    () async {
      final merchants = _Merchants();
      final categories = _Categories();
      final tags = _Tags();
      await merchants.save(
        Merchant(id: MerchantId('merchant-grocery'), name: 'My Grocery'),
      );

      final result = await SeedInitialMasterData(merchants, categories, tags)(
        InitialMasterData(
          merchants: [
            Merchant(id: MerchantId('merchant-grocery'), name: 'Grocery Store'),
            Merchant(id: MerchantId('merchant-coffee'), name: 'Coffee Shop'),
          ],
          categories: [
            Category(
              id: CategoryId('category-dining'),
              name: 'Dining',
              origin: CategoryOrigin.system,
            ),
          ],
          tags: [Tag(id: TagId('tag-recurring'), name: 'Recurring')],
        ),
      );

      expect(result, isA<ApplicationSuccess<void>>());
      expect((await merchants.listAll()).length, 2);
      expect(
        (await merchants.findById(MerchantId('merchant-grocery')))!.name,
        'My Grocery',
      );
      expect((await categories.listAll()).single.name, 'Dining');
      expect((await tags.listAll()).single.name, 'Recurring');
    },
  );
}

final class _Merchants implements MerchantRepository {
  final values = <String, Merchant>{};

  @override
  Future<Merchant?> findById(MerchantId id) async => values[id.value];

  @override
  Future<List<Merchant>> listAll() async => values.values.toList();

  @override
  Future<void> save(Merchant merchant) async {
    values[merchant.id.value] = merchant;
  }
}

final class _Categories implements CategoryRepository {
  final values = <String, Category>{};

  @override
  Future<Category?> findById(CategoryId id) async => values[id.value];

  @override
  Future<List<Category>> listAll() async => values.values.toList();

  @override
  Future<void> save(Category category) async {
    values[category.id.value] = category;
  }
}

final class _Tags implements TagRepository {
  final values = <String, Tag>{};

  @override
  Future<Tag?> findById(TagId id) async => values[id.value];

  @override
  Future<List<Tag>> listAll() async => values.values.toList();

  @override
  Future<void> save(Tag tag) async {
    values[tag.id.value] = tag;
  }
}
