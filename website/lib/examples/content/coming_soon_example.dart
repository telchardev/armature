import 'package:flutter/material.dart';

import '../../docs/doc_typography.dart';

class ComingSoonExample extends StatelessWidget {
  const ComingSoonExample({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DocTitle(title),
        const DocParagraph(
          'This example is not built yet. Browse other examples using the '
          'sidebar.',
        ),
      ],
    );
  }
}
