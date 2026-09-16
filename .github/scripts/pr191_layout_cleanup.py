from pathlib import Path
import re

ROOT = Path('.')


def read(path: str) -> str:
    return (ROOT / path).read_text()


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text)


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected exactly one match, found {count}: {old[:80]!r}')
    write(path, text.replace(old, new, 1))


TOKENS = 'apps/butlerly/lib/design_system/tokens/butlerly_tokens.dart'
replace_once(
    TOKENS,
    '''  /// Window class is based on the shortest logical side so rotating a phone\n  /// never turns its primary navigation into tablet navigation.\n  static bool isTabletViewport(Size viewport) =>\n      viewport.shortestSide >= phoneBreakpoint;\n\n  /// Keeps phone page content readable in landscape while allowing tablets to\n  /// use the established wider readable column.\n  static double pageContentMaxWidthFor(Size viewport) =>\n      isTabletViewport(viewport) ? pageContentMaxWidth : phoneContentMaxWidth;\n''',
    '',
)
replace_once(
    TOKENS,
    '''}\n\nabstract final class ButlerlyMotion {\n''',
    '''}\n\nenum ButlerlyNavigationMode { phone, rail, extendedRail }\n\n/// Semantic responsive-layout policy. Feature pages consume this policy rather\n/// than embedding breakpoints or readable-width numbers of their own.\nabstract final class ButlerlyLayout {\n  static ButlerlyNavigationMode navigationMode(Size viewport) {\n    if (viewport.width >= ButlerlySize.desktopBreakpoint) {\n      return ButlerlyNavigationMode.extendedRail;\n    }\n    if (viewport.shortestSide >= ButlerlySize.phoneBreakpoint) {\n      return ButlerlyNavigationMode.rail;\n    }\n    return ButlerlyNavigationMode.phone;\n  }\n\n  static double contentMaxWidth(Size viewport) =>\n      navigationMode(viewport) == ButlerlyNavigationMode.phone\n      ? ButlerlySize.phoneContentMaxWidth\n      : ButlerlySize.pageContentMaxWidth;\n}\n\nabstract final class ButlerlyMotion {\n''',
)

for path in [
    'apps/butlerly/lib/design_system/components/butlerly_components.dart',
    'apps/butlerly/lib/design_system/components/butlerly_responsive_body.dart',
    'apps/butlerly/lib/features/foundation/presentation/home_page.dart',
]:
    text = read(path)
    old = 'ButlerlySize.pageContentMaxWidthFor('
    if old not in text:
        raise RuntimeError(f'{path}: expected responsive width call')
    write(path, text.replace(old, 'ButlerlyLayout.contentMaxWidth('))

SHELL = 'apps/butlerly/lib/app/shell/adaptive_shell.dart'
shell = read(SHELL)
old_build = '''  @override\n  Widget build(BuildContext context) {\n    final secondaryRouteVisible = widget.visibilityController\n        .secondaryRouteVisibleFor(navigationShell.currentIndex);\n    final viewport = MediaQuery.sizeOf(context);\n    final tabletViewport = ButlerlySize.isTabletViewport(viewport);\n    return PopScope(\n      canPop: secondaryRouteVisible || navigationShell.currentIndex != 1,\n      onPopInvokedWithResult: _handleSystemBack,\n      child: LayoutBuilder(\n        builder: (context, constraints) {\n          if (secondaryRouteVisible) {\n            return Scaffold(body: navigationShell);\n          }\n\n          if (!tabletViewport) {\n            return Scaffold(\n              body: SafeArea(bottom: false, child: _phoneBody()),\n              bottomNavigationBar: _phoneNavigation(context),\n            );\n          }\n\n          final extended =\n              constraints.maxWidth >= ButlerlySize.desktopBreakpoint;\n          final destinations = _destinations(context);\n          final selectedVisualIndex = _visualBranchIndexes.indexOf(\n            navigationShell.currentIndex,\n          );\n          return Scaffold(\n            body: SafeArea(\n              child: Row(\n                children: [\n                  NavigationRail(\n                    extended: extended,\n                    selectedIndex: selectedVisualIndex,\n                    onDestinationSelected: (visualIndex) => _selectDestination(\n                      _visualBranchIndexes[visualIndex],\n                    ),\n                    leading: Padding(\n                      padding: const EdgeInsets.symmetric(\n                        vertical: ButlerlySpacing.section,\n                      ),\n                      child: extended\n                          ? Text(\n                              context.l10n.text('appName'),\n                              style: Theme.of(context).textTheme.headlineMedium\n                                  ?.copyWith(color: context.colors.primaryText),\n                            )\n                          : Icon(\n                              Icons.circle,\n                              size: 14,\n                              color: context.colors.interactive,\n                            ),\n                    ),\n                    destinations: [\n                      for (final branchIndex in _visualBranchIndexes)\n                        NavigationRailDestination(\n                          icon: destinations[branchIndex]!.icon,\n                          selectedIcon:\n                              destinations[branchIndex]!.selectedIcon,\n                          label: Text(destinations[branchIndex]!.label),\n                        ),\n                    ],\n                  ),\n                  VerticalDivider(width: 1, color: context.colors.cardDivider),\n                  Expanded(child: navigationShell),\n                ],\n              ),\n            ),\n          );\n        },\n      ),\n    );\n  }\n'''
new_build = '''  @override\n  Widget build(BuildContext context) {\n    final secondaryRouteVisible = widget.visibilityController\n        .secondaryRouteVisibleFor(navigationShell.currentIndex);\n    final navigationMode = ButlerlyLayout.navigationMode(\n      MediaQuery.sizeOf(context),\n    );\n\n    late final Widget shell;\n    if (secondaryRouteVisible) {\n      shell = Scaffold(body: navigationShell);\n    } else if (navigationMode == ButlerlyNavigationMode.phone) {\n      shell = Scaffold(\n        body: SafeArea(bottom: false, child: _phoneBody()),\n        bottomNavigationBar: _phoneNavigation(context),\n      );\n    } else {\n      final extended = navigationMode == ButlerlyNavigationMode.extendedRail;\n      final destinations = _destinations(context);\n      final selectedVisualIndex = _visualBranchIndexes.indexOf(\n        navigationShell.currentIndex,\n      );\n      shell = Scaffold(\n        body: SafeArea(\n          child: Row(\n            children: [\n              NavigationRail(\n                extended: extended,\n                selectedIndex: selectedVisualIndex,\n                onDestinationSelected: (visualIndex) => _selectDestination(\n                  _visualBranchIndexes[visualIndex],\n                ),\n                leading: Padding(\n                  padding: const EdgeInsets.symmetric(\n                    vertical: ButlerlySpacing.section,\n                  ),\n                  child: extended\n                      ? Text(\n                          context.l10n.text('appName'),\n                          style: Theme.of(context).textTheme.headlineMedium\n                              ?.copyWith(color: context.colors.primaryText),\n                        )\n                      : Icon(\n                          Icons.circle,\n                          size: 14,\n                          color: context.colors.interactive,\n                        ),\n                ),\n                destinations: [\n                  for (final branchIndex in _visualBranchIndexes)\n                    NavigationRailDestination(\n                      icon: destinations[branchIndex]!.icon,\n                      selectedIcon: destinations[branchIndex]!.selectedIcon,\n                      label: Text(destinations[branchIndex]!.label),\n                    ),\n                ],\n              ),\n              VerticalDivider(width: 1, color: context.colors.cardDivider),\n              Expanded(child: navigationShell),\n            ],\n          ),\n        ),\n      );\n    }\n\n    return PopScope(\n      canPop: secondaryRouteVisible || navigationShell.currentIndex != 1,\n      onPopInvokedWithResult: _handleSystemBack,\n      child: shell,\n    );\n  }\n'''
if shell.count(old_build) != 1:
    raise RuntimeError('adaptive_shell.dart: build method shape changed')
write(SHELL, shell.replace(old_build, new_build, 1))

LEGAL = 'apps/butlerly/lib/features/foundation/presentation/legal_licenses_page.dart'
replace_once(
    LEGAL,
    "import 'package:butlerly/design_system/components/butlerly_components.dart';\n",
    "import 'package:butlerly/design_system/components/butlerly_components.dart';\nimport 'package:butlerly/design_system/components/butlerly_responsive_body.dart';\n",
)
legal = read(LEGAL)
old_legal_body = '''    body: FutureBuilder<String>(\n      future: rootBundle.loadString(document.assetPath),\n      builder: (context, snapshot) {\n        if (snapshot.hasError) {\n          return Center(\n            child: Padding(\n              padding: const EdgeInsets.all(ButlerlySpacing.section),\n              child: Text(context.l10n.text('legalDocumentLoadError')),\n            ),\n          );\n        }\n        if (!snapshot.hasData) {\n          return const ButlerlyLoadingState();\n        }\n        return SafeArea(\n          child: SingleChildScrollView(\n            padding: const EdgeInsets.symmetric(\n              horizontal: ButlerlySize.phoneGutter,\n              vertical: ButlerlySpacing.section,\n            ),\n            child: SelectableText(snapshot.requireData),\n          ),\n        );\n      },\n    ),\n'''
new_legal_body = '''    body: SafeArea(\n      child: ButlerlyResponsiveBody(\n        contentKey: const ValueKey('legal-document-content'),\n        child: FutureBuilder<String>(\n          future: rootBundle.loadString(document.assetPath),\n          builder: (context, snapshot) {\n            if (snapshot.hasError) {\n              return Center(\n                child: Padding(\n                  padding: const EdgeInsets.all(ButlerlySpacing.section),\n                  child: Text(context.l10n.text('legalDocumentLoadError')),\n                ),\n              );\n            }\n            if (!snapshot.hasData) {\n              return const ButlerlyLoadingState();\n            }\n            return SingleChildScrollView(\n              padding: const EdgeInsets.symmetric(\n                horizontal: ButlerlySize.phoneGutter,\n                vertical: ButlerlySpacing.section,\n              ),\n              child: SelectableText(snapshot.requireData),\n            );\n          },\n        ),\n      ),\n    ),\n'''
if legal.count(old_legal_body) != 1:
    raise RuntimeError('legal_licenses_page.dart: LegalDocumentPage body shape changed')
write(LEGAL, legal.replace(old_legal_body, new_legal_body, 1))

CONTEXTUAL = 'apps/butlerly/lib/features/foundation/presentation/contextual_pages.dart'
contextual = read(CONTEXTUAL)
old_welcome = '''    body: SafeArea(\n      child: ListView(\n        padding: const EdgeInsets.all(ButlerlySpacing.section),\n'''
new_welcome = '''    body: SafeArea(\n      child: ButlerlyResponsiveBody(\n        contentKey: const ValueKey('welcome-content'),\n        child: ListView(\n          padding: const EdgeInsets.all(ButlerlySpacing.section),\n'''
if contextual.count(old_welcome) != 1:
    raise RuntimeError('contextual_pages.dart: Welcome body shape changed')
contextual = contextual.replace(old_welcome, new_welcome, 1)
welcome_end = '''          FilledButton(\n            onPressed: () => context.go('/'),\n            child: Text(context.l10n.text('getStarted')),\n          ),\n        ],\n      ),\n    ),\n  );\n}\n\nclass _WelcomeValue'''
welcome_end_new = '''          FilledButton(\n            onPressed: () => context.go('/'),\n            child: Text(context.l10n.text('getStarted')),\n          ),\n        ],\n        ),\n      ),\n    ),\n  );\n}\n\nclass _WelcomeValue'''
if contextual.count(welcome_end) != 1:
    raise RuntimeError('contextual_pages.dart: Welcome closing shape changed')
contextual = contextual.replace(welcome_end, welcome_end_new, 1)
old_receipt_detail = '''    body: ListView(\n      padding: const EdgeInsets.all(ButlerlySpacing.standard),\n      children: [\n        Text(\n          context.l10n.text('sourceData'),\n          style: Theme.of(context).textTheme.titleLarge,\n        ),\n        const SizedBox(height: ButlerlySpacing.small),\n        ButlerlySourcePreview(\n          title: name,\n          subtitle: context.l10n.text('receiptPreview'),\n        ),\n        ButlerlySectionHeader(title: context.l10n.text('extractedSourceText')),\n        ButlerlyCard(\n          child: Text(context.l10n.text('extractedTextUnavailable')),\n        ),\n      ],\n    ),\n'''
new_receipt_detail = '''    body: ButlerlyResponsiveBody(\n      contentKey: const ValueKey('receipt-detail-content'),\n      child: ListView(\n        padding: const EdgeInsets.all(ButlerlySpacing.standard),\n        children: [\n          Text(\n            context.l10n.text('sourceData'),\n            style: Theme.of(context).textTheme.titleLarge,\n          ),\n          const SizedBox(height: ButlerlySpacing.small),\n          ButlerlySourcePreview(\n            title: name,\n            subtitle: context.l10n.text('receiptPreview'),\n          ),\n          ButlerlySectionHeader(title: context.l10n.text('extractedSourceText')),\n          ButlerlyCard(\n            child: Text(context.l10n.text('extractedTextUnavailable')),\n          ),\n        ],\n      ),\n    ),\n'''
if contextual.count(old_receipt_detail) != 1:
    raise RuntimeError('contextual_pages.dart: ReceiptDetail body shape changed')
contextual = contextual.replace(old_receipt_detail, new_receipt_detail, 1)
write(CONTEXTUAL, contextual)

TEST = 'apps/butlerly/test/app/responsive_shell_test.dart'
test = read(TEST)
replace_import = "import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';\n"
if test.count(replace_import) != 1:
    raise RuntimeError('responsive_shell_test.dart: tokens import not unique')
test = test.replace(
    replace_import,
    replace_import + "import 'package:butlerly/features/foundation/presentation/legal_licenses_page.dart';\n",
    1,
)
old_policy_test = '''  test('window class and readable width use the shortest logical side', () {\n    expect(ButlerlySize.isTabletViewport(const Size(390, 844)), isFalse);\n    expect(ButlerlySize.isTabletViewport(const Size(932, 430)), isFalse);\n    expect(ButlerlySize.isTabletViewport(const Size(744, 1133)), isTrue);\n    expect(ButlerlySize.isTabletViewport(const Size(1133, 744)), isTrue);\n    expect(\n      ButlerlySize.pageContentMaxWidthFor(const Size(932, 430)),\n      ButlerlySize.phoneContentMaxWidth,\n    );\n    expect(\n      ButlerlySize.pageContentMaxWidthFor(const Size(1133, 744)),\n      ButlerlySize.pageContentMaxWidth,\n    );\n  });\n'''
new_policy_test = '''  test('layout policy distinguishes phone, tablet, and desktop windows', () {\n    expect(\n      ButlerlyLayout.navigationMode(const Size(390, 844)),\n      ButlerlyNavigationMode.phone,\n    );\n    expect(\n      ButlerlyLayout.navigationMode(const Size(932, 430)),\n      ButlerlyNavigationMode.phone,\n    );\n    expect(\n      ButlerlyLayout.navigationMode(const Size(744, 1133)),\n      ButlerlyNavigationMode.rail,\n    );\n    expect(\n      ButlerlyLayout.navigationMode(const Size(1133, 744)),\n      ButlerlyNavigationMode.extendedRail,\n    );\n    expect(\n      ButlerlyLayout.navigationMode(const Size(1200, 500)),\n      ButlerlyNavigationMode.extendedRail,\n    );\n    expect(\n      ButlerlyLayout.contentMaxWidth(const Size(932, 430)),\n      ButlerlySize.phoneContentMaxWidth,\n    );\n    expect(\n      ButlerlyLayout.contentMaxWidth(const Size(1200, 500)),\n      ButlerlySize.pageContentMaxWidth,\n    );\n  });\n'''
if test.count(old_policy_test) != 1:
    raise RuntimeError('responsive_shell_test.dart: policy test shape changed')
test = test.replace(old_policy_test, new_policy_test, 1)
anchor = '''  testWidgets('iPad mini landscape keeps the 760 point readable body', (\n    tester,\n  ) async {\n    await _pumpAt(tester, const Size(1133, 744));\n\n    expect(\n      tester.getSize(find.byKey(const ValueKey('home-page-content'))).width,\n      ButlerlySize.pageContentMaxWidth,\n    );\n  });\n'''
addition = anchor + '''\n  testWidgets('shallow desktop window keeps extended NavigationRail', (\n    tester,\n  ) async {\n    await _pumpAt(tester, const Size(1200, 500));\n\n    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));\n    expect(rail.extended, isTrue);\n    expect(\n      find.byKey(const ValueKey('primary-phone-navigation')),\n      findsNothing,\n    );\n    expect(\n      tester.getSize(find.byKey(const ValueKey('home-page-content'))).width,\n      ButlerlySize.pageContentMaxWidth,\n    );\n  });\n\n  testWidgets(\n    'landscape Legal document keeps full-width AppBar and capped content',\n    (tester) async {\n      tester.view.physicalSize = const Size(932, 430);\n      tester.view.devicePixelRatio = 1;\n      addTearDown(tester.view.resetPhysicalSize);\n      addTearDown(tester.view.resetDevicePixelRatio);\n\n      await tester.pumpWidget(\n        const MaterialApp(\n          home: LegalDocumentPage(\n            document: LegalDocument(\n              'termsOfUse',\n              'assets/legal/terms_of_use.txt',\n            ),\n          ),\n        ),\n      );\n      await tester.pump();\n\n      expect(tester.getSize(find.byType(AppBar)).width, 932);\n      expect(\n        tester.getSize(find.byKey(const ValueKey('legal-document-content'))).width,\n        ButlerlySize.phoneContentMaxWidth,\n      );\n    },\n  );\n'''
if test.count(anchor) != 1:
    raise RuntimeError('responsive_shell_test.dart: iPad landscape anchor changed')
test = test.replace(anchor, addition, 1)
write(TEST, test)

print('PR #191 responsive layout cleanup applied.')
