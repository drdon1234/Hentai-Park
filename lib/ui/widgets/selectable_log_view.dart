import 'package:flutter/material.dart';

import '../theme.dart';

class SelectableLogView extends StatelessWidget {
  const SelectableLogView({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(12),
    child: SelectableText(
      text,
      style: ParkText.mono(Theme.of(context).textTheme.bodySmall),
    ),
  );
}
