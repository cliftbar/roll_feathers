import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:roll_feathers/di/di.dart';
import 'package:roll_feathers/ui/roll_feathers_app.dart';

void main() async {
  hierarchicalLoggingEnabled = true;
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}');
  });
  FlutterBluePlus.setLogLevel(LogLevel.warning);

  WidgetsFlutterBinding.ensureInitialized();

  DiWrapper di = await DiWrapper.initDi();

  // create the app factory to ensure instantiation
  RollFeatherApp app = await RollFeatherApp.create(di);

  runApp(app);
}
