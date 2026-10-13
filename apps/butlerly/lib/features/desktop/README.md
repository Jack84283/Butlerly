# Butlerly desktop presentation

The desktop Home screen is implemented separately in `presentation/desktop_home_page.dart` and consumes the shared `FinanceServices.loadHomeOverview` use case. Mobile and tablet routes keep using `features/foundation/presentation/home_page.dart`.

The router selects desktop Home only for wide (`>= 1100px`) desktop or web windows. No desktop widget is imported by the mobile Home implementation. The current wide navigation shell remains shared while desktop screens are incrementally implemented.

Desktop UI changes must not alter mobile/device widgets, business rules, data access, or localization behavior. Subsequent desktop screens belong in this folder, and desktop-specific widget tests should verify responsive routing and real-data behavior.

The desktop route is activated only on supported wide desktop/web viewports; its feature boundary is intended to stay independent of device presentation components.

CI validation covers Dart formatting, static analysis, Flutter tests, web build, and platform smoke checks. New desktop changes should be pushed only with those checks reviewed.
