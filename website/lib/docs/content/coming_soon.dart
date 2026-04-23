import 'package:flutter/material.dart';

import '../doc_typography.dart';

class ComingSoonContent extends StatelessWidget {
  const ComingSoonContent({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DocTitle(title),
        const DocParagraph(
          'This page is not written yet. Check back soon, or browse other '
          'sections using the sidebar.',
        ),
      ],
    );
  }
}
