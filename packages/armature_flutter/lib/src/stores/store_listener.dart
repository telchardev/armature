import 'package:armature/armature.dart' show Store;
import 'package:flutter/widgets.dart';

/// Predicate evaluated on every state transition; [listener] only
/// fires when it returns `true`. Useful for reacting to specific
/// edges instead of every change.
typedef StoreListenWhen<TState> = bool Function(TState prev, TState next);

/// Side-effect callback. Receives the [BuildContext] (for navigation
/// / dialogs / snackbars) and the new state value.
typedef StoreListenCallback<TState> =
    void Function(BuildContext context, TState state);

/// Side-effect host for a [Store] — fires [listener] on transitions
/// without rebuilding [child]. Use for navigation, dialogs,
/// analytics; pair with `StoreBuilder` / `StoreSelector` for
/// rendering.
///
/// Pass the [Store] via the [store] parameter — `S` is inferred from
/// `Store<S>`, no second generic to spell out:
///
/// ```dart
/// StoreListener(
///   store: context.store<AuthStore>(),
///   listenWhen: (prev, next) => !prev.isLoggedIn && next.isLoggedIn,
///   listener: (ctx, _) => Navigator.of(ctx).pushReplacementNamed('/home'),
///   child: const LoginForm(),
/// );
/// ```
class StoreListener<S> extends StatefulWidget {
  /// Store to observe. `S` is inferred from `Store<S>`.
  final Store<S> store;

  /// Filter predicate. `null` fires on every change; otherwise
  /// fires only when the predicate returns `true`.
  final StoreListenWhen<S>? listenWhen;

  /// Side-effect callback. Runs after the state has settled.
  final StoreListenCallback<S> listener;

  /// Subtree the listener wraps. Rebuilt only when its own
  /// dependencies change — never as a consequence of [listener]
  /// firing.
  final Widget child;

  const StoreListener({
    super.key,
    required this.store,
    required this.listener,
    required this.child,
    this.listenWhen,
  });

  @override
  State<StoreListener<S>> createState() => _StoreListenerState<S>();
}

class _StoreListenerState<S> extends State<StoreListener<S>> {
  late void Function() _disposer;

  void _subscribe() {
    _disposer = widget.store.subscribe((prev, next) {
      final guard = widget.listenWhen;
      if (guard != null && !guard(prev, next)) return;
      if (!mounted) return;
      widget.listener(context, next);
    });
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant StoreListener<S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      _disposer();
      _subscribe();
    }
  }

  @override
  void dispose() {
    _disposer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
