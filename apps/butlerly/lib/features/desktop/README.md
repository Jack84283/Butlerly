# Butlerly desktop presentation

The desktop Home screen is implemented separately in `presentation/desktop_home_page.dart` and consumes the shared `FinanceServices.loadHomeOverview` use case. Mobile and tablet routes keep using `features/foundation/presentation/home_page.dart`.

The router selects desktop Home only for wide (`>= 1100px`) desktop or web windows. No desktop widget is imported by the mobile Home implementation. The current wide navigation shell remains shared while desktop screens are incrementally implemented.

Desktop UI changes must not alter mobile/device widgets, business rules, data access, or localization behavior. Subsequent desktop screens belong in this folder, and desktop-specific widget tests should verify responsive routing and real-data behavior.

The desktop route is activated only on supported wide desktop/web viewports; its feature boundary is intended to stay independent of device presentation components.

CI validation covers Dart formatting, static analysis, Flutter tests, web build, and platform smoke checks. New desktop changes should be pushed only with those checks reviewed.

The desktop Home implementation is reviewed independently from the mobile layout during PR validation.

## Shared desktop transaction table

Use `ButlerlyDesktopTransactionTable` from
`design_system/components/butlerly_desktop_transaction_table.dart` in desktop
Home, Transactions, Search, Review, or future detail surfaces. It renders the
same localized Date, Merchant, Category, Subcategory, Payment Source, and Amount
columns, payment-brand icons, and horizontal overflow below 760 px. The table
does **not** fetch transactions, decide filters/grouping, show a page header,
control expansion, or navigate itself.

Pass a prepared `List<TransactionDto>`, resolved `TransactionMasterData`,
optional `paymentSourceNames` / `missingCategoryLabel`, and a host-specific
`onTap(TransactionDto)`. Wrap it in the page's own outer and inner cards:
the reusable `ButlerlyDesktopInnerCard` provides Home-style padding/radius/
color when that design is desired. The Transactions page already consumes
the shared table; additional pages can adopt it without duplicating columns
or changing their filtering and navigation.
