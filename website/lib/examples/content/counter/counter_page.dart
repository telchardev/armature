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
          _Caption('The store'),
          CodeBlock(code: _storeSource, language: 'dart'),
          SizedBox(height: 20),
          _Caption('The widget'),
          CodeBlock(code: _widgetSource, language: 'dart'),
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

const _storeSource = '''class CounterStore extends Store<({int value})> {
  CounterStore() : super(state: (value: 0));

  late final increment = createVoidTask(
    fn: () async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      state = (value: state.value + 1);
    },
    strategy: TaskStrategy.queue,
  );

  late final debouncedBump = createVoidTask(
    fn: () async {
      state = (value: state.value + 1);
    },
    strategy: TaskStrategy.debounce(Duration(milliseconds: 400)),
  );

  late final reset = createVoidTask(
    fn: () async => state = (value: 0),
    strategy: TaskStrategy.queue,
  );
}''';

const _widgetSource = '''class CounterDemoWidget extends StatefulWidget {
  const CounterDemoWidget({super.key});

  @override
  State<CounterDemoWidget> createState() => _State();
}

class _State extends State<CounterDemoWidget> {
  late final _store = CounterStore();

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StateObserver(
          builder: (_) => Text('\${_store.state.value}'),
        ),
        FilledButton(
          onPressed: _store.increment,
          child: const Text('Increment'),
        ),
      ],
    );
  }
}''';
