import 'package:armature/armature.dart' show Store;
import 'package:flutter/widgets.dart' show BuildContext, FlutterError;

import 'feature_context.dart' show FeatureContext;

/// Namespace helper for typed [Store] lookup from the enclosing slot's
/// feature.
///
/// Walks up the widget tree for the nearest [FeatureContext], then asks
/// that feature's scope API for a store of type `T`. Fails loudly if
/// called outside a slot, or if the feature doesn't own a store of the
/// requested type (via [StoreLookupError]).
///
/// ```dart
/// class _NoteTile extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     final notes = StoreContext.of<NoteStore>(context);
///     return Text(notes.state.title);
///   }
/// }
/// ```
class StoreContext {
  StoreContext._();

  /// Returns the [Store] of type `T` owned by the slot's enclosing
  /// feature. Throws [FlutterError] if no [FeatureContext] ancestor is
  /// present; throws [StoreLookupError] if the feature doesn't own a
  /// store of type `T`.
  static T of<T extends Store>(BuildContext context) {
    final featureContext = context
        .dependOnInheritedWidgetOfExactType<FeatureContext>();
    if (featureContext == null) {
      throw FlutterError(
        'StoreContext.of<$T>() called with a context that does not '
        'contain a FeatureContext.\nThis widget must be a descendant of a slot widget.',
      );
    }
    return featureContext.feature.internal.scopeApi.store<T>();
  }
}

/// Shortcut extension for store lookup from [BuildContext].
///
/// `context.store<T>()` is the inverse of the Provider-style naming
/// (`context.read<T>()`) and matches the imperative semantics: it
/// does **not** subscribe the enclosing widget to rebuilds when the
/// store's state changes. Wrap the read in a [StateObserver] / a
/// `StoreBuilder<T>` (or call it from inside one) when reactivity is
/// required; use it directly inside event handlers (`onTap`, …) where
/// only a one-shot read is needed.
extension BuildContextStoreExt on BuildContext {
  /// Equivalent to `StoreContext.of<T>(this)`.
  T store<T extends Store>() => StoreContext.of<T>(this);
}
