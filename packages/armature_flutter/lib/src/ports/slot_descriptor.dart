import 'package:flutter/widgets.dart' show Widget;

/// Builder that produces the widget shown while a slot is in its
/// loading state (owning feature `.pending`). Invoked on every build
/// where the loader path is active; typical implementations return a
/// `const` placeholder.
typedef SlotLoaderBuilder = Widget Function();

/// Base descriptor for slot ports. Carries the widget to render when a
/// handler wins selection, plus an optional [loader] that overrides the
/// renderer-wide fallback while the feature is still `.pending`.
///
/// Subclasses add selection metadata — [SingleSlotDescriptor.priority]
/// for single-slot competition, [MultiSlotDescriptor.order] for multi-
/// slot sort order.
class SlotDescriptor {
  /// Widget rendered once the owning feature is `.active` and this
  /// handler wins selection.
  final Widget widget;

  /// Optional loader shown while the owning feature is `.pending`.
  /// When `null`, the renderer's global `loaderBuilder` is used (or an
  /// empty space if that's also absent).
  final SlotLoaderBuilder? loader;

  SlotDescriptor({required this.widget, this.loader});
}
