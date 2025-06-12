import 'package:flutter/material.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:collection/collection.dart' as cc;

import '../../dice_sdks/dice_sdks.dart';
import '../../util/color.dart';
import '../roll_domain.dart';

typedef ResultTarget =
    Future<void> Function({
      required DieDomain dd,
      required RollDomain rd,
      List<GenericDie>? allDice,
      List<GenericDie>? resultDice,
      List<String> args,
    });

Future<void> blink({
  required DieDomain dd,
  required RollDomain rd,
  List<GenericDie>? allDice,
  List<GenericDie>? resultDice,
  List<String> args = const [],
}) async {
  for (GenericDie die in (resultDice ?? allDice ?? [])) {
    Color blinkColor = colorMap[args.firstOrNull] ?? die.blinkColor ?? Colors.white;
    dd.blink(blinkColor, die);
  }
}

Future<void> sequence({
  required DieDomain dd,
  required RollDomain rd,
  List<GenericDie>? allDice,
  List<GenericDie>? resultDice,
  List<String> args = const [],
}) async {
  int loops = int.tryParse(args[0]) ?? 1;
  var defaultColors = ["red", "green", "blue"];
  for (GenericDie die in (resultDice ?? allDice ?? [])) {
    List<String> colorStrings = args.length < 2 ? defaultColors : args.sublist(1);
    List<String> colorLoops = [];
    for (int i = 0; i < loops; i++) {
      colorLoops.addAll(colorStrings);
    }
    for (var cs in colorLoops) {
      Color c = colorMap[cs] ?? Colors.white;
      await dd.blink(c, die);
    }
  }
}

Map<String, ResultTarget> resultActions = {"blink": blink, "sequence": sequence};

typedef ResultRule = bool Function({List<String> args});

bool ret({List<String> args = const ["false"]}) {
  return bool.tryParse(args[0], caseSensitive: false) ?? false;
}

Map<String, ResultRule> resultRules = {"return": ret};
