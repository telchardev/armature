import 'package:flutter/material.dart';

import '../examples/examples_shell.dart';

class ExamplesPage extends StatelessWidget {
  const ExamplesPage({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return ExamplesShell(slug: slug);
  }
}
