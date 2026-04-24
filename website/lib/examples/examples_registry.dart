import 'package:flutter/widgets.dart';

import 'content/auth_flow/auth_page.dart';
import 'content/coming_soon_example.dart';
import 'content/counter/counter_page.dart';
import 'content/debounced_search/search_page.dart';
import 'content/feature_toggles/feature_toggles_page.dart';
import 'content/todo_list/todo_page.dart';
import 'examples_tree.dart';

const Map<String, Widget> _registry = {
  'counter': CounterExamplePage(),
  'todo-list': TodoExamplePage(),
  'debounced-search': SearchExamplePage(),
  'feature-toggles': FeatureTogglesPage(),
  'auth-flow': AuthFlowPage(),
};

Widget resolveExampleContent(String slug) {
  final registered = _registry[slug];
  if (registered != null) {
    return registered;
  }
  final entry = findExample(slug);
  return ComingSoonExample(title: entry?.title ?? slug);
}
