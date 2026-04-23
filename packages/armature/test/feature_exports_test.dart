import 'package:armature/armature.dart';
import 'package:armature/test_utils.dart';
import 'package:test/test.dart';

class _Counter {
  int value = 0;
}

class _Auth {
  String? user;

  Future<void> login(String name) async {
    user = name;
  }

  void logout() {
    user = null;
  }
}

typedef _AuthExports = ({
  Future<void> Function(String) login,
  void Function() logout,
  String? Function() user,
});

void main() {
  group('Feature.exports (1c-strict)', () {
    test(
      'createFeature with stores and no exports throws FeatureConfigurationError',
      () {
        expect(
          () => createFeature(
            name: 'NoExports',
            stores: (_) => (counter: _Counter()),
          ),
          throwsA(
            isA<FeatureConfigurationError>()
                .having(
                  (e) => e.featureName,
                  'featureName',
                  equals('NoExports'),
                )
                .having(
                  (e) => e.toString(),
                  'message',
                  contains(
                    'feature with `stores:` must also declare `exports:`',
                  ),
                ),
          ),
        );
      },
    );

    test('createFeature with no stores and no exports is valid', () {
      // Stateless feature — common pattern for pure port extensions.
      final feature = createFeature(name: 'Stateless');
      expect(feature.name, equals('Stateless'));
    });

    test('createFeature with stores and exports constructs cleanly', () async {
      final feature = createFeature(
        name: 'WithExports',
        stores: (_) => (counter: _Counter()),
        exports: (api) => api.own,
      );
      await startedContainer(features: [feature]);
      expect(feature.name, equals('WithExports'));
    });

    test('api.from returns exports — passthrough mirrors stores', () async {
      final parent = createFeature(
        name: 'parent',
        stores: (_) => (counter: _Counter()),
        exports: (api) => api.own,
      );
      int seenFromChildFactory = -1;
      final child = createFeature(
        name: 'child',
        dependsOn: [parent],
        stores: (parentApi) {
          seenFromChildFactory = parentApi.of(parent).counter.value;
          return null;
        },
        exports: (api) => api.own,
      );
      await startedContainer(features: [parent, child]);
      expect(seenFromChildFactory, equals(0));
    });

    test('api.from returns narrowed exports when hiding fields', () async {
      final authFeature = createFeature(
        name: 'Auth',
        stores: (_) => (auth: _Auth()),
        exports: (api) => (
          login: api.own.auth.login,
          logout: api.own.auth.logout,
          user: () => api.own.auth.user,
        ),
      );

      _AuthExports? captured;
      final consumer = createFeature(
        name: 'Consumer',
        dependsOn: [authFeature],
        stores: (parentApi) {
          captured = parentApi.of(authFeature);
          return null;
        },
        exports: (api) => api.own,
      );

      await startedContainer(features: [authFeature, consumer]);

      expect(captured, isNotNull);
      expect(captured!.user(), isNull);
      await captured!.login('admin');
      expect(captured!.user(), equals('admin'));
      captured!.logout();
      expect(captured!.user(), isNull);
    });

    test('exports factory runs exactly once (lazy + memoised)', () async {
      var exportsCallCount = 0;
      final parent = createFeature(
        name: 'parent',
        stores: (_) => (counter: _Counter()),
        exports: (api) {
          exportsCallCount++;
          return api.own;
        },
      );

      // Two independent children both read the parent's exports.
      final childA = createFeature(
        name: 'childA',
        dependsOn: [parent],
        stores: (parentApi) {
          final read = parentApi.of(parent).counter.value;
          return (read: read);
        },
        exports: (api) => api.own,
      );
      final childB = createFeature(
        name: 'childB',
        dependsOn: [parent],
        stores: (parentApi) {
          // Two reads within the same factory — still a single exports call.
          final readA = parentApi.of(parent).counter.value;
          final readB = parentApi.of(parent).counter.value;
          return (readA: readA, readB: readB);
        },
        exports: (api) => api.own,
      );

      await startedContainer(features: [parent, childA, childB]);

      expect(
        exportsCallCount,
        equals(1),
        reason: 'exports factory must be memoised across all callers',
      );
    });

    test('exports can hold plain values / references without stores', () async {
      // Stateless feature with no stores can legally go without exports.
      // Its api.from(...) returns the inferred TExports (typically Null).
      final stateless = createFeature(name: 'pure-extension');
      final container = await startedContainer(features: [stateless]);
      expect(container.statusOf(stateless), equals(FeatureStatus.active));
    });
  });
}
