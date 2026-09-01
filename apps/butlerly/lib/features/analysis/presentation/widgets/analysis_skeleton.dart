import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

class AnalysisSkeleton extends StatelessWidget {
  const AnalysisSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 48),
      for (var i = 0; i < 4; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: ButlerlySpacing.standard),
          child: ButlerlyCard(
            child: SizedBox(
              height: i == 0 ? 120 : 160,
              child: const LinearProgressIndicator(),
            ),
          ),
        ),
    ],
  );
}
