import 'package:flutter/material.dart';

import '../theme.dart';

class SelectableLogView extends StatelessWidget {
  const SelectableLogView({super.key, required this.logs});
  final List<String> logs;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(12),
    child: SelectableText(
      logs.join('\n\n'),
      style: ParkText.mono(Theme.of(context).textTheme.bodySmall),
    ),
  );
}
