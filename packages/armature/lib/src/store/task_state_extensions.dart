import './task.dart'
    show TaskDone, TaskFailed, TaskIdle, TaskPending, TaskState;

/// Ergonomic pattern matching for [TaskState]. [when] requires all
/// four branches and is checked for exhaustiveness; [maybeWhen]
/// accepts a subset and falls through to [orElse]. Boolean and
/// nullable getters give one-line access to a specific branch.
///
/// ```dart
/// task.state.when(
///   idle:    ()         => const _IdlePlaceholder(),
///   pending: (params)   => CircularProgressIndicator.adaptive(),
///   done:    (result)   => ResultCard(result),
///   failed:  (error)    => ErrorBanner(message: error.toString()),
/// );
/// ```
extension TaskStateExtensions<TParams, TResult, TError>
    on TaskState<TParams, TResult, TError> {
  /// Exhaustive pattern match. All four branches required; returns
  /// the value produced by the matching branch.
  T when<T>({
    required T Function() idle,
    required T Function(TParams params) pending,
    required T Function(TResult result) done,
    required T Function(TError error) failed,
  }) {
    final self = this;
    if (self is TaskIdle<TParams, TResult, TError>) return idle();
    if (self is TaskPending<TParams, TResult, TError>) {
      return pending(self.params);
    }
    if (self is TaskDone<TParams, TResult, TError>) return done(self.result);
    if (self is TaskFailed<TParams, TResult, TError>) return failed(self.error);
    // Unreachable — [TaskState] is sealed; keeps return type non-nullable.
    throw StateError('Unreachable TaskState variant: $self');
  }

  /// Partial pattern match — supply only branches you care about;
  /// unmatched states route through [orElse], which receives the
  /// original state for inspection.
  T maybeWhen<T>({
    T Function()? idle,
    T Function(TParams params)? pending,
    T Function(TResult result)? done,
    T Function(TError error)? failed,
    required T Function(TaskState<TParams, TResult, TError> state) orElse,
  }) {
    final self = this;
    if (self is TaskIdle<TParams, TResult, TError>) {
      return idle != null ? idle() : orElse(self);
    }
    if (self is TaskPending<TParams, TResult, TError>) {
      return pending != null ? pending(self.params) : orElse(self);
    }
    if (self is TaskDone<TParams, TResult, TError>) {
      return done != null ? done(self.result) : orElse(self);
    }
    if (self is TaskFailed<TParams, TResult, TError>) {
      return failed != null ? failed(self.error) : orElse(self);
    }
    return orElse(self);
  }

  /// Whether the task has not started or has been reset back to idle
  /// (sticky state cleared).
  bool get isIdle => this is TaskIdle<TParams, TResult, TError>;

  /// Whether the task is currently executing.
  bool get isPending => this is TaskPending<TParams, TResult, TError>;

  /// Whether the most recent run completed successfully and the result
  /// is still observable (not yet reset).
  bool get isDone => this is TaskDone<TParams, TResult, TError>;

  /// Whether the most recent run threw a [TError]-matching exception
  /// and the failure is still observable.
  bool get isFailed => this is TaskFailed<TParams, TResult, TError>;

  /// In-flight call's params if [isPending], otherwise `null`.
  TParams? get paramsOrNull {
    final self = this;
    if (self is TaskPending<TParams, TResult, TError>) return self.params;
    return null;
  }

  /// Last successful result if [isDone], otherwise `null`.
  TResult? get resultOrNull {
    final self = this;
    if (self is TaskDone<TParams, TResult, TError>) return self.result;
    return null;
  }

  /// Last sticky error if [isFailed], otherwise `null`.
  TError? get errorOrNull {
    final self = this;
    if (self is TaskFailed<TParams, TResult, TError>) return self.error;
    return null;
  }
}
