import 'package:petitparser/parser.dart' as pp;

final pp.Parser<bool> booleanParser =
    ["true".toParser().map((b) => true), "false".toParser().map((b) => false)].toChoiceParser();

final pp.Parser<num> integerParser = pp.digit().plus().flatten().map(num.parse);
final pp.Parser<num> numberParser = pp
    .digit()
    .plus()
    .seq(pp.char('.').seq(pp.digit().plus()).optional())
    .flatten()
    .trim()
    .map(num.parse);

final pp.Parser<String> alphanumericParser = pp.pattern('a-zA-Z0-9_').starString("defineName");
final pp.Parser<String> wholeWordParser = pp.pattern('a-zA-Z0-9_').plus().flatten();
final pp.Parser<String> variableParser = pp.seq2("\$".toParser(), pp.pattern('a-zA-Z0-9_').star()).flatten();
final pp.Parser numberOrStarParser = [numberParser, "*".toParser()].toChoiceParser();
final pp.Parser numStarVarParser = [numberParser, "*".toParser(), variableParser].toChoiceParser();

// ruleId: first char alphanumeric/underscore, subsequent may also include dash
final pp.Parser<String> ruleIdParser =
    (pp.pattern('a-zA-Z0-9_') & pp.pattern('a-zA-Z0-9_-').star()).flatten();

final pp.Parser<String> _quotedStringParser = pp
    .seq3(pp.char('"'), pp.any().starLazy(pp.char('"')).flatten(), pp.char('"'))
    .map3((_, content, __) => content);

// Parses "define <id> [\"Display Name\"] " and returns (ruleId, displayName?).
// Consumed trailing whitespace so "for roll" follows directly.
final pp.Parser<(String, String?)> defineHeaderParser = pp
    .seq5(
      pp.string("define "),
      ruleIdParser,
      pp.whitespace().star(),
      _quotedStringParser.optional(),
      pp.whitespace().star(),
    )
    .map5((_, name, __, displayName, ___) => (name, displayName));

/// Returns the quoted display name from the define line, or null if absent/unparseable.
String? parseDisplayName(String script) {
  try {
    return defineHeaderParser.parse(script.trim()).value.$2;
  } catch (_) {
    return null;
  }
}
