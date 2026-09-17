from pathlib import Path

policy = Path('apps/butlerly/test/design_system/content_surface_policy_test.dart')
text = policy.read_text()
old = "children: [SizedBox(key: ValueKey('surface-policy-child'))],"
new = "children: [SizedBox(key: ValueKey('surface-policy-child'), height: 20)],"
if old not in text:
    raise SystemExit('surface policy child fixture not found')
policy.write_text(text.replace(old, new, 1))

components = Path('apps/butlerly/test/design_system/butlerly_components_test.dart')
text = components.read_text()
old = '''        expect(
          find.byWidgetPredicate(
            (widget) => widget is Material && widget.color == colors.background,
          ),
          findsWidgets,
        );'''
new = '''        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedSliver &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).color == colors.background,
          ),
          findsOneWidget,
        );'''
if old not in text:
    raise SystemExit('generated semantic background expectation not found')
components.write_text(text.replace(old, new, 1))
