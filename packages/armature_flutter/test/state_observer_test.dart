import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class TestService extends Store<int> {
  TestService() : super(state: 0);

  void increment() => update((state) => state + 1);
}

void main() {
  group('StateObserver', () {
    testWidgets('rebuilds when tracked state changes', (tester) async {
      final service = TestService();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StateObserver(
            builder: (context) {
              return Text('count: ${service.state}');
            },
          ),
        ),
      );

      expect(find.text('count: 0'), findsOneWidget);

      service.increment();
      await tester.pumpAndSettle();

      expect(find.text('count: 1'), findsOneWidget);

      service.increment();
      service.increment();
      await tester.pumpAndSettle();

      expect(find.text('count: 3'), findsOneWidget);
    });

    testWidgets('does not rebuild when untracked state changes', (
      tester,
    ) async {
      final trackedService = TestService();
      final untrackedService = TestService();
      var buildCount = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StateObserver(
            builder: (context) {
              buildCount++;
              return Text('count: ${trackedService.state}');
            },
          ),
        ),
      );

      final initialBuildCount = buildCount;

      untrackedService.increment();
      await tester.pumpAndSettle();

      expect(buildCount, equals(initialBuildCount));
    });

    testWidgets('cleans up reaction on dispose', (tester) async {
      final service = TestService();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StateObserver(
            builder: (context) {
              return Text('count: ${service.state}');
            },
          ),
        ),
      );

      expect(find.text('count: 0'), findsOneWidget);

      // Replace with empty widget to trigger dispose
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.shrink(),
        ),
      );

      // Updating state after dispose should not throw
      service.increment();
      await tester.pumpAndSettle();

      expect(find.text('count: 1'), findsNothing);
    });
  });
}
