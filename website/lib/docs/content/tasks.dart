import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class TasksContent extends StatelessWidget {
  const TasksContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Tasks'),
        const DocParagraph(
          'A task wraps an async function with an observable lifecycle. '
          'Stores create them via createTask (typed params) or '
          'createVoidTask (no params). Each task picks a strategy that '
          'defines how concurrent calls combine, exposes its state as a '
          'reactive value, and cleans up automatically when the owning '
          'store is disposed.',
        ),
        const DocHeading('Four states'),
        const DocParagraph(
          'A task is always in exactly one of four states. Transitions are '
          'driven by call():',
        ),
        Text.rich(
          TextSpan(
            children: [
              inlineCode('TaskIdle', context),
              const TextSpan(
                text:
                    ' — initial state. The task has never run, or the '
                    'previous run threw an unexpected error.',
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            children: [
              inlineCode('TaskPending(params)', context),
              const TextSpan(
                text:
                    ' — the async function is running with the given '
                    'arguments. For debounced tasks, this also shows up '
                    'while the quiet timer is still waiting.',
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            children: [
              inlineCode('TaskDone(result)', context),
              const TextSpan(
                text:
                    ' — the most recent run succeeded. Sticky until the '
                    'next call() transitions to TaskPending again.',
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            children: [
              inlineCode('TaskFailed(error)', context),
              const TextSpan(
                text:
                    ' — the most recent run threw an error that matches '
                    'the TError type parameter. Also sticky until the '
                    'next call().',
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 24),
        const DocHeading('Observing state'),
        const DocParagraph(
          'task.state is a reactive snapshot of the lifecycle — reads '
          'inside a StateObserver or Reaction auto-subscribe, so '
          'transitions trigger rebuilds. A common pattern is rendering '
          'a button that reflects the current phase:',
        ),
        const CodeBlock(code: _observeSource, language: 'dart'),
        const DocParagraph(
          'Pattern matching on the sealed TaskState hierarchy makes the '
          'four cases exhaustive — the compiler catches a missing branch '
          'when you add new ones downstream.',
        ),
        const DocHeading('Error handling'),
        const DocParagraph(
          'The TError type parameter decides what lands in TaskFailed. '
          'Errors whose runtime type matches TError transition the state '
          'to TaskFailed(error); call() returns a Future that resolves '
          'normally with the thrown error surfaced to the caller as a '
          'rejection.',
        ),
        const DocParagraph(
          'Errors that do not match TError are treated as bugs — the '
          'state reverts to TaskIdle and the original exception rethrows '
          'from call() so the caller can surface it to the framework '
          'error handler. Pick a TError that covers the domain errors '
          'you care about; keep unexpected failures as regular '
          'exceptions.',
        ),
        const CodeBlock(code: _errorSource, language: 'dart'),
        const DocHeading('Picking TError'),
        const DocParagraph(
          'Four idioms cover most cases. The choice is architectural — '
          'it decides where each thrown value goes (sticky in UI vs '
          'propagated to the caller / error handler).',
        ),
        const DocBullet(
          'TError = Exception (default for API/IO) — Exception '
          'subclasses stick to TaskFailed; Errors (StateError, '
          'RangeError, ...) propagate, so a programming bug doesn\'t '
          'pollute the UI.',
        ),
        const DocBullet(
          'TError = a domain class (e.g. ApiError, OrderError) — only '
          'that family sticks. UI can pattern-match on specific cases.',
        ),
        const DocBullet(
          'TError = Never — nothing sticks. Use when the fn is not '
          'expected to throw in normal flow; any throw escalates.',
        ),
        const DocBullet(
          'TError = Object — everything sticks, including bugs. Last '
          'resort; loses the bug-vs-domain distinction.',
        ),
        const CodeBlock(code: _pickErrorSource, language: 'dart'),
        const DocHeading('Strategies at a glance'),
        const DocParagraph(
          'Every task declares a strategy at construction. The parameter '
          'is optional and defaults to queue; each strategy observes a '
          'different contract for concurrent calls:',
        ),
        const DocBullet(
          'queue (default) — FIFO; each call waits for the previous one '
          'to complete. Order-preserving, no lost calls.',
        ),
        const DocBullet(
          'once — runs exactly one time across the task\'s lifetime. '
          'Later calls return the cached result or the in-flight future.',
        ),
        const DocBullet(
          'latest — a new call supersedes an in-flight one. Only the '
          'latest run writes to state; all pending callers share its '
          'outcome. Superseded runs complete silently in the background.',
        ),
        const DocBullet(
          'debounce(d) — coalesces a burst into a single run at the end '
          'of the quiet window. State shows TaskPending with the most '
          'recent params throughout.',
        ),
        const DocBullet(
          'throttle(d, edge:) — one run per d window. leading fires '
          'immediately and cools down; trailing collects calls and '
          'fires once at the end of the window with the most recent '
          'params.',
        ),
        const SizedBox(height: 8),
        const DocParagraph(
          'The Stores page shows the syntax for each. A common rule of '
          'thumb: queue for mutating actions, latest for '
          'search-as-you-type, debounce for auto-save, once for lazy '
          'init, throttle for rate limits.',
        ),
        const DocHeading('Reset'),
        const DocParagraph(
          'task.reset() returns the state to TaskIdle from any sticky '
          'state, cancels coalesced callers (latest / debounce / '
          'throttle(trailing)) with TaskError, drops state writes from '
          'any in-flight run, and clears the once cache. Useful for '
          'retry buttons, dismissing toast-style results, or re-arming '
          'a once task after a transient failure.',
        ),
        const DocParagraph(
          'For "show the result for a moment, then come back to the '
          'idle button" UX, pass autoReset: duration at construction. '
          'A timer schedules the same transition automatically after '
          'TaskDone or TaskFailed and cancels itself if a new call() '
          'arrives mid-window.',
        ),
        const CodeBlock(code: _resetSource, language: 'dart'),
        const DocHeading('Disposal'),
        const DocParagraph(
          'Tasks do not need manual cleanup. Store.dispose cascades to '
          'every task created via createTask / createVoidTask: '
          'debounce/throttle timers cancel, coalesced callers reject '
          'with TaskError, and subsequent call() invocations throw '
          'TaskError immediately. In-flight direct calls still resolve '
          'normally — they own their completion future.',
        ),
        const DocHeading('What is next?'),
        const DocBullet(
          'Activation helpers — including whenStoreState, which '
          'subscribes to a store whose value is often driven by a task.',
        ),
        const DocBullet(
          'Error model — how TaskFailed relates to the framework\'s '
          'wider HandlerError / RenderError routing.',
        ),
      ],
    );
  }
}

const _observeSource = '''StateObserver(
  builder: (_) {
    final state = userStore.fetchUser.state;
    return switch (state) {
      TaskIdle() => FilledButton(
          onPressed: () => userStore.fetchUser(42),
          child: const Text('Load'),
        ),
      TaskPending() => const FilledButton(
          onPressed: null,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      TaskDone(:final result) => Text('Loaded \${result.name}'),
      TaskFailed(:final error) => Text('Failed: \$error'),
    };
  },
)''';

const _errorSource = '''class UserStore extends Store<UserState> {
  UserStore() : super(state: (name: null, age: 0));

  // TError = Exception — ApiException and friends land in TaskFailed.
  // Programming errors (StateError, RangeError, ...) rethrow to caller.
  late final fetchUser = createTask<int, User, Exception>(
    fn: (id) async {
      try {
        return await api.getUser(id);
      } on ApiException {
        rethrow;
      }
    },
    strategy: TaskStrategy.latest,
  );
}

// Call site:
try {
  final user = await store.fetchUser(42);
  // ... handle user
} on ApiException catch (e) {
  // Domain failure — also visible via store.fetchUser.state.
  showError(e);
}''';

const _resetSource = '''class UserStore extends Store<UserState> {
  UserStore() : super(state: const UserState());

  // After Done/Failed, return to TaskIdle 3s later so the button
  // re-appears without manual intervention.
  late final fetchUser = createTask<int, User, Exception>(
    fn: (id) => api.getUser(id),
    autoReset: const Duration(seconds: 3),
  );
}

// In the UI: a manual retry button rendered alongside the failure.
StateObserver(
  builder: (_) {
    final state = userStore.fetchUser.state;
    return switch (state) {
      TaskFailed(:final error) => Row(children: [
        Text('Failed: \$error'),
        TextButton(
          onPressed: userStore.fetchUser.reset,
          child: const Text('Retry'),
        ),
      ]),
      _ => const SizedBox.shrink(),
    };
  },
)''';

const _pickErrorSource = '''// Default for API/IO calls.
late final fetchUser = createTask<int, User, Exception>(
  fn: (id) async => api.getUser(id),
);

// Typed exception hierarchy — switch can match specific cases.
sealed class OrderError implements Exception {}
class OutOfStock extends OrderError {}
class PaymentDeclined extends OrderError {}

late final placeOrder = createTask<OrderRequest, OrderId, OrderError>(
  fn: (req) async => api.placeOrder(req),
);

// Strict — fn shouldn't fail in normal flow; any throw is a bug.
late final increment = createVoidTask<int, Never>(
  fn: () async => state.value + 1,
);

// In the UI:
StateObserver(
  builder: (_) => switch (orderStore.placeOrder.state) {
    TaskFailed(error: OutOfStock()) => const Text('Sold out'),
    TaskFailed(error: PaymentDeclined()) => const Text('Card declined'),
    _ => const SizedBox.shrink(),
  },
)''';
