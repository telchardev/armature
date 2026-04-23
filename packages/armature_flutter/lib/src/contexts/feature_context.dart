import 'package:armature/armature.dart' show Feature;
import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, StringProperty;
import 'package:flutter/widgets.dart'
    show FlutterError, InheritedWidget, BuildContext;

/// Inherited provider for the [Feature] whose slot is currently
/// rendering a subtree. Installed by each slot widget (SingleSlot,
/// MultiSlot, …) so descendants know which feature they belong to.
///
/// Application code rarely reads this directly — prefer
/// [StoreContext.of] for typed store access. Reach for
/// [FeatureContext.of] when you need the raw [Feature] reference
/// (e.g. to call `observe` / `apply` against a port manually).
class FeatureContext extends InheritedWidget {
  /// Returns the nearest enclosing [FeatureContext].
  ///
  /// Throws [FlutterError] when called from outside any slot — the
  /// widget must be mounted under one of the slot widgets installed by
  /// the framework (SingleSlot, MultiSlot, FeatureRoot, …).
  static FeatureContext of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<FeatureContext>();
    if (result == null) {
      throw FlutterError(
        'FeatureContext.of() called with a context that does not contain '
        'a FeatureContext.\nThis widget must be a descendant of a slot widget.',
      );
    }
    return result;
  }

  final Feature feature;

  const FeatureContext({
    super.key,
    required this.feature,
    required super.child,
  });

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('featureName', feature.name));
  }

  @override
  bool updateShouldNotify(FeatureContext oldWidget) =>
      feature != oldWidget.feature;
}
