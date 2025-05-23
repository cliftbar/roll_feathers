import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:roll_feathers/repositories/app_repository.dart';
import 'package:roll_feathers/services/app_service.dart';
import 'package:roll_feathers/ui/roll_feathers_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterBluePlus.setLogLevel(LogLevel.info, color: true);

  // create the app factory to ensure instantiation
  RollFeatherApp app = await RollFeatherApp.create(AppRepository(AppService()));

  runApp(app);
}
