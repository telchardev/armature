import 'package:flutter/material.dart';

import '../docs/docs_shell.dart';

class DocsPage extends StatelessWidget {
  const DocsPage({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return DocsShell(slug: slug);
  }
}
