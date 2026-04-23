import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class ArmatureAppContent extends StatelessWidget {
  const ArmatureAppContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('ArmatureApp'),
        const DocParagraph(
          'ArmatureApp is the Flutter bootstrap for an Armature runtime. '
          'You pass it the list of features plus a root widget; the '
          'widget builds the container, resolves the dependency graph, '
          'activates every feature, and hands control back to Flutter.',
        ),
        const DocHeading('Minimum usage'),
        const DocParagraph(
          'Drop ArmatureApp at the top of main() in place of a direct '
          'runApp call with your root widget:',
        ),
        const CodeBlock(code: _minimumSource, language: 'dart'),
        const DocParagraph(
          'Two required fields: features lists every feature in the '
          'container, and child is the widget rendered once the '
          'container is ready. The rest is optional.',
        ),
        const DocHeading('Container options'),
        const DocParagraph(
          'containerOptions customises runtime behaviour. The two fields '
          'you will actually tune are errorHandler and '
          'maxResolveConcurrency.',
        ),
        const CodeBlock(code: _optionsSource, language: 'dart'),
        const DocParagraph(
          'errorHandler is the sink for every recoverable runtime error: '
          'onStart throws, activation setup throws, port misuse, slot '
          'build crashes, listener exceptions. Each callback gets '
          'attribution (the feature name or a framework sentinel like '
          '"<container>"), the typed error, and a metadata map with '
          'extra context. Use it to feed your crash reporter — the '
          'framework guarantees one bad handler never blocks other '
          'errors from being processed.',
        ),
        const DocParagraph(
          'maxResolveConcurrency caps how many features can run their '
          'onStart in parallel. null means unbounded, which is usually '
          'fine; lower it if you have expensive startup work sharing a '
          'bottleneck (a single database, a rate-limited API).',
        ),
        const DocHeading('Logger'),
        const DocParagraph(
          'The logger is separate from errorHandler — it carries '
          'framework-internal diagnostics (activation traces, port '
          'applies, cascade steps). PrintLogger ships with the core '
          'package and routes to the Dart console with a minimum level '
          'filter:',
        ),
        const CodeBlock(code: _loggerSource, language: 'dart'),
        const DocParagraph(
          'Implement the Logger interface to adapt to a structured '
          'logger, a file sink, or your observability stack. User-'
          'actionable failures never ride through the logger — they '
          'always reach errorHandler.',
        ),
        const DocHeading('Where it sits'),
        const DocParagraph(
          'ArmatureApp is a regular widget. Typically it wraps your '
          'MaterialApp or top-level shell, because the container must '
          'be alive before any feature\'s UI mounts. The child widget '
          'renders after the graph is wired — by the time its build '
          'runs, stores exist, onStart has fired for everything active.',
        ),
        const DocParagraph(
          'Pair it with FeatureGraphOverlay from armature_flutter in '
          'debug builds to see the live graph on top of your app:',
        ),
        const CodeBlock(code: _overlaySource, language: 'dart'),
        const DocHeading('What is next?'),
        const DocBullet(
          'createFeatureRoot — the helper that mounts a feature as the '
          'top-level child of ArmatureApp.',
        ),
        const DocBullet(
          'Slot widgets — the providers that render inside the '
          'feature root.',
        ),
        const DocBullet(
          'MultiPortBuilder — reads several ports of different kinds '
          'in one flat builder.',
        ),
      ],
    );
  }
}

const _minimumSource =
    '''import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/widgets.dart';

void main() {
  runApp(
    ArmatureApp(
      features: [
        layoutFeature,
        counterFeature,
        authFeature,
      ],
      child: const AppShell(),
    ),
  );
}''';

const _optionsSource = '''ArmatureApp(
  features: [...],
  containerOptions: ContainerOptions(
    maxResolveConcurrency: 8,
    errorHandler: ({required source, required error, required meta}) {
      if (error is HandlerError) {
        crashReporter.record(source, error, meta);
      }
      debugPrint('[\$source] \$error');
    },
  ),
  child: const AppShell(),
)''';

const _loggerSource = '''ArmatureApp(
  features: [...],
  logger: PrintLogger(minLevel: LogLevel.info),
  child: const AppShell(),
)''';

const _overlaySource = '''ArmatureApp(
  features: [...],
  child: FeatureGraphOverlay(
    enabled: kDebugMode,
    child: const AppShell(),
  ),
)''';
