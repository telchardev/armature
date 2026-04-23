part of './core.dart';

/// Base type for all errors raised by the reactive core. Sealed so
/// callers can `catch on ReactiveError` and cover every framework
/// failure mode exhaustively.
sealed class ReactiveError implements Exception {
  /// Human-readable diagnostic — never part of a stable contract.
  final String message;

  const ReactiveError(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown from [Context.endBatch] when the reactive graph fails to
/// reach a stable state within the configured [ReactiveConfig.maxIterations].
///
/// Typically signals a cycle: reaction A invalidates reaction B,
/// which re-invalidates A, repeating without convergence. The
/// [reactionName] points at the reaction that was still pending on the
/// final iteration.
final class ReactiveCycleError extends ReactiveError {
  /// Name of a reaction that was still pending when the convergence
  /// budget ran out. Best-effort — other reactions in the same batch
  /// may have been part of the cycle too.
  final String reactionName;

  /// Iteration limit that was exceeded.
  final int maxIterations;

  const ReactiveCycleError({
    required this.reactionName,
    required this.maxIterations,
  }) : super(
         'Reactive graph did not converge after $maxIterations iterations. '
         'Likely a cycle involving reaction "$reactionName".',
       );
}
