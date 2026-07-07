import 'package:collection/collection.dart' as cc;
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:petitparser/parser.dart' as pp;

import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/domains/die_domain.dart';
import 'package:roll_feathers/util/color.dart';
import 'parser_definitions.dart';

const int intMaxValue = 9000000000000000;
const int intMinValue = -9000000000000000;

final Logger _rtLog = Logger('ResultTargets');

typedef ActionTarget =
    Future<void> Function({
      required DieDomain dd,
      List<GenericDie>? allDice,
      List<GenericDie>? resultDice,
      required List<GenericDie> defaultDice,
      List<String> args,
    });

final pp.Parser<bool> startIntervalClosedParser =
    ["[".toParser().map((_) => true), "(".toParser().map((_) => false)].toChoiceParser();
final pp.Parser<bool> endIntervalClosedParser =
    ["]".toParser().map((_) => true), ")".toParser().map((_) => false)].toChoiceParser();

final pp.Parser<RollResultRange> resultRangeParser = pp
    .seq5<bool, num, String, num, bool>(
      startIntervalClosedParser,
      [numberParser, "*".toParser().map((e) => intMinValue)].toChoiceParser(),
      ":".toParser(),
      [numberParser, "*".toParser().map((e) => intMaxValue)].toChoiceParser(),
      endIntervalClosedParser,
    )
    .map5(
      ((bool startInclusive, num minVal, _, num maxVal, bool endInclusive) =>
          RollResultRange(startInclusive, minVal.round(), maxVal.round(), endInclusive)),
    );

// Limit args to safe tokens so we don't greedily consume the next block keyword.
final pp.Parser<ResultTargetFunction> resultTarget = (() {
  final List<pp.Parser<ResultTargetFunction>> choices = [];

  // Use horizontal whitespace (spaces/tabs) to separate args so we don't
  // accidentally consume the next line's leading keyword (e.g., 'on').
  final pp.Parser hspace = pp.pattern(' \t').plus();

  // Sentinel: stop argument capture before a reserved keyword that would start
  // a new statement or at end-of-line. This prevents consuming the next block.
  final pp.Parser reservedWordStart = [
    'use', 'on', 'aggregate', 'make', 'with', 'define', 'result', 'selection', 'for', 'roll'
  ]
      .map((w) => w.toParser())
      .toChoiceParser();
  // Reserved keyword at a word boundary: start of line or after whitespace
  final pp.Parser reservedSentinel = (
    pp.pattern(' \t').star() & reservedWordStart & pp.pattern(' \t').plus()
  ).flatten();
  final pp.Parser lineOrReservedSentinel = pp.newline().or(reservedSentinel).or(pp.endOfInput());

  // Special-case parser for 'action sequence' to capture the entire rest-of-line
  // as arguments (after the action name). This avoids dropping color words when
  // token-by-token parsing gets interrupted. We then split by horizontal
  // whitespace and let the action handler filter unknown tokens.
  final pp.Parser<ResultTargetFunction> actionSequenceP = (
    ResultTargetType.action.key.toParser().map((rt) => ResultTargetType.byKey(rt)),
    pp.whitespace().star(),
    'sequence'.toParser(),
    // Consume at least one horizontal space before args (if any)
    hspace.optional(),
    // Capture up to reserved keyword/newline/EOF WITHOUT consuming it
    pp.any().starLazy(lineOrReservedSentinel).flatten(),
  ).toSequenceParser().map((entry) {
    final String rest = (entry.$5).trimRight();
    // Split on spaces/tabs, drop empties
    List<String> toks = rest.isEmpty
        ? <String>[]
        : rest.split(RegExp(r"[\t ]+")).where((s) => s.isNotEmpty).toList();
    // ignore: avoid_print
    _rtLog.fine(() => '[RESULT_TARGET_PARSE] action=sequence args=${toks.join(" ")}');
    return ResultTargetFunction(
      rtType: entry.$1!,
      target: 'sequence',
      args: toks,
    );
  });
  choices.add(actionSequenceP);

  // Webhook: "webhook [GET|POST] <url-to-end-of-line>"
  // Method prefix is optional; defaults to POST. URL stored in action, method in args[0].
  final webhookP = pp
      .seq3(
        ResultTargetType.webhook.key.toParser(),
        pp.whitespace().plus(),
        // The URL (+ optional ` with <name>`) is the whole rest of the line — don't
        // stop at reserved words that legitimately appear inside a URL (e.g. /roll).
        pp.any().plusLazy(pp.newline().or(pp.endOfInput())).flatten(),
      )
      .map3((_, __, rest) {
        final String trimmed = rest.trimRight();
        final parts = trimmed.split(RegExp(r'\s+'));
        final String method;
        String remainder; // "<url> [with <payloadName>]"
        if (parts.isNotEmpty &&
            (parts.first.toUpperCase() == 'GET' || parts.first.toUpperCase() == 'POST')) {
          method = parts.first.toUpperCase();
          remainder = trimmed.substring(parts.first.length).trimLeft();
        } else {
          method = 'POST';
          remainder = trimmed;
        }
        // Optional trailing " with <payloadName>" (URLs can't contain a bare " with ").
        String url = remainder;
        String? payloadName;
        final withMatch = RegExp(r'\s+with\s+(.+)$').firstMatch(remainder);
        if (withMatch != null) {
          url = remainder.substring(0, withMatch.start).trimRight();
          payloadName = withMatch.group(1)!.trim();
        }
        return ResultTargetFunction(
          rtType: ResultTargetType.webhook,
          target: url,
          args: payloadName == null ? [method] : [method, payloadName],
        );
      });
  choices.add(webhookP);

  // Discord: "discord <url-to-end-of-line>" — DEPRECATED sugar for
  // `webhook <url> with discord`. Still parses; tagged deprecated so the UI can
  // offer a one-tap migrate.
  final discordP = pp
      .seq3(
        ResultTargetType.discord.key.toParser(),
        pp.whitespace().plus(),
        pp.any().plusLazy(pp.newline().or(pp.endOfInput())).flatten(),
      )
      .map3((_, __, rest) {
        return ResultTargetFunction(
          rtType: ResultTargetType.discord,
          target: rest.trim(),
          args: [],
          deprecated: true,
        );
      });
  choices.add(discordP);

  final actionP = (
    ResultTargetType.action.key.toParser().map((rt) => ResultTargetType.byKey(rt)),
    pp.whitespace().star(),
    resultActionMap.keys.map((a) => a.toParser()).toChoiceParser(),
    // Only allow horizontal whitespace before args on the SAME line
    hspace.optional(),
    // Capture up to reserved keyword/newline/EOF WITHOUT consuming it
    pp.any().starLazy(lineOrReservedSentinel).flatten(),
  ).toSequenceParser().map(
    (entry) {
      final String rest = (entry.$5).trimRight();
      List<String> args = rest.isEmpty
          ? <String>[]
          : rest.split(RegExp(r"[\t ]+")).where((s) => s.isNotEmpty).toList();
      final action = entry.$3;
      // ignore: avoid_print
      _rtLog.fine(() => '[RESULT_TARGET_PARSE] action=$action args=${args.join(" ")}');
      return ResultTargetFunction(
        rtType: entry.$1!,
        target: action,
        args: args,
      );
    },
  );
  choices.add(actionP);

  return choices.toChoiceParser();
})();

final pp.Parser<ScriptResultTarget> resultDef = pp
    .seq5("on".toParser(), pp.whitespace().star(), resultRangeParser, pp.whitespace().star(), resultTarget)
    .map((entry) => ScriptResultTarget(entry.$3, entry.$5));

enum ResultTargetType {
  webhook("webhook"),
  discord("discord"),
  action("action");

  final String key;

  const ResultTargetType(this.key);

  static ResultTargetType? byKey(String key) {
    return ResultTargetType.values.firstWhereOrNull((t) => t.key == key);
  }
}

class ResultTargetFunction {
  ResultTargetType rtType;
  String target;
  List<String> args;

  /// True for deprecated syntax (the `discord` keyword) — surfaced in the UI so
  /// rules can be migrated to `webhook <url> with discord`.
  bool deprecated;

  ResultTargetFunction({required this.rtType, required this.target, required this.args, this.deprecated = false});
}

class ScriptResultTarget {
  RollResultRange resultRange;
  ResultTargetFunction targetFunction;

  ScriptResultTarget(this.resultRange, this.targetFunction);
}

class RollResultRange {
  late final bool startInclusive;
  late final int start;
  late final int end;
  late final bool endInclusive;

  RollResultRange(this.startInclusive, this.start, this.end, this.endInclusive);

  int getStart() {
    return startInclusive ? start : start + 1;
  }

  int getEnd() {
    return endInclusive ? end : end - 1;
  }

  bool valueIn(int value) {
    return getStart() <= value && value <= getEnd();
  }
}

Future<void> blink({
  required DieDomain dd,
  List<GenericDie>? allDice,
  List<GenericDie>? resultDice,
  required List<GenericDie> defaultDice,
  List<String> args = const [],
}) async {
  final String? argColorName = args.firstOrNull;
  final Color resolvedArgColor = argColorName != null ? (colorMap[argColorName] ?? Colors.white) : Colors.white;
  await Future.wait((resultDice ?? allDice ?? []).map((die) {
    final Color blinkColor = argColorName != null ? resolvedArgColor : (die.blinkColor ?? Colors.white);
    _rtLog.finer(() => "[blink] die=${die.dieId} arg=${argColorName ?? '-'} color=${blinkColor.toARGB32()}");
    return dd.blink(blinkColor, die);
  }));
}

Future<void> sequence({
  required DieDomain dd,
  List<GenericDie>? allDice,
  List<GenericDie>? resultDice,
  required List<GenericDie> defaultDice,
  List<String> args = const [],
  Duration blinkInterval = const Duration(milliseconds: 500),
}) async {
  // Determine loop count from first arg if numeric; otherwise default to 1.
  final int loops = args.isNotEmpty ? (int.tryParse(args.first) ?? 1) : 1;

  // Build the color list from remaining args that are known color names.
  // If the first arg is numeric, treat it as loops and use the rest as colors;
  // otherwise, treat all args as color candidates. This avoids dropping the first
  // color when loops are omitted (e.g., "sequence red blue").
  final bool firstIsNumber = args.isNotEmpty && int.tryParse(args.first) != null;
  final Iterable<String> colorCandidates = firstIsNumber ? args.skip(1) : args;
  final List<String> providedColors = colorCandidates
      .where((tok) => colorMap.containsKey(tok))
      .toList();

  // If no valid colors are provided, default to white per requirement.
  final List<String> defaultColors = ["white"];
  final List<String> colorStrings = providedColors.isEmpty ? defaultColors : providedColors;

  // Expand steps once: loops × colors
  final List<String> steps = <String>[];
  for (int i = 0; i < loops; i++) {
    steps.addAll(colorStrings);
  }

  final List<GenericDie> dice = (resultDice ?? allDice ?? []);

  // Debug logs
  _rtLog.fine(() => "[sequence] loops=$loops colors=${colorStrings.join(', ')} args='${args.join(' ')}'");
  for (final die in dice) {
    _rtLog.fine(() => "[sequence] selected die=${die.dieId}");
  }

  for (final cs in steps) {
    final Color c = colorMap[cs] ?? Colors.white;

    // Option B: dispatch blinks concurrently for this step, then wait for all
    _rtLog.finer(() => "[sequence] step color=$cs:${c.r},${c.g},${c.b} dice=${dice.length}");
    await Future.wait(dice.map((die) async {
      _rtLog.finer(() => "[sequence] die=${die.dieId} blink=$cs:${c.r},${c.g},${c.b}");
      await dd.blink(c, die, blinkCount: 1);
    }));

    // Inter-step delay to avoid hardware/SDK coalescing
    await Future.delayed(blinkInterval);
  }
}

Map<String, ActionTarget> resultActionMap = {"blink": blink, "sequence": sequence};
