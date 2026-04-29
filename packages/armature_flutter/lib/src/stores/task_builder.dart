import 'package:armature/armature.dart'
    show Task, TaskState, TaskStateExtensions;
import 'package:flutter/widgets.dart';

import './state_observer.dart' show StateObserver;

/// Branch builder for [TaskBuilder] when the task is idle.
typedef TaskIdleBuilder = Widget Function(BuildContext context);

/// Branch builder for [TaskBuilder] while a run is in flight;
/// receives the in-flight params.
typedef TaskPendingBuilder<TParams> =
    Widget Function(BuildContext context, TParams params);

/// Branch builder for [TaskBuilder] after a successful run; receives
/// the result payload.
typedef TaskDoneBuilder<TResult> =
    Widget Function(BuildContext context, TResult result);

/// Branch builder for [TaskBuilder] after a sticky failure; receives
/// the [TError] payload.
typedef TaskFailedBuilder<TError> =
    Widget Function(BuildContext context, TError error);

/// Reactive widget that renders a [Task]'s lifecycle through four
/// branch builders. All generics infer from the [task] argument:
///
/// ```dart
/// // store.fetchUser: Task<int, User, ApiException>
/// TaskBuilder(
///   task: store.fetchUser,
///   idle:    (_)         => const _Placeholder(),
///   pending: (_, userId) => CircularProgressIndicator.adaptive(),
///   done:    (_, user)   => UserCard(user),
///   failed:  (_, e)      => ErrorBanner(message: e.message),
/// )
/// ```
class TaskBuilder<TParams, TResult, TError> extends StatelessWidget {
  /// Task whose state drives the builder.
  final Task<TParams, TResult, TError> task;

  /// Branch shown for [TaskIdle].
  final TaskIdleBuilder idle;

  /// Branch shown for [TaskPending]. Receives the in-flight params.
  final TaskPendingBuilder<TParams> pending;

  /// Branch shown for [TaskDone]. Receives the result.
  final TaskDoneBuilder<TResult> done;

  /// Branch shown for [TaskFailed]. Receives the sticky error.
  final TaskFailedBuilder<TError> failed;

  const TaskBuilder({
    super.key,
    required this.task,
    required this.idle,
    required this.pending,
    required this.done,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    return StateObserver(
      builder: (context) => task.state.when(
        idle: () => idle(context),
        pending: (params) => pending(context, params),
        done: (result) => done(context, result),
        failed: (error) => failed(context, error),
      ),
    );
  }
}
