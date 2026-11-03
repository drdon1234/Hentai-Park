import 'package:flutter/material.dart';

import '../kit/kit.dart';
import '../theme.dart';

class SelectableLogView extends StatelessWidget {
  const SelectableLogView({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => PageGutter(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: Gap.m),
      child: SelectableText(
        text,
        style: ParkText.mono(Theme.of(context).textTheme.bodySmall),
      ),
    ),
  );
}
