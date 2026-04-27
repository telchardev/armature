// Syntactic forms of top-level `final feature = createFeature(...)`
// cascades — verifies that the different shapes of onStart /
// activation callbacks (block bodies, arrow-null returns,
// mixed-arity lambdas) all compile and activate cleanly.
//
// Container-lifecycle reuse is covered separately in
// `container_reuse_test.dart`.

import 'package:armature/armature.dart';
import 'package:test/test.dart';

class _Svc extends Store<int> {
  _Svc() : super(state: 0);
}

final _topLevelBlockBody =
    createFeature(
      name: "topLevelBlockBody",
      stores: (_) => (svc: _Svc()),
      exports: (api) => api.own,
    )..onStart((api, cleanup) {
      // block body returns Null — previously broke the runtime cast.
      final _ = api.own.svc;
    });

final _topLevelArrowNull = createFeature(
  name: "topLevelArrowNull",
  stores: (_) => (svc: _Svc()),
  exports: (api) => api.own,
)..onStart((_, _) => null);

final _topLevelActivationBlock =
    createFeature(
      name: "topLevelActivationBlock",
      stores: (_) => (svc: _Svc()),
      exports: (api) => api.own,
    )..activation((_, toggle, _) {
      toggle(ToggleState.active);
    });

void main() {
  group('top-level feature cascade syntax forms', () {
    test('onStart with 2-param block body activates cleanly', () async {
      final c = AppContainer(features: [_topLevelBlockBody]);
      await c.start();
      expect(c.statusOf(_topLevelBlockBody) == FeatureStatus.active, isTrue);
      await c.stop();
    });

    test('onStart with (_, _) => null arrow activates cleanly', () async {
      final c = AppContainer(features: [_topLevelArrowNull]);
      await c.start();
      expect(c.statusOf(_topLevelArrowNull) == FeatureStatus.active, isTrue);
      await c.stop();
    });

    test('activation with 3-param block body activates cleanly', () async {
      final c = AppContainer(features: [_topLevelActivationBlock]);
      await c.start();
      expect(
        c.statusOf(_topLevelActivationBlock) == FeatureStatus.active,
        isTrue,
      );
      await c.stop();
    });
  });
}
