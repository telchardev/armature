import 'package:flutter/material.dart';

import '../../../docs/doc_typography.dart';
import '../../../widgets/code_block.dart';
import '../../../widgets/external_links.dart';
import 'counter_widget.dart';

class CounterExamplePage extends StatelessWidget {
  const CounterExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DocTitle('Counter'),
          const DocParagraph(
            'A single store holding one integer. Two task strategies drive '
            'the buttons — a queued increment that serialises async calls, '
            'and a debounced bump that collapses rapid taps into one write.',
          ),
          const SizedBox(height: 8),
          const _Tabs(),
          const SizedBox(height: 24),
          const SizedBox(
            height: 560,
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [_PreviewTab(), _CodeTab()],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'See the full multi-feature version in the armature_example '
            'package on GitHub.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () =>
                openExternal('$kGitHubUrl/tree/main/examples/armature_example'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open armature_example on GitHub'),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerHeight: 0,
        tabs: const [
          Tab(text: 'Preview'),
          Tab(text: 'Code'),
        ],
      ),
    );
  }
}

class _PreviewTab extends StatefulWidget {
  const _PreviewTab();

  @override
  State<_PreviewTab> createState() => _PreviewTabState();
}

class _PreviewTabState extends State<_PreviewTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: CounterDemoWidget(),
      ),
    );
  }
}

class _CodeTab extends StatelessWidget {
  const _CodeTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _Caption('counter_store.dart'),
          CodeBlock(code: _counterStoreSource, language: 'dart'),
          SizedBox(height: 20),
          _Caption('counter_widget.dart'),
          CodeBlock(code: _counterWidgetSource, language: 'dart'),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

const _counterStoreSource = r'''import 'package:armature/armature.dart';

/// State record — a single integer value.
typedef CounterState = ({int value});

/// Reactive store for the counter example.
///
/// Demonstrates two task strategies: `queue` for serialised asynchronous
/// increments, and `debounce` for rate-limited bumps that collapse rapid
/// calls into a single write.
class CounterStore extends Store<CounterState> {
  CounterStore() : super(state: (value: 0));

  /// Increments after a short delay. With `queue`, two rapid taps run
  /// back-to-back — you see the value climb smoothly.
  late final increment = createVoidTask(
    fn: () async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      state = (value: state.value + 1);
    },
  );

  /// Fires at most once per 400 ms, no matter how fast you tap.
  late final debouncedBump = createVoidTask(
    fn: () async {
      state = (value: state.value + 1);
    },
    strategy: TaskStrategy.debounce(Duration(milliseconds: 400)),
  );

  /// Resets the counter to zero immediately.
  late final reset = createVoidTask(
    fn: () async {
      state = (value: 0);
    },
  );
}
''';

const _counterWidgetSource = r'''import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import 'counter_store.dart';

/// Feature owning the [CounterStore]. The framework constructs the store
/// on container start and disposes it on container teardown — no manual
/// `store.dispose()` needed in widget code.
final counterFeature = createFeature(
  name: 'Counter',
  stores: (_) => (counter: CounterStore()),
  exports: (api) => api.own,
);

final _counterRoot = createFeatureRoot(
  feature: counterFeature,
  widget: const _CounterView(),
);

class CounterDemoWidget extends StatelessWidget {
  const CounterDemoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ArmatureApp(
      features: [counterFeature],
      child: _counterRoot(data: null),
    );
  }
}

class _CounterView extends StatelessWidget {
  const _CounterView();

  @override
  Widget build(BuildContext context) {
    final store = StoreContext.of<CounterStore>(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StateObserver(
          builder: (_) => Text(
            '${store.state.value}',
            style: Theme.of(context).textTheme.displayLarge,
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => store.increment(),
              icon: const Icon(Icons.add),
              label: const Text('Increment (queue)'),
            ),
            OutlinedButton.icon(
              onPressed: () => store.debouncedBump(),
              icon: const Icon(Icons.timer_outlined),
              label: const Text('Debounced bump (400ms)'),
            ),
            TextButton.icon(
              onPressed: () => store.reset(),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset'),
            ),
          ],
        ),
      ],
    );
  }
}
''';
