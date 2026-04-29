import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class StoresContent extends StatelessWidget {
  const StoresContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Stores'),
        const DocParagraph(
          'A store owns a piece of reactive state and the actions that mutate '
          'it. Stores are plain Dart classes — no code generation, no '
          'globals. Features create them in their stores factory; the '
          'framework tracks the instances and makes them available through '
          'the api.',
        ),
        const DocHeading('Declaring a store'),
        const DocParagraph(
          'Extend Store<TState> and pass the initial value to super. TState '
          'is usually a record, but any type works:',
        ),
        const CodeBlock(code: _declareSource, language: 'dart'),
        const DocParagraph(
          'The state field is protected — external callers can read it but '
          'only the store itself (or its subclasses) can write. This keeps '
          'mutation localised and traceable.',
        ),
        const DocHeading('Reading state'),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text:
                    'Reading state inside a reaction-tracked scope registers '
                    'the reader as a dependency. The most common tracked '
                    'scope is the ',
              ),
              inlineCode('StateObserver', context),
              const TextSpan(
                text:
                    ' widget — its builder is re-run whenever a state it '
                    'observed changes:',
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 16),
        const CodeBlock(code: _observerSource, language: 'dart'),
        const DocParagraph(
          'Reading outside a tracked scope is a plain read — no subscription '
          'registered. This is useful in event handlers where you only need '
          'the current value.',
        ),
        const DocHeading('Writing state'),
        const DocParagraph(
          'Two ways to mutate: direct assignment and the update callback. '
          'Both are protected and equality-filtered — writes that produce '
          'the same value are skipped:',
        ),
        const CodeBlock(code: _writeSource, language: 'dart'),
        const DocHeading('Imperative subscriptions'),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Outside reactive scopes, listen to a store with ',
              ),
              inlineCode('subscribe', context),
              const TextSpan(text: ' for the raw whole-state signal, or '),
              inlineCode('subscribeSelect', context),
              const TextSpan(
                text:
                    ' for an equality-filtered projection. Both return a '
                    'disposer; both are silent no-ops after dispose.',
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 16),
        const CodeBlock(code: _subscribeSource, language: 'dart'),
        const DocParagraph(
          'subscribeSelect compares projections with == by default. For '
          'collection-typed selectors pass equals (e.g. listEquals from '
          'flutter/foundation) so the listener fires only on content '
          'changes:',
        ),
        const CodeBlock(code: _subscribeSelectEqualsSource, language: 'dart'),
        const DocHeading('Side effects from widgets'),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text:
                    'StateObserver / StoreBuilder rebuild on changes. For '
                    'fire-and-forget side effects (navigation, snackbars, '
                    'analytics) without rebuilding, wrap the subtree in ',
              ),
              inlineCode('StoreListener', context),
              const TextSpan(
                text:
                    ' — it subscribes for the lifetime of the widget and '
                    'fires the callback only on transitions that pass the '
                    'optional listenWhen filter:',
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 16),
        const CodeBlock(code: _storeListenerSource, language: 'dart'),
        const DocParagraph(
          'The state generic is inferred from the Store argument — no '
          'second type parameter to spell out. listener receives the '
          'current BuildContext, so it can call Navigator, '
          'ScaffoldMessenger, or anything else that needs the tree.',
        ),
        const DocHeading('Tasks'),
        const DocParagraph(
          'Tasks wrap async work with an observable state machine: '
          'TaskIdle → TaskPending → TaskDone | TaskFailed. A store owns its '
          'tasks via createVoidTask (no arguments) or createTask (typed '
          'arguments):',
        ),
        const CodeBlock(code: _taskSource, language: 'dart'),
        const DocParagraph(
          'Calling load() returns a Future that resolves once the load '
          'finishes; observers watching the task state see the full '
          'lifecycle in order. persist runs as a side effect of every '
          'add/remove (it is debounced — see below).',
        ),
        const DocHeading('Task strategies'),
        const DocParagraph(
          'Every task picks a strategy that defines how concurrent calls '
          'are handled. Five variants cover the common patterns; the '
          'strategy parameter is optional and defaults to queue:',
        ),
        const DocBullet(
          'queue (default) — serialises calls FIFO; each waits for the '
          'previous to complete. Good for ordered mutations like adding '
          'a note.',
        ),
        const DocBullet(
          'once — runs a single time; later calls return the cached result '
          'or share the in-flight future. Good for one-shot initialisation.',
        ),
        const DocBullet(
          'latest — a new call supersedes the in-flight run. All pending '
          'callers share the latest outcome. Good for search-as-you-type '
          'where only the most recent query matters.',
        ),
        const DocBullet(
          'debounce(d) — coalesces bursts; the function fires once after '
          'the last call, using the most recent arguments. Good for '
          'auto-save (persist after the user stops typing).',
        ),
        const DocBullet(
          'throttle(d) — rate-limits. Leading edge fires immediately and '
          'cools down; trailing edge collects calls and fires once at the '
          'end of the window.',
        ),
        const SizedBox(height: 8),
        const DocParagraph('Example:'),
        const CodeBlock(code: _strategySource, language: 'dart'),
        const DocHeading('Lifecycle'),
        const DocParagraph(
          'The framework calls dispose when the owning feature deactivates. '
          'dispose is idempotent and cascades to every task created on the '
          'store — in-flight calls reject with TaskError and writes after '
          'dispose are silently ignored. If a subclass needs extra teardown, '
          'override dispose and call super.dispose() first.',
        ),
        const DocHeading('What is next?'),
        const DocBullet(
          'Ports — how stores in one feature get wired into another.',
        ),
        const DocBullet(
          'Tasks in detail — state machine, error handling, '
          'TaskState pattern-matching.',
        ),
        const DocBullet(
          'Activation helpers — whenStoreState and friends that gate a '
          'feature on a store\'s value.',
        ),
      ],
    );
  }
}

const _declareSource = '''typedef Note = ({String id, String text});
typedef NotesState = ({List<Note> items});

class NotesStore extends Store<NotesState> {
  NotesStore() : super(state: (items: const []));
}''';

const _observerSource = '''StateObserver(
  builder: (_) {
    final state = notesStore.state;
    return Text('\${state.items.length} notes');
  },
)''';

const _writeSource = '''class NotesStore extends Store<NotesState> {
  NotesStore() : super(state: (items: const []));

  void add(String text) {
    final id = 'n\${state.items.length}';
    update((s) => (items: [...s.items, (id: id, text: text)]));
  }

  void clear() {
    state = (items: const []);
  }
}''';

const _taskSource = '''class NotesStore extends Store<NotesState> {
  NotesStore() : super(state: (items: const []));

  // Initial load from disk.
  late final load = createVoidTask<void, Exception>(
    fn: () async {
      final loaded = await db.readAll();
      state = (items: loaded);
    },
    strategy: TaskStrategy.once,
  );

  // Auto-save after every add / remove, coalesced.
  late final persist = createVoidTask(
    fn: () async => await db.writeAll(state.items),
    strategy: TaskStrategy.debounce(const Duration(milliseconds: 300)),
  );

  void add(String text) {
    final id = 'n\${state.items.length}';
    update((s) => (items: [...s.items, (id: id, text: text)]));
    persist();
  }
}''';

const _strategySource = '''late final persist = createVoidTask(
  fn: () async => await db.writeAll(state.items),
  strategy: TaskStrategy.debounce(Duration(milliseconds: 300)),
);

late final search = createTask<String, List<Note>, Exception>(
  fn: (query) => searchEngine.find(query),
  strategy: TaskStrategy.latest,
);''';

const _subscribeSource = '''// Whole-state side effect.
final cancel = userStore.subscribe((prev, next) {
  print('user changed: \${prev.id} -> \${next.id}');
});

// Equality-filtered projection. Fires only when user.id moves.
final cancelId = userStore.subscribeSelect(
  (s) => s.user?.id,
  (prev, next) => analytics.identify(next),
);

// ... later ...
cancel();
cancelId();''';

const _subscribeSelectEqualsSource =
    '''import 'package:flutter/foundation.dart' show listEquals;

notesStore.subscribeSelect(
  (s) => s.items,
  (_, next) => sync(next),
  equals: listEquals,
);''';

const _storeListenerSource = '''StoreListener(
  store: context.store<AuthStore>(),
  // Optional edge filter — fires only when the predicate flips true.
  listenWhen: (prev, next) => !prev.isLoggedIn && next.isLoggedIn,
  listener: (ctx, _) =>
      Navigator.of(ctx).pushReplacementNamed('/home'),
  child: const LoginForm(),
)''';
