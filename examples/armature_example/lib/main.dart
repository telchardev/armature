import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'admin/config.dart';
import 'auth/config.dart';
import 'counter/config.dart';
import 'feature_toggles/config.dart';
import 'history/config.dart';
import 'inspector/config.dart';
import 'inspectorSub/config.dart';
import 'layout/config.dart';
import 'night_mode/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    ArmatureApp(
      features: [
        layoutFeature,
        counterFeature,
        historyFeature,
        authFeature,
        adminFeature,
        inspectorSubFeature,
        nightModeFeature,
        featureTogglesFeature,
        inspectorFeature,
      ],
      containerOptions: ContainerOptions(
        maxResolveConcurrency: 10,
        errorHandler: ({required error, required source, required meta}) {
          debugPrint('[$source] Error: $error');
        },
      ),
      logger: PrintLogger(minLevel: LogLevel.debug),
      child: FeatureGraphOverlay(
        enabled: kDebugMode,
        child: layoutRoot(data: null),
      ),
    ),
  );
}
