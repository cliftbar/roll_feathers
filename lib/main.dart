import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/ui/roll_feathers_app.dart';

void main() async {
  hierarchicalLoggingEnabled = true;
  Logger.root.level = Level.INFO;
  Logger('RuleEvaluator').level = Level.FINER;
  Logger('ResultTargets').level = Level.FINER;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}');
  });

  WidgetsFlutterBinding.ensureInitialized();

  // Render immediately so the window shows content instead of a black frame
  // while async init (HA service, BLE, HTTP server, SharedPreferences) completes.
  runApp(const _SplashApp());

  DiWrapper di = await DiWrapper.initDi();
  RollFeatherApp app = await RollFeatherApp.create(di);
  runApp(app);
}

class _SplashApp extends StatelessWidget {
  const _SplashApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
