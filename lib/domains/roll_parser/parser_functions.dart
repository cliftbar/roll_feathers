
// functions
import 'package:collection/collection.dart';

typedef RollAggregate = int Function(List<int> list);

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