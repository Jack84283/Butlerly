from pathlib import Path

home = Path('apps/butlerly/lib/features/foundation/presentation/home_page.dart')
text = home.read_text()
start_marker = "            SliverToBoxAdapter(\n              child: ColoredBox(\n                key: const ValueKey('home-page-content-surface'),"
start = text.index(start_marker)
end_marker = "            ),\n          ],\n        ),\n      ),\n    );"
end = text.index(end_marker, start)
replacement = '''            SliverLayoutBuilder(
              builder: (context, constraints) {
                final contentMaxWidth = ButlerlyLayout.contentMaxWidth(
                  MediaQuery.sizeOf(context),
                );
                final surfaceMaxWidth =
                    contentMaxWidth + ButlerlySize.phoneGutter * 2;
                final extraWidth =
                    constraints.crossAxisExtent - surfaceMaxWidth;
                final horizontalInset = extraWidth > 0 ? extraWidth / 2 : 0.0;
                return SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalInset),
                  sliver: SliverToBoxAdapter(
                    child: ColoredBox(
                      key: const ValueKey('home-page-content-surface'),
                      color: context.colors.background,
                      child: Padding(
                        key: const ValueKey('home-page-content-padding'),
                        padding: const EdgeInsets.fromLTRB(
                          ButlerlySize.phoneGutter,
                          ButlerlySpacing.small,
                          ButlerlySize.phoneGutter,
                          ButlerlySpacing.large,
                        ),
                        child: SizedBox(
                          key: const ValueKey('home-page-content'),
                          width: double.infinity,
                          child: FutureBuilder<_HomeData>(
                            key: const ValueKey('home-body-data'),
                            future: future,
                            builder: (context, snapshot) {
                              final data =
                                  snapshot.data ??
                                  _HomeData.empty(
                                    _now,
                                    selectedMonth: _selectedMonth,
                                  );
                              final loading =
                                  snapshot.connectionState !=
                                  ConnectionState.done;
                              return _homeContent(context, data, loading);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
'''
text = text[:start] + replacement + text[end + len("            ),\n"):]
home.write_text(text)
