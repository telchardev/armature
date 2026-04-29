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
          'TError = a domain class (e.g. PersistError, NotFound) — only '
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
          'A common rule of thumb: queue for mutating actions (add note), '
          'latest for search-as-you-type, debounce for auto-save (persist), '
          'once for lazy init (load), throttle for rate limits.',
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
        const DocHeading('Pattern matching helpers'),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text:
                    'For ergonomic branching without a full sealed switch, '
                    'use the ',
              ),
              inlineCode('TaskStateExtensions', context),
              const TextSpan(
                text:
                    ' that ship with armature: .when (exhaustive, '
                    'compile-checked) and .maybeWhen (partial with orElse). '
                    'Boolean and nullable getters give one-line access to a '
                    'specific branch.',
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 16),
        const CodeBlock(code: _whenSource, language: 'dart'),
        const DocHeading('TaskBuilder widget'),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'For Flutter, '),
              inlineCode('TaskBuilder', context),
              const TextSpan(
                text:
                    ' wraps the same .when matching in a reactive widget. '
                    'All four branches are required, generics infer from '
                    'the task argument, and rebuilds happen on every state '
                    'transition:',
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 16),
        const CodeBlock(code: _taskBuilderSource, language: 'dart'),
        const DocParagraph(
          'Use TaskBuilder when the four-way switch is the whole UI; drop '
          'down to StateObserver when you need to read store state '
          'alongside the task or compose with other reactive sources.',
        ),
        const DocHeading('Awaiting transitions'),
        const DocParagraph(
          'Outside reactive scopes (tests, orchestration scripts), wait '
          'for a specific transition with firstWhere / awaitDone / '
          'awaitFailed / awaitSettled. Each returns a Future that '
          'auto-detaches its subscription as soon as the predicate '
          'matches.',
        ),
        const CodeBlock(code: _awaitSource, language: 'dart'),
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
        const DocBullet(
          'ArmatureApp — where errorHandler (the sink for unmatched '
          'task throws) is installed.',
        ),
      ],
    );
  }
}

const _observeSource = '''StateObserver(
  builder: (_) {
    final state = notesStore.load.state;
    return switch (state) {
      TaskIdle() => FilledButton(
          onPressed: () => notesStore.load(),
          child: const Text('Load notes'),
        ),
      TaskPending() => const FilledButton(
          onPressed: null,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      TaskDone() => Text('\${notesStore.state.items.length} notes loaded'),
      TaskFailed(:final error) => Text('Failed to load: \$error'),
    };
  },
)''';

const _errorSource = '''class NotesStore extends Store<NotesState> {
  NotesStore() : super(state: (items: const []));

  // TError = Exception — IOException and friends land in TaskFailed.
  // Programming errors (StateError, RangeError, ...) rethrow to caller.
  late final load = createVoidTask<void, Exception>(
    fn: () async {
      try {
        final items = await db.readAll();
        state = (items: items);
      } on IOException {
        rethrow;
      }
    },
    strategy: TaskStrategy.once,
  );
}

// Call site:
try {
  await store.load();
} on IOException catch (e) {
  // Domain failure — also visible via store.load.state.
  showError(e);
}''';

const _resetSource = '''class NotesStore extends Store<NotesState> {
  NotesStore() : super(state: (items: const []));

  // After Done/Failed, return to TaskIdle 3s later so the button
  // re-appears without manual intervention.
  late final load = createVoidTask<void, Exception>(
    fn: () async {
      state = (items: await db.readAll());
    },
    autoReset: const Duration(seconds: 3),
  );
}

// In the UI: a manual retry button rendered alongside the failure.
StateObserver(
  builder: (_) {
    final state = notesStore.load.state;
    return switch (state) {
      TaskFailed(:final error) => Row(children: [
        Text('Failed: \$error'),
        TextButton(
          onPressed: notesStore.load.reset,
          child: const Text('Retry'),
        ),
      ]),
      _ => const SizedBox.shrink(),
    };
  },
)''';

const _pickErrorSource = '''// Default for API/IO calls.
late final load = createVoidTask<void, Exception>(
  fn: () async => state = (items: await db.readAll()),
);

// Typed exception hierarchy — switch can match specific cases.
sealed class PersistError implements Exception {}
class DiskFull extends PersistError {}
class PermissionDenied extends PersistError {}

late final persist = createVoidTask<void, PersistError>(
  fn: () async => await db.writeAll(state.items),
);

// Strict — fn shouldn't fail in normal flow; any throw is a bug.
late final clearAll = createVoidTask<void, Never>(
  fn: () async => state = (items: const []),
);

// In the UI:
StateObserver(
  builder: (_) => switch (notesStore.persist.state) {
    TaskFailed(error: DiskFull()) => const Text('Disk is full'),
    TaskFailed(error: PermissionDenied()) => const Text('Permission denied'),
    _ => const SizedBox.shrink(),
  },
)''';

const _whenSource = '''// Exhaustive — compiler enforces every branch.
final widget = task.state.when(
  idle:    ()         => const _Placeholder(),
  pending: (params)   => CircularProgressIndicator.adaptive(),
  done:    (result)   => ResultCard(result),
  failed:  (error)    => ErrorBanner(message: error.toString()),
);

// Partial — only some branches matter.
final label = task.state.maybeWhen<String>(
  done: (r) => 'Loaded \$r items',
  orElse: (_) => 'Loading…',
);

// One-liners.
if (task.state.isPending) showSpinner();
final result = task.state.resultOrNull;          // null unless TaskDone
final params = task.state.paramsOrNull;          // null unless TaskPending
final error  = task.state.errorOrNull;           // null unless TaskFailed''';

const _taskBuilderSource = '''// store.fetchUser: Task<int, User, ApiException>
TaskBuilder(
  task: store.fetchUser,
  idle:    (_)         => const _Placeholder(),
  pending: (_, userId) => const CircularProgressIndicator.adaptive(),
  done:    (_, user)   => UserCard(user),
  failed:  (_, e)      => ErrorBanner(message: e.message),
)''';

const _awaitSource = '''// In a test:
final f = store.fetchUser(42);
expect(store.fetchUser.state, isA<TaskPending<int, User, ApiException>>());
final user = await store.fetchUser.awaitDone();
expect(user.id, 42);
expect(await f, user);

// Orchestration: wait for any terminal state.
final settled = await store.persist.awaitSettled();
print(settled is TaskDone ? 'saved' : 'failed');

// Custom predicate.
await store.search.firstWhere(
  (s) => s is TaskDone<String, List<Note>, Exception>
      && (s as TaskDone).result.isNotEmpty,
);''';
