import 'package:armature/armature.dart';

typedef FeatureTogglesState = ({bool inspector});

extension FeatureTogglesStateCopyWith on FeatureTogglesState {
  FeatureTogglesState copyWith({bool? inspector}) =>
      (inspector: inspector ?? this.inspector);
}

class FeatureTogglesStore extends Store<FeatureTogglesState> {
  FeatureTogglesStore() : super(state: (inspector: true));

  void setInspector(bool value) {
    update((s) => s.copyWith(inspector: value));
  }
}
