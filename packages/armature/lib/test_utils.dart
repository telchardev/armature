/// Test utilities for code built on top of `armature`.
///
/// Usage from a test file:
///
/// ```dart
/// import 'package:armature/test_utils.dart';
///
/// void main() {
///   test('my feature works', () async {
///     final container = await startedContainer(features: [myFeature]);
///     final store = myFeature.storeOf<MyStore>(container);
///     // ...
///   });
/// }
/// ```
///
/// This sub-library pulls in `package:test` — import it only from test
/// code. Production code must not reach for these helpers.
library;

import 'package:test/test.dart' show addTearDown;

import 'armature.dart';

/// Error handler that swallows every error. Use in tests where the
/// recoverable-error path isn't the subject under test.
void noopErrorHandler({
  required String source,
  required ArmatureError error,
  required Map<String, String> meta,
}) {}

/// Convenience builder for [ContainerOptions] with [noopErrorHandler]
/// and no logger.
ContainerOptions silentOptions({int? maxResolveConcurrency}) {
  return ContainerOptions(
    errorHandler: noopErrorHandler,
    maxResolveConcurrency: maxResolveConcurrency,
  );
}

/// Paired result from [collectErrors]: a [ContainerOptions] whose
/// `errorHandler` appends every error into [errors].
typedef ErrorCollector = ({
  ContainerOptions options,
  List<ArmatureError> errors,
});

/// Creates a pre-wired error collector.
///
/// ```dart
/// final collector = collectErrors();
/// final container = await startedContainer(
///   features: [feature],
///   options: collector.options,
/// );
/// // ... run scenario ...
/// expect(collector.errors, hasLength(1));
/// ```
ErrorCollector collectErrors({int? maxResolveConcurrency}) {
  final errors = <ArmatureError>[];
  final options = ContainerOptions(
    errorHandler: ({required error, required source, required meta}) {
      errors.add(error);
    },
    maxResolveConcurrency: maxResolveConcurrency,
  );
  return (options: options, errors: errors);
}

/// Spins up an [AppContainer], registers disposal via `addTearDown`,
/// and awaits `start()`. Returns the ready-to-use container.
///
/// Replaces the common three-liner:
/// ```dart
/// final container = AppContainer(features: [...]);
/// addTearDown(container.dispose);
/// await container.start();
/// ```
Future<AppContainer> startedContainer({
  required List<AnyFeature> features,
  ContainerOptions? options,
  Logger? logger,
}) async {
  final container = AppContainer(
    features: features,
    options: options ?? silentOptions(),
    logger: logger,
  );
  addTearDown(container.dispose);
  await container.start();
  return container;
}

/// Test-scoped extensions on [Feature]. Only available when
/// `package:armature/test_utils.dart` is imported.
extension FeatureTestExtensions<
  TStores extends Object?,
  TExports extends Object?,
  TPorts extends Object?
>
    on Feature<TStores, TExports, TPorts> {
  /// Typed lookup of a [Store] owned by this feature in [container].
  ///
  /// Feature runtime state (including the scope API where stores live)
  /// is per-container — you must tell the helper which container's
  /// runtime to look in.
  T storeOf<T extends Store>(AppContainer container) {
    return container.runtimeOf(this).scopeApi.store<T>();
  }
}
