from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"{path}: expected exactly one match, found {count}: {old[:100]!r}"
        )
    file.write_text(text.replace(old, new, 1))


tx = "apps/butlerly/lib/features/foundation/presentation/transactions_page.dart"
replace_once(
    tx,
    "import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';\n",
    "import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';\n"
    "import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';\n",
)
replace_once(
    tx,
    "      body: FutureBuilder<_EditorMasterData>(\n",
    "      body: ButlerlyResponsiveBody(\n"
    "        contentKey: const ValueKey('transaction-editor-content'),\n"
    "        child: FutureBuilder<_EditorMasterData>(\n",
)
replace_once(
    tx,
    "        },\n      ),\n    );\n  }\n\n  Future<void> _createMerchant",
    "        },\n      ),\n      ),\n    );\n  }\n\n  Future<void> _createMerchant",
)
replace_once(
    tx,
    "      body: ListView(\n"
    "        padding: const EdgeInsets.all(ButlerlySpacing.pagePadding),\n"
    "        children: [\n",
    "      body: ButlerlyResponsiveBody(\n"
    "        contentKey: const ValueKey('transaction-detail-content'),\n"
    "        child: ListView(\n"
    "          padding: const EdgeInsets.all(ButlerlySpacing.pagePadding),\n"
    "          children: [\n",
)
replace_once(
    tx,
    "        ],\n      ),\n    ),\n  );\n}\n\nclass _EvidenceSection",
    "        ],\n      ),\n      ),\n    ),\n  );\n}\n\nclass _EvidenceSection",
)

receipt = "apps/butlerly/lib/features/foundation/presentation/receipt_capture_page.dart"
replace_once(
    receipt,
    "import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';\n",
    "import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';\n"
    "import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';\n",
)
replace_once(
    receipt,
    "      body: SafeArea(\n        child: ListView(\n",
    "      body: SafeArea(\n"
    "        child: ButlerlyResponsiveBody(\n"
    "          contentKey: const ValueKey('receipt-capture-content'),\n"
    "          child: ListView(\n",
)
replace_once(
    receipt,
    "          ],\n        ),\n      ),\n    );\n  }\n}",
    "          ],\n        ),\n        ),\n      ),\n    );\n  }\n}",
)

statement = "apps/butlerly/lib/features/foundation/presentation/statement_capture_page.dart"
replace_once(
    statement,
    "import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';\n",
    "import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';\n"
    "import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';\n",
)
replace_once(
    statement,
    "    body: _busy\n",
    "    body: ButlerlyResponsiveBody(\n"
    "      contentKey: const ValueKey('statement-capture-content'),\n"
    "      child: _busy\n",
)
replace_once(
    statement,
    "          ),\n  );\n}\n\nclass _StatementReviewPage",
    "          ),\n    ),\n  );\n}\n\nclass _StatementReviewPage",
)
replace_once(
    statement,
    "    body: ListView(\n"
    "      padding: const EdgeInsets.all(ButlerlySpacing.pagePadding),\n"
    "      children: [\n",
    "    body: ButlerlyResponsiveBody(\n"
    "      contentKey: const ValueKey('statement-review-content'),\n"
    "      child: ListView(\n"
    "        padding: const EdgeInsets.all(ButlerlySpacing.pagePadding),\n"
    "        children: [\n",
)
replace_once(
    statement,
    "      ],\n    ),\n  );\n}\n\nclass _ProgressSummary",
    "      ],\n    ),\n    ),\n  );\n}\n\nclass _ProgressSummary",
)

test = "apps/butlerly/test/app/responsive_shell_test.dart"
replace_once(
    test,
    "import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';\n",
    "import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';\n"
    "import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';\n",
)
marker = "  for (final size in const [Size(744, 1133), Size(1133, 744)]) {\n"
addition = """  testWidgets(
    'focused responsive body keeps AppBar full-width and caps phone content',
    (tester) async {
      await _pumpResponsiveBodyAt(tester, const Size(932, 430));

      expect(tester.getSize(find.byType(AppBar)).width, 932);
      expect(
        tester.getSize(find.byKey(const ValueKey('focused-page-content'))).width,
        ButlerlySize.phoneContentMaxWidth,
      );
    },
  );

  testWidgets('focused responsive body keeps the tablet readable width', (
    tester,
  ) async {
    await _pumpResponsiveBodyAt(tester, const Size(1133, 744));

    expect(tester.getSize(find.byType(AppBar)).width, 1133);
    expect(
      tester.getSize(find.byKey(const ValueKey('focused-page-content'))).width,
      ButlerlySize.pageContentMaxWidth,
    );
  });

"""
replace_once(test, marker, addition + marker)
with Path(test).open("a") as file:
    file.write(
        """

Future<void> _pumpResponsiveBodyAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Focused page')),
        body: const ButlerlyResponsiveBody(
          contentKey: ValueKey('focused-page-content'),
          child: SizedBox.expand(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
"""
    )
