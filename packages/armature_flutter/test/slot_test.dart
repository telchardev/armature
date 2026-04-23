import 'package:armature/armature.dart' show Store, createFeature;
import 'package:armature_flutter/armature_flutter.dart';
import 'package:armature_flutter/test_utils.dart';
import 'package:flutter/widgets.dart' show SizedBox, Text, Widget;
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(initTestRenderer);

  group('createSingleSlot', () {
    test('returns null when no handlers registered', () async {
      final rootFeature = createFeature(name: "root");
      final slot = createSingleSlot<Null>(
        name: "empty_slot",
        feature: rootFeature,
      );

      final container = await startedContainer(features: [rootFeature]);

      final result = container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: null,
        data: null,
      );

      expect(result, isNull);
    });

    test('returns widget from single handler', () async {
      final rootFeature = createFeature(name: "root");
      final slot = createSingleSlot<Null>(
        name: "single_handler_slot",
        feature: rootFeature,
      );

      final childFeature =
          createFeature(name: "child", dependsOn: [rootFeature])
            ..useSingleSlot(slot, (data, api) {
              return const Text("hello");
            });

      final container = await startedContainer(
        features: [rootFeature, childFeature],
      );

      final result = container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: null,
        data: null,
      );

      expect(result, isNotNull);
      expect(result, isA<Widget>());
    });

    test('selects highest priority handler', () async {
      final rootFeature = createFeature(name: "root");
      final slot = createSingleSlot<String>(
        name: "priority_slot",
        feature: rootFeature,
      );

      final lowPriority =
          createFeature(name: "low_priority", dependsOn: [rootFeature])
            ..useSingleSlot(slot, (data, api) {
              return const Text("low");
            }, priority: 1);

      final highPriority =
          createFeature(name: "high_priority", dependsOn: [rootFeature])
            ..useSingleSlot(slot, (data, api) {
              return const Text("high");
            }, priority: 10);

      final container = await startedContainer(
        features: [rootFeature, lowPriority, highPriority],
      );

      final result = container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: null,
        data: "test",
      );

      expect(result, isNotNull);
    });

    test('skips disabled features', () async {
      final rootFeature = createFeature(name: "root");
      final slot = createSingleSlot<Null>(
        name: "disabled_slot",
        feature: rootFeature,
      );

      final disabledFeature =
          createFeature(name: "disabled", dependsOn: [rootFeature])
            ..useSingleSlot(slot, (data, api) {
              return const Text("should not appear");
            })
            ..activation((_, _, _) {});

      final container = await startedContainer(
        features: [rootFeature, disabledFeature],
      );

      final result = container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: null,
        data: null,
      );

      expect(result, isNull);
    });

    test('passes input data to handler', () async {
      final rootFeature = createFeature(name: "root");
      final slot = createSingleSlot<String>(
        name: "data_slot",
        feature: rootFeature,
      );

      String? receivedData;

      final childFeature =
          createFeature(name: "child", dependsOn: [rootFeature])
            ..useSingleSlot(slot, (data, api) {
              receivedData = data;
              return const SizedBox.shrink();
            });

      final container = await startedContainer(
        features: [rootFeature, childFeature],
      );

      container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: null,
        data: "hello_world",
      );

      expect(receivedData, equals("hello_world"));
    });

    test('returns null when handler returns null', () async {
      final rootFeature = createFeature(name: "root");
      final slot = createSingleSlot<Null>(
        name: "null_slot",
        feature: rootFeature,
      );

      final childFeature =
          createFeature(name: "child", dependsOn: [rootFeature])
            ..useSingleSlot(slot, (data, api) {
              return null;
            });

      final container = await startedContainer(
        features: [rootFeature, childFeature],
      );

      final result = container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: null,
        data: null,
      );

      expect(result, isNull);
    });

    test('reacts to state change: null → widget', () async {
      final rootFeature = createFeature(
        name: "root",
        stores: (_) => (toggle: _ToggleStore()),
        exports: (api) => api.own,
      );
      final slot = createSingleSlot<Null>(
        name: "reactive_slot",
        feature: rootFeature,
      );

      final childFeature =
          createFeature(name: "child", dependsOn: [rootFeature])
            ..useSingleSlot(slot, (data, api) {
              final visible = api.from(rootFeature).toggle.state;
              if (!visible) return null;
              return const Text("visible");
            });

      final container = await startedContainer(
        features: [rootFeature, childFeature],
      );
      final toggleService = rootFeature.storeOf<_ToggleStore>();

      // Initially false → null
      var result = container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: null,
        data: null,
      );
      expect(result, isNull);

      // Toggle to true → widget appears
      toggleService.toggle();

      result = container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: null,
        data: null,
      );
      expect(result, isNotNull);

      // Toggle back to false → null again
      toggleService.toggle();

      result = container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: null,
        data: null,
      );
      expect(result, isNull);
    });
  });

  group('createMultiSlot', () {
    test('returns empty list when no handlers', () async {
      final rootFeature = createFeature(name: "root");
      final slot = createMultiSlot<Null>(
        name: "empty_multi",
        feature: rootFeature,
        orderDirection: MultiSlotOrderDirection.asc,
      );

      final container = await startedContainer(features: [rootFeature]);

      final result = container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: <Widget>[],
        data: null,
      );

      expect(result, isEmpty);
    });

    test('collects widgets from multiple features', () async {
      final rootFeature = createFeature(name: "root");
      final slot = createMultiSlot<Null>(
        name: "multi_collect",
        feature: rootFeature,
        orderDirection: MultiSlotOrderDirection.asc,
      );

      final featureA =
          createFeature(name: "feature_a", dependsOn: [rootFeature])
            ..useMultiSlot(slot, (data, api) {
              return const Text("A");
            }, order: 1);

      final featureB =
          createFeature(name: "feature_b", dependsOn: [rootFeature])
            ..useMultiSlot(slot, (data, api) {
              return const Text("B");
            }, order: 2);

      final container = await startedContainer(
        features: [rootFeature, featureA, featureB],
      );

      final result = container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: <Widget>[],
        data: null,
      );

      expect(result, hasLength(2));
    });

    test('skips handlers returning null', () async {
      final rootFeature = createFeature(name: "root");
      final slot = createMultiSlot<Null>(
        name: "multi_null",
        feature: rootFeature,
        orderDirection: MultiSlotOrderDirection.asc,
      );

      final visibleFeature =
          createFeature(name: "visible", dependsOn: [rootFeature])
            ..useMultiSlot(slot, (data, api) {
              return const Text("visible");
            }, order: 1);

      final hiddenFeature =
          createFeature(name: "hidden", dependsOn: [rootFeature])
            ..useMultiSlot(slot, (data, api) {
              return null;
            }, order: 2);

      final container = await startedContainer(
        features: [rootFeature, visibleFeature, hiddenFeature],
      );

      final result = container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: <Widget>[],
        data: null,
      );

      expect(result, hasLength(1));
    });

    test('reacts to state change: adds/removes widgets', () async {
      final rootFeature = createFeature(
        name: "root",
        stores: (_) => (toggle: _ToggleStore()),
        exports: (api) => api.own,
      );
      final slot = createMultiSlot<Null>(
        name: "reactive_multi",
        feature: rootFeature,
        orderDirection: MultiSlotOrderDirection.asc,
      );

      final alwaysFeature =
          createFeature(name: "always", dependsOn: [rootFeature])
            ..useMultiSlot(slot, (data, api) {
              return const Text("always");
            }, order: 1);

      final conditionalFeature =
          createFeature(name: "conditional", dependsOn: [rootFeature])
            ..useMultiSlot(slot, (data, api) {
              final visible = api.from(rootFeature).toggle.state;
              if (!visible) return null;
              return const Text("conditional");
            }, order: 2);

      final container = await startedContainer(
        features: [rootFeature, alwaysFeature, conditionalFeature],
      );
      final toggleService = rootFeature.storeOf<_ToggleStore>();

      // Initially false → only 1 widget
      var result = container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: <Widget>[],
        data: null,
      );
      expect(result, hasLength(1));

      // Toggle → 2 widgets
      toggleService.toggle();

      result = container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: <Widget>[],
        data: null,
      );
      expect(result, hasLength(2));

      // Toggle back → 1 widget
      toggleService.toggle();

      result = container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: <Widget>[],
        data: null,
      );
      expect(result, hasLength(1));
    });

    test('skips disabled features', () async {
      final rootFeature = createFeature(name: "root");
      final slot = createMultiSlot<Null>(
        name: "multi_disabled",
        feature: rootFeature,
        orderDirection: MultiSlotOrderDirection.asc,
      );

      final enabledFeature =
          createFeature(name: "enabled", dependsOn: [rootFeature])
            ..useMultiSlot(slot, (data, api) {
              return const Text("enabled");
            }, order: 1);

      final disabledFeature =
          createFeature(name: "disabled", dependsOn: [rootFeature])
            ..useMultiSlot(slot, (data, api) {
              return const Text("disabled");
            }, order: 2)
            ..activation((_, _, _) {});

      final container = await startedContainer(
        features: [rootFeature, enabledFeature, disabledFeature],
      );

      final result = container.apply(
        rootFeature: rootFeature,
        port: slot,
        initialValue: <Widget>[],
        data: null,
      );

      expect(result, hasLength(1));
    });
  });

  group('createSingleSwitchSlot', () {
    test('returns same slot instance for same route', () {
      final feature = createFeature(name: "root");
      final factory = createSingleSwitchSlot<Null>(
        name: "switch",
        feature: feature,
      );

      final slotA = factory("home");
      final slotB = factory("home");

      expect(identical(slotA, slotB), isTrue);
    });

    test('returns different slot instances for different routes', () {
      final feature = createFeature(name: "root");
      final factory = createSingleSwitchSlot<Null>(
        name: "switch",
        feature: feature,
      );

      final slotHome = factory("home");
      final slotProfile = factory("profile");

      expect(identical(slotHome, slotProfile), isFalse);
    });

    test('slot names follow name/route pattern', () {
      final feature = createFeature(name: "root");
      final factory = createSingleSwitchSlot<Null>(
        name: "nav",
        feature: feature,
      );

      final slot = factory("settings");

      expect(slot.name, equals("nav/settings"));
    });
  });

  group('createMultiSwitchSlot', () {
    test('returns same slot instance for same route', () {
      final feature = createFeature(name: "root");
      final factory = createMultiSwitchSlot<Null>(
        name: "multi_switch",
        feature: feature,
        orderDirection: MultiSlotOrderDirection.asc,
      );

      final slotA = factory("dashboard");
      final slotB = factory("dashboard");

      expect(identical(slotA, slotB), isTrue);
    });

    test('returns different slot instances for different routes', () {
      final feature = createFeature(name: "root");
      final factory = createMultiSwitchSlot<Null>(
        name: "multi_switch",
        feature: feature,
        orderDirection: MultiSlotOrderDirection.desc,
      );

      final slotA = factory("page1");
      final slotB = factory("page2");

      expect(identical(slotA, slotB), isFalse);
    });

    test('slot names follow name/route pattern', () {
      final feature = createFeature(name: "root");
      final factory = createMultiSwitchSlot<Null>(
        name: "tabs",
        feature: feature,
        orderDirection: MultiSlotOrderDirection.asc,
      );

      final slot = factory("inbox");

      expect(slot.name, equals("tabs/inbox"));
    });

    test('preserves order direction from factory', () {
      final feature = createFeature(name: "root");
      final ascFactory = createMultiSwitchSlot<Null>(
        name: "asc_switch",
        feature: feature,
        orderDirection: MultiSlotOrderDirection.asc,
      );
      final descFactory = createMultiSwitchSlot<Null>(
        name: "desc_switch",
        feature: feature,
        orderDirection: MultiSlotOrderDirection.desc,
      );

      final ascSlot = ascFactory("route");
      final descSlot = descFactory("route");

      expect(ascSlot.orderDirection, MultiSlotOrderDirection.asc);
      expect(descSlot.orderDirection, MultiSlotOrderDirection.desc);
    });
  });
}

/// Simple bool store for reactive tests.
class _ToggleStore extends Store<bool> {
  _ToggleStore() : super(state: false);

  void toggle() {
    state = !state;
  }
}
