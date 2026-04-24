/// Flutter test utilities for code built on top of `armature_flutter`.
///
/// Usage from a widget test file:
///
/// ```dart
/// import 'package:armature_flutter/test_utils.dart';
///
/// void main() {
///   testWidgets('renders title from slot', (tester) async {
///     final container = await startedContainer(features: [root, child]);
///     initTestRenderer(container);
///     await pumpFeature(
///       tester,
///       container: container,
///       feature: root,
///       child: SingleSlotProvider(
///         slot: titleSlot,
///         data: null,
///         builder: (w, _) => w ?? const Text('default'),
///       ),
///     );
///     expect(find.text('Hello'), findsOneWidget);
///   });
/// }
/// ```
///
/// This sub-library pulls in `flutter_test` — import it only from test
/// code. Production code must not reach for these helpers.
library;

import 'package:armature/armature.dart' show AnyFeature, AppContainer;
import 'package:flutter/widgets.dart'
    show Directionality, TextDirection, Widget;
import 'package:flutter_test/flutter_test.dart' show WidgetTester;

import 'armature_flutter.dart';
import 'src/contexts/feature_context.dart' show FeatureContext;
import 'src/renderer/flutter_renderer.dart' show FlutterRenderer;
import 'src/renderer/renderer_context.dart' show ContainerRenderer;

export 'package:armature/test_utils.dart';

/// Installs a [FlutterRenderer] on [container] so slot widgets can
/// render. The renderer is per-container — call this on each container
/// built by a test that isn't going through [ArmatureApp] (which sets
/// its own renderer during `initState`).
void initTestRenderer(
  AppContainer container, {
  FlutterRendererOptions? options,
}) {
  container.setRenderer(
    FlutterRenderer(options: options ?? FlutterRendererOptions()),
  );
}

/// Wraps [child] in `Directionality → ContainerContext → FeatureContext`,
/// the minimal ambient tree required by the armature Flutter providers.
Widget wrapForTesting({
  required AppContainer container,
  required AnyFeature feature,
  required Widget child,
  TextDirection textDirection = TextDirection.ltr,
}) {
  return Directionality(
    textDirection: textDirection,
    child: ContainerContext(
      container: container,
      child: FeatureContext(feature: feature, child: child),
    ),
  );
}

/// Shortcut for `tester.pumpWidget(wrapForTesting(...))`.
///
/// Ensures [container] has a renderer installed (via [initTestRenderer])
/// before pumping, so slot widgets can render without a separate setup
/// call in every test.
Future<void> pumpFeature(
  WidgetTester tester, {
  required AppContainer container,
  required AnyFeature feature,
  required Widget child,
  TextDirection textDirection = TextDirection.ltr,
}) {
  if (container.maybeRenderer == null) {
    initTestRenderer(container);
  }
  return tester.pumpWidget(
    wrapForTesting(
      container: container,
      feature: feature,
      child: child,
      textDirection: textDirection,
    ),
  );
}
