import 'package:armature/advanced.dart' show PipeHandler;
import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:armature_flutter/test_utils.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _CounterStore extends Store<int> {
  _CounterStore() : super(state: 0);

  void increment() => state = state + 1;

  void reset() => state = 0;
}

void main() {
  group('MultiPortBuilder', () {
    testWidgets('reads a single port and rebuilds on reactive state change', (
      tester,
    ) async {
      final rootFeature = createFeature(
        name: 'root',
        stores: (_) => (counter: _CounterStore()),
        exports: (api) => api.own,
      );
      final labelPipe = createPipe<String>(name: 'label', feature: rootFeature);

      final childFeature =
          createFeature(name: 'child', dependsOn: [rootFeature])
            ..usePipe(labelPipe, (value, api) {
              return 'n=${api.of(rootFeature).counter.state}';
            });

      final container = await startedContainer(
        features: [rootFeature, childFeature],
      );
      final counter = rootFeature.storeOf<_CounterStore>(container);

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: MultiPortBuilder(
          builder: (reader, _) {
            final label = reader.pipe(labelPipe, initialValue: '');
            return Text(label);
          },
        ),
      );

      expect(find.text('n=0'), findsOneWidget);

      counter.increment();
      await tester.pumpAndSettle();
      expect(find.text('n=1'), findsOneWidget);
    });

    testWidgets('reads multiple ports; rebuild fires independently for each', (
      tester,
    ) async {
      final rootFeature = createFeature(
        name: 'root',
        stores: (_) => (counter: _CounterStore()),
        exports: (api) => api.own,
      );
      final aPipe = createPipe<int>(name: 'a', feature: rootFeature);
      final bPipe = createPipe<int>(name: 'b', feature: rootFeature);

      final childFeature =
          createFeature(name: 'child', dependsOn: [rootFeature])
            ..usePipe(aPipe, (v, api) => v + api.of(rootFeature).counter.state)
            ..usePipe(
              bPipe,
              (v, api) => v + api.of(rootFeature).counter.state * 10,
            );

      final container = await startedContainer(
        features: [rootFeature, childFeature],
      );
      final counter = rootFeature.storeOf<_CounterStore>(container);

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: MultiPortBuilder(
          builder: (reader, _) {
            final a = reader.pipe(aPipe, initialValue: 0);
            final b = reader.pipe(bPipe, initialValue: 0);
            return Text('a=$a b=$b');
          },
        ),
      );

      expect(find.text('a=0 b=0'), findsOneWidget);

      counter.increment();
      await tester.pumpAndSettle();
      expect(find.text('a=1 b=10'), findsOneWidget);
    });

    testWidgets(
      'reconciles subscriptions when the builder stops reading a port',
      (tester) async {
        final rootFeature = createFeature(
          name: 'root',
          stores: (_) => (counter: _CounterStore()),
          exports: (api) => api.own,
        );
        final aPipe = createPipe<int>(name: 'a', feature: rootFeature);
        final bPipe = createPipe<int>(name: 'b', feature: rootFeature);

        final childFeature =
            createFeature(name: 'child', dependsOn: [rootFeature])
              ..usePipe(
                aPipe,
                (v, api) => v + api.of(rootFeature).counter.state,
              )
              ..usePipe(
                bPipe,
                (v, api) => v + api.of(rootFeature).counter.state,
              );

        final container = await startedContainer(
          features: [rootFeature, childFeature],
        );
        final counter = rootFeature.storeOf<_CounterStore>(container);

        await pumpFeature(
          tester,
          container: container,
          feature: rootFeature,
          child: _ToggleReader(aPipe: aPipe, bPipe: bPipe),
        );
        expect(find.text('a=0'), findsOneWidget);

        counter.increment();
        await tester.pumpAndSettle();
        expect(find.text('a=1'), findsOneWidget);

        // Toggle builder to read `b` instead of `a`.
        _ToggleReader.toggleKey.currentState!.flip();
        await tester.pumpAndSettle();
        expect(find.text('b=1'), findsOneWidget);

        // Further updates are picked up via `b`'s handler re-eval.
        counter.increment();
        await tester.pumpAndSettle();
        expect(find.text('b=2'), findsOneWidget);
      },
    );

    testWidgets(
      'handler throw falls back & reports RenderError to the container',
      (tester) async {
        final collector = collectErrors();
        final rootFeature = createFeature(name: 'root');
        final pipe = createPipe<String>(name: 'p', feature: rootFeature);

        final childFeature = createFeature(
          name: 'child',
          dependsOn: [rootFeature],
        )..usePipe(pipe, (_, _) => throw StateError('boom'));

        final container = await startedContainer(
          features: [rootFeature, childFeature],
          options: collector.options,
        );

        await pumpFeature(
          tester,
          container: container,
          feature: rootFeature,
          child: MultiPortBuilder(
            builder: (reader, _) {
              final value = reader.pipe(pipe, initialValue: 'fallback');
              return Text(value);
            },
          ),
        );

        expect(find.text('fallback'), findsOneWidget);
        expect(collector.errors, isNotEmpty);
        expect(
          collector.errors.any((e) => e is HandlerError || e is RenderError),
          isTrue,
        );
      },
    );

    testWidgets('disposes all subscriptions on unmount', (tester) async {
      final rootFeature = createFeature(
        name: 'root',
        stores: (_) => (counter: _CounterStore()),
        exports: (api) => api.own,
      );
      final pipe = createPipe<int>(name: 'p', feature: rootFeature);

      final childFeature = createFeature(
        name: 'child',
        dependsOn: [rootFeature],
      )..usePipe(pipe, (v, api) => v + api.of(rootFeature).counter.state);

      final container = await startedContainer(
        features: [rootFeature, childFeature],
      );
      final counter = rootFeature.storeOf<_CounterStore>(container);
      var builderCallCount = 0;

      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: MultiPortBuilder(
          builder: (reader, _) {
            builderCallCount++;
            final v = reader.pipe(pipe, initialValue: 0);
            return Text('$v');
          },
        ),
      );
      expect(builderCallCount, greaterThanOrEqualTo(1));
      final builds = builderCallCount;

      // Unmount the MultiPortBuilder by replacing with a different widget.
      await pumpFeature(
        tester,
        container: container,
        feature: rootFeature,
        child: const Text('gone'),
      );

      // Trigger a port change — MultiPortBuilder must NOT rebuild (it's gone).
      counter.increment();
      await tester.pumpAndSettle();
      expect(builderCallCount, equals(builds));
      expect(find.text('gone'), findsOneWidget);
    });
  });
}

class _ToggleReader extends StatefulWidget {
  static final GlobalKey<_ToggleReaderState> toggleKey =
      GlobalKey<_ToggleReaderState>();

  final Pipe<int, PipeHandler<int>> aPipe;
  final Pipe<int, PipeHandler<int>> bPipe;

  _ToggleReader({required this.aPipe, required this.bPipe})
    : super(key: toggleKey);

  @override
  State<_ToggleReader> createState() => _ToggleReaderState();
}

class _ToggleReaderState extends State<_ToggleReader> {
  bool _readA = true;

  void flip() => setState(() => _readA = !_readA);

  @override
  Widget build(BuildContext context) {
    return MultiPortBuilder(
      builder: (reader, _) {
        if (_readA) {
          final a = reader.pipe(widget.aPipe, initialValue: 0);
          return Text('a=$a');
        }
        final b = reader.pipe(widget.bPipe, initialValue: 0);
        return Text('b=$b');
      },
    );
  }
}
