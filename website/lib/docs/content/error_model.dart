import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class ErrorModelContent extends StatelessWidget {
  const ErrorModelContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Error model'),
        const DocParagraph(
          'Every error the framework produces extends ArmatureError — a '
          'sealed base class that splits into four behavioural groups. '
          'Catch the whole family with a single on ArmatureError clause; '
          'the concrete type tells you which group you are dealing with '
          'and what to do about it.',
        ),
        const DocHeading('Four groups'),
        const DocBullet(
          'Lifecycle errors — you called the container in the wrong '
          'state. Synchronous throws; fix the call site.',
        ),
        const DocBullet(
          'Programming errors — your API usage is a bug. Synchronous '
          'throws; fix the code that produced them.',
        ),
        const DocBullet(
          'Resolution failures — the dependency graph or a stores '
          'factory could not come up. Thrown out of AppContainer.start().',
        ),
        const DocBullet(
          'Recoverable runtime errors — reported to your errorHandler '
          'and never thrown. The container keeps running with a fallback.',
        ),
        const DocHeading('The hierarchy'),
        const DocParagraph('Concrete types, grouped by behaviour:'),
        const CodeBlock(code: _hierarchySource, language: 'dart'),
        const DocParagraph(
          'Every ArmatureError carries an optional stackTrace — captured '
          'at the throw site or explicitly threaded through wrap(). '
          'Consumers read error.stackTrace without extra plumbing.',
        ),
        const DocHeading('errorHandler — the single sink'),
        const DocParagraph(
          'Recoverable runtime errors flow through ContainerOptions.errorHandler. '
          'The handler signature is:',
        ),
        const CodeBlock(code: _handlerSignatureSource, language: 'dart'),
        const DocBullet(
          'source — the feature name, or a framework sentinel ("<container>", '
          '"<events>", "<feature-teardown>") for errors that are not '
          'attributable to a single feature.',
        ),
        const DocBullet(
          'error — a typed ArmatureError subclass. Pattern-match to decide '
          'what to do.',
        ),
        const DocBullet(
          'meta — free-form string map with extra breadcrumbs (event kind, '
          'port name, activation phase).',
        ),
        const DocParagraph(
          'Your handler never blocks: if it throws, the container logs '
          'the throw and processes the next error normally. One bad '
          'handler never compounds damage.',
        ),
        const DocHeading('What lands where'),
        const DocParagraph('Only three error types reach errorHandler:'),
        const DocBullet(
          'HandlerError — an activation setup, onStart, or port handler '
          '(usePipe / useBehavior / useSingleSlot / useMultiSlot) threw. '
          'For onStart throws, the feature settles in disabled and '
          'required descendants cascade closed.',
        ),
        const DocBullet(
          'ListenerError — a listener registered via '
          'AppContainer.onFeatureStatusChanged or onPortChanged threw. '
          'The listener is otherwise isolated; siblings still fire.',
        ),
        const DocBullet(
          'RenderError — a slot widget threw during build, or '
          'MultiPortBuilder reader caught an exception while reading a '
          'port. The slot renders its fallback; errorHandler sees the '
          'wrapped error.',
        ),
        const DocParagraph('Typical production wiring:'),
        const CodeBlock(code: _productionHandlerSource, language: 'dart'),
        const DocHeading('What is thrown synchronously'),
        const DocParagraph(
          'Programming errors surface as throws so they cannot be '
          'ignored:',
        ),
        const DocBullet(
          'ContainerError — wrong container state (apply() before '
          'start(), double start() without an intervening stop(), etc.).',
        ),
        const DocBullet(
          'ContainerUsageError — caller misuse (stop() from inside a '
          'feature callback, reaching into orchestrator internals).',
        ),
        const DocBullet(
          'FeatureConfigurationError — feature misconfigured '
          '(activation() / onStart() twice, duplicate Store type in one '
          'feature).',
        ),
        const DocBullet(
          'TaskError — a Task was called after the owning Store was '
          'disposed.',
        ),
        const DocBullet(
          'PortError (at registration time) — handler registered from a '
          'feature that did not declare the owner as a parent, or twice '
          'from the same feature.',
        ),
        const DocBullet(
          'StoreLookupError — StoreContext.of<T>(context) asked for a '
          'store the enclosing feature does not own.',
        ),
        const DocHeading('Graceful degradation on apply'),
        const DocParagraph(
          'PortError is different at apply time. Instead of throwing '
          'inside port.apply(), the framework returns the error to '
          'AppContainer.apply(), routes it through errorHandler, and '
          'falls back to the initialValue. This keeps one misconfigured '
          'port from crashing an entire render tree.',
        ),
        const DocParagraph(
          'Pattern-match to distinguish "I need to fix this" from "I '
          'need to alert someone":',
        ),
        const CodeBlock(code: _patternMatchSource, language: 'dart'),
        const DocHeading('What is next?'),
        const DocBullet('ArmatureApp — where errorHandler is installed.'),
        const DocBullet(
          'createFeatureRoot — the mounting point whose build is the '
          'source of most RenderErrors.',
        ),
        const DocBullet(
          'Slot widgets — the providers whose handler throws become '
          'RenderError reports.',
        ),
      ],
    );
  }
}

const _hierarchySource = '''ArmatureError (sealed)
├── ContainerError                      // wrong container lifecycle state
├── ContainerUsageError                 // calling convention violated
├── FeatureConfigurationError           // feature declared incorrectly
├── FeatureResolutionError              // start() failed (graph / factory)
│   └── reason: FeatureResolutionReason
│       (missingParent, notDeclaredParent, cycle,
│        storesFactoryFailed, storesAlreadyInitialised, other)
├── PortError                           // port misuse (throws at register,
│                                       //  returned at apply)
├── StoreLookupError                    // StoreContext.of<T> missed
├── TaskError                           // task called after dispose
├── HandlerError       ──► errorHandler // handler / onStart threw
├── ListenerError      ──► errorHandler // event listener threw
└── RenderError        ──► errorHandler // slot build threw''';

const _handlerSignatureSource = '''typedef ContainerErrorHandler =
    void Function({
      required String source,
      required ArmatureError error,
      required Map<String, String> meta,
    });''';

const _productionHandlerSource = '''ArmatureApp(
  features: [...],
  containerOptions: ContainerOptions(
    errorHandler: ({required source, required error, required meta}) {
      // Framework-internal route: always log for diagnostics.
      logger.error('[armature:\$source] \$error', error: error);

      // Domain route: send user-actionable failures to crash reporter.
      if (error is HandlerError || error is RenderError) {
        Sentry.captureException(error, stackTrace: error.stackTrace);
      }
    },
  ),
  child: const AppShell(),
)''';

const _patternMatchSource = '''void handleArmatureError(ArmatureError e) {
  switch (e) {
    case HandlerError(:final featureName):
      // onStart / port handler threw — feature is now disabled.
      showBanner('Feature "\$featureName" is unavailable.');

    case RenderError(:final featureName):
      // Slot build threw — fallback rendered; log for follow-up.
      reportRenderBug(featureName, e);

    case ListenerError(:final source):
      // User-installed listener misbehaved; framework moved on.
      analytics.logWarning('listener.\$source', e.message);

    case ContainerError() || ContainerUsageError():
      // Programming error — crash loud in debug, recover in release.
      assert(false, e.toString());

    case FeatureResolutionError(:final reason):
      // start() already rethrew this; handler hit because of a listener
      // or inspection path. Just log.
      logger.warn('resolution \${reason.name}: \${e.message}');

    default:
      logger.warn(e.toString());
  }
}''';
