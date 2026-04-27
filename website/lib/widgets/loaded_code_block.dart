import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'code_block.dart';

/// CodeBlock that loads its source text from an asset path at runtime.
///
/// Used by example pages to keep a single source of truth — the asset
/// path is the actual `.dart` file that runs in the embedded preview,
/// so the displayed source can never drift from the running code.
class LoadedCodeBlock extends StatelessWidget {
  const LoadedCodeBlock({
    super.key,
    required this.path,
    this.language = 'dart',
  });

  final String path;
  final String language;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: rootBundle.loadString(path),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Failed to load source: ${snapshot.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }
        return CodeBlock(code: snapshot.data ?? '', language: language);
      },
    );
  }
}
