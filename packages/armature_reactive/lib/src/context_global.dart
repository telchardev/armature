part of './core.dart';

/// Shared reactive context used by [Atom] and [Reaction] when no explicit
/// context is passed. Suitable for typical single-container apps.
///
/// For multi-container scenarios that need isolated reactive state
/// (e.g. parallel test environments), construct a dedicated [Context] via
/// [createContext] and pass it to each [Atom] and [Reaction] manually.
///
/// The per-isolate state (batch counter, pending reactions, currently
/// tracked reaction) can be cleared with [Context.reset] — useful in test
/// `tearDown` when the global context is shared across cases.
final Context globalContext = createContext(config: ReactiveConfig.defaults);

/// Creates a new isolated reactive [Context]. Use this when you need
/// reactive state that doesn't share batching or pending-reaction bookkeeping
/// with the default [globalContext].
Context createContext({required ReactiveConfig config}) =>
    Context(config: config);
