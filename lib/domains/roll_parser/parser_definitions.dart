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
