// Mock defs
import 'dart:ui';

import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/domains/roll_domain.dart';

class MockRollDomain extends Mock implements RollDomain {}
class MockDieDomain extends Mock implements DieDomain {}
class MockGenericDie extends Mock implements GenericDie {}
class MockColor extends Mock implements Color {}

void setupLogger(Level level) {
  hierarchicalLoggingEnabled = true;
  Logger.root.level = level;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}');
  });
}