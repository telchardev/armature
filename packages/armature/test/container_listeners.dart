import 'package:mockito/annotations.dart';

@GenerateMocks([Listeners])
class Listeners {
  void onFeatureStatusChanged() {}

  void onFeatureStatusChanged2() {}

  void onPortChanged() {}

  void onPortChanged2() {}
}
