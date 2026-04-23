import 'package:armature/armature.dart';

class ActiveTabStore extends Store<String> {
  ActiveTabStore() : super(state: 'counter');

  void setTab(String id) {
    state = id;
  }
}
