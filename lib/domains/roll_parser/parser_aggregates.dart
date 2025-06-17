// functions
import 'package:collection/collection.dart';
import 'package:petitparser/parser.dart' as pp;

typedef RollAggregate = int Function(List<int> list);

final pp.Parser<RollAggregate> aggregateParsers =
    [
      "sum".toParser().map((f) => sum),
      "min".toParser().map((f) => min),
      "max".toParser().map((f) => max),
      "avg".toParser().map((f) => avg),
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
