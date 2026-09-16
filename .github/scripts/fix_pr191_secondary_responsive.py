from pathlib import Path

ROOT = Path('.')


def ensure_import(text: str, anchor: str, addition: str) -> str:
    if addition in text:
        return text
    if anchor not in text:
        raise SystemExit(f'missing import anchor: {anchor}')
    return text.replace(anchor, anchor + addition, 1)


def wrap_body(text: str, class_name: str, content_key: str) -> str:
    class_marker = f'class {class_name}'
    start = text.find(class_marker)
    if start < 0:
        raise SystemExit(f'missing class: {class_name}')
    next_class = text.find('\nclass ', start + len(class_marker))
    end = len(text) if next_class < 0 else next_class
    segment = text[start:end]
    if f"ValueKey('{content_key}')" in segment:
        return text

    body_marker = '    body: '
    body_rel = segment.find(body_marker)
    if body_rel < 0:
        raise SystemExit(f'missing body in {class_name}')
    body_start = start + body_rel
    expr_start = body_start + len(body_marker)
    close = text.find('\n    ),', expr_start, end)
    if close < 0:
        raise SystemExit(f'could not locate body close in {class_name}')
    expr = text[expr_start:close + len('\n    )')]
    replacement = (
        f"    body: ButlerlyResponsiveBody(\n"
        f"      contentKey: const ValueKey('{content_key}'),\n"
        f"      child: {expr},\n"
        f"    )"
    )
    return text[:body_start] + replacement + text[close + len('\n    )'):]


contextual_path = ROOT / 'apps/butlerly/lib/features/foundation/presentation/contextual_pages.dart'
contextual = contextual_path.read_text()
contextual = ensure_import(
    contextual,
    "import 'package:butlerly/design_system/components/butlerly_components.dart';\n",
    "import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';\n",
)
contextual = wrap_body(contextual, '_ImportExportPageState', 'import-export-content')
contextual = wrap_body(contextual, 'NotificationsPage', 'notifications-content')
contextual = wrap_body(contextual, 'AssistantUnavailablePage', 'assistant-unavailable-content')
contextual_path.write_text(contextual)

privacy_path = ROOT / 'apps/butlerly/lib/features/foundation/presentation/privacy_data_page.dart'
privacy = privacy_path.read_text()
privacy = ensure_import(
    privacy,
    "import 'package:butlerly/design_system/components/butlerly_components.dart';\n",
    "import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';\n",
)
privacy = wrap_body(privacy, '_PrivacyDataPageState', 'privacy-data-content')
privacy_path.write_text(privacy)

test_path = ROOT / 'apps/butlerly/test/app/responsive_shell_test.dart'
tests = test_path.read_text()
if "landscape Import/Export keeps a full-width header and caps body at 600" not in tests:
    marker = "  testWidgets(\n    'focused responsive body keeps AppBar full-width and caps phone content',"
    if marker not in tests:
        raise SystemExit('missing responsive test insertion marker')
    test = """  testWidgets(\n    'landscape Import/Export keeps a full-width header and caps body at 600',\n    (tester) async {\n      await _pumpAt(tester, const Size(932, 430));\n\n      appRouter.go('/import-export');\n      await tester.pumpAndSettle();\n\n      expect(find.byType(NavigationRail), findsNothing);\n      expect(\n        find.byKey(const ValueKey('primary-phone-navigation')),\n        findsNothing,\n      );\n      expect(tester.getSize(find.byType(AppBar)).width, 932);\n      expect(\n        tester\n            .getSize(find.byKey(const ValueKey('import-export-content')))\n            .width,\n        ButlerlySize.phoneContentMaxWidth,\n      );\n    },\n  );\n\n"""
    tests = tests.replace(marker, test + marker, 1)
test_path.write_text(tests)

# Assert the requested production paths are all covered before committing.
for path, key in [
    (contextual_path, 'import-export-content'),
    (contextual_path, 'notifications-content'),
    (contextual_path, 'assistant-unavailable-content'),
    (privacy_path, 'privacy-data-content'),
]:
    if f"ValueKey('{key}')" not in path.read_text():
        raise SystemExit(f'missing expected responsive wrapper: {key}')
