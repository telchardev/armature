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
        const DocHeading('Tasks'),
        const DocParagraph(
          'Tasks wrap async work with an observable state machine: '
          'TaskIdle → TaskPending → TaskDone | TaskFailed. A store owns its '
          'tasks via createVoidTask (no arguments) or createTask (typed '
          'arguments):',
        ),
        const CodeBlock(code: _taskSource, language: 'dart'),
        const DocParagraph(
          'Calling fetchUser(42) returns a Future that resolves with the '
          'loaded user; observers watching the task state see the full '
          'lifecycle in order.',
        ),
        const DocHeading('Task strategies'),
        const DocParagraph(
          'Every task picks a strategy that defines how concurrent calls '
          'are handled. Five variants cover the common patterns; the '
          'strategy parameter is optional and defaults to queue:',
        ),
        const DocBullet(
          'queue (default) — serialises calls FIFO; each waits for the '
          'previous to complete. Good for ordered mutations like a counter '
          'increment.',
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
          'auto-save or typing-settled effects.',
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

const _declareSource = '''typedef UserState = ({String? name, int age});

class UserStore extends Store<UserState> {
  UserStore() : super(state: (name: null, age: 0));
}''';

const _observerSource = '''StateObserver(
  builder: (_) {
    final state = userStore.state;
    return Text(state.name ?? 'anonymous');
  },
)''';

const _writeSource = '''class UserStore extends Store<UserState> {
  UserStore() : super(state: (name: null, age: 0));

  void rename(String name) {
    state = (name: name, age: state.age);
  }

  void birthday() {
    update((s) => (name: s.name, age: s.age + 1));
  }
}''';

const _taskSource = '''class UserStore extends Store<UserState> {
  UserStore() : super(state: (name: null, age: 0));

  late final fetchUser = createTask<int, User, Exception>(
    fn: (id) async {
      final user = await api.getUser(id);
      state = (name: user.name, age: user.age);
      return user;
    },
    strategy: TaskStrategy.latest,
  );

  late final refresh = createVoidTask(
    fn: () async => api.refreshCurrent(),
    strategy: TaskStrategy.once,
  );
}''';

const _strategySource = '''late final save = createVoidTask(
  fn: () async => await api.persist(state),
  strategy: TaskStrategy.debounce(Duration(milliseconds: 500)),
);

late final search = createTask<String, List<Hit>, Exception>(
  fn: (query) => api.search(query),
  strategy: TaskStrategy.latest,
);''';
