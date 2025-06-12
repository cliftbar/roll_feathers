import 'package:flutter/material.dart';
import 'package:roll_feathers/domains/die_domain.dart';

import '../../dice_sdks/dice_sdks.dart';
import '../../util/color.dart';
import '../roll_domain.dart';

typedef ResultTarget =
    void Function({
      required DieDomain dd,
      required RollDomain rd,
      List<GenericDie>? allDice,
      List<GenericDie>? resultDice,
      List<String> args,
    });

void blink({
  required DieDomain dd,
  required RollDomain rd,
  List<GenericDie>? allDice,
  List<GenericDie>? resultDice,
  List<String> args = const [],
}) {
  for (GenericDie die in (resultDice ?? allDice ?? [])) {
    Color blinkColor = colorMap[args.firstOrNull] ?? rd.blinkColors[die.dieId] ?? Colors.white;
    dd.blink(blinkColor, die);
  }
}

Map<String, ResultTarget> resultActions = {"blink": blink};

typedef ResultRule = bool Function({List<String> args});

bool ret({List<String> args = const ["false"]}) {
  return bool.tryParse(args[0], caseSensitive: false) ?? false;
}

Map<String, ResultRule> resultRules = {"return": ret};
