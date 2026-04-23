import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

const String kGitHubUrl = 'https://github.com/telchardev/armature';
const String kPubDevUrl = 'https://pub.dev/packages/armature';
const String kApiDocsUrl = 'https://pub.dev/documentation/armature/latest/';

void openExternal(String url) {
  unawaited(launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication));
}
