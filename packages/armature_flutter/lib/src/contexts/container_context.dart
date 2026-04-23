import 'package:armature/armature.dart' show AppContainer;
import 'package:flutter/widgets.dart'
    show FlutterError, InheritedWidget, BuildContext;

/// Inherited provider for the active [AppContainer]. Installed by the
/// default renderer (via `renderRoot`) at the root of the armature
/// widget subtree — descendants reach it through
/// [ContainerContext.of].
///
/// Typical consumers are framework-internal (port providers, slot
/// widgets), but application code may also read the container when it
/// needs to [AppContainer.observe] a port or inspect
/// [AppContainer.statusOf] imperatively.
class ContainerContext extends InheritedWidget {
  /// Returns the nearest enclosing [ContainerContext].
  ///
  /// Throws [FlutterError] when no [ContainerContext] is found in
  /// [context]'s ancestor chain — that almost always means the caller
  /// forgot to wrap the widget tree with `ArmatureApp` (or the `render`
  /// function returned from `bootstrap()`).
  static ContainerContext of(BuildContext context) {
    final result = context
        .dependOnInheritedWidgetOfExactType<ContainerContext>();
    if (result == null) {
      throw FlutterError(
        'ContainerContext.of() called with a context that does not contain '
        'a ContainerContext.\nMake sure your widget tree is wrapped with '
        '`ArmatureApp` or the render function returned from `bootstrap()`.',
      );
    }
    return result;
  }

  final AppContainer container;

  const ContainerContext({
    super.key,
    required this.container,
    required super.child,
  });

  @override
  bool updateShouldNotify(ContainerContext oldWidget) =>
      container != oldWidget.container;
}
