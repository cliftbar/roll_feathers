// functions
import 'package:collection/collection.dart';
import 'package:petitparser/parser.dart' as pp;

typedef RollAggregate = int Function(List<int> list);

/// Parses an aggregate keyword into (name, function). The name is surfaced to
/// webhook payloads as `{{rollType}}`.
final pp.Parser<(String, RollAggregate)> aggregateParsers =
    [
      "sum".toParser().map((f) => ('sum', sum)),
      "min".toParser().map((f) => ('min', min)),
      "max".toParser().map((f) => ('max', max)),
      "avg".toParser().map((f) => ('avg', avg)),
      "count".toParser().map((f) => ('count', count)),
    ].toChoiceParser();

int sum(List<int> list) {
  // return list.fold(0, (a, b) => a + b);
  return list.sum;
}

int min(List<int> list) {
  // return list.reduce((a, b) => a <= b ? a : b);
  return list.min;
}

int max(List<int> list) {
  // return list.reduce((a, b) => a <= b ? b : a);
  return list.max;
}

int avg(List<int> list) {
  // return list.reduce((a, b) => a <= b ? b : a);
  return list.average.round();
}

int count(List<int> list) {
  return list.length;
}
