import 'package:armature/armature.dart';

typedef FeatureTogglesState = ({bool inspector});

class FeatureTogglesStore extends Store<FeatureTogglesState> {
  FeatureTogglesStore() : super(state: (inspector: true));

  void setInspector(bool value) {
    update((s) => (inspector: value));
  }
}
