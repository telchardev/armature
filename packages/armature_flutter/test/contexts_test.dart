import 'package:armature/armature.dart'
    show AppContainer, Feature, createFeature;
import 'package:armature_flutter/armature_flutter.dart' show ContainerContext;
import 'package:armature_flutter/src/contexts/feature_context.dart'
    show FeatureContext;
import 'package:flutter/widgets.dart' show Builder, FlutterError, SizedBox;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContainerContext', () {
    testWidgets('provides container to descendants', (tester) async {
      final container = AppContainer(features: []);
      addTearDown(container.dispose);

      AppContainer? foundContainer;

      await tester.pumpWidget(
        ContainerContext(
          container: container,
          child: Builder(
            builder: (context) {
              foundContainer = ContainerContext.of(context).container;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(foundContainer, same(container));
    });

    testWidgets('throws when not in tree', (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            expect(
              () => ContainerContext.of(context),
              throwsA(isA<FlutterError>()),
            );
            return const SizedBox.shrink();
          },
        ),
      );
    });
  });

  group('FeatureContext', () {
    testWidgets('provides feature to descendants', (tester) async {
      final feature = createFeature(name: "TestFeature");
      Feature? foundFeature;

      await tester.pumpWidget(
        FeatureContext(
          feature: feature,
          child: Builder(
            builder: (context) {
              foundFeature = FeatureContext.of(context).feature;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(foundFeature, same(feature));
    });
  });
}
