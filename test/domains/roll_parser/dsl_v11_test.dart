import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// These are here to ensure the file compiles against current sources.
// Actual assertions will be enabled once the v1.1 parser is implemented.
// ignore: unused_import
import 'package:roll_feathers/domains/roll_parser/parser.dart';

String loadFixture(String name) {
  final file = File('test/fixtures/$name');
  return file.readAsStringSync();
}

void main() {
  group('DSL v1.1 fixtures (pending implementation)', () {
    test('extremes.rule loads', () {
      final script = loadFixture('extremes.rule');
      expect(script.isNotEmpty, true);
    });

    test('d20_check.rule loads', () {
      final script = loadFixture('d20_check.rule');
      expect(script.isNotEmpty, true);
    });

    test('scaled_top.rule loads', () {
      final script = loadFixture('scaled_top.rule');
      expect(script.isNotEmpty, true);
    });

    test('percentile_bands.rule loads', () {
      final script = loadFixture('percentile_bands.rule');
      expect(script.isNotEmpty, true);
    });

    test('doubles_or_matches.rule loads', () {
      final script = loadFixture('doubles_or_matches.rule');
      expect(script.isNotEmpty, true);
    });

    test('tracker_threshold.rule loads', () {
      final script = loadFixture('tracker_threshold.rule');
      expect(script.isNotEmpty, true);
    });

    test('multi_use_same_selection.rule loads', () {
      final script = loadFixture('multi_use_same_selection.rule');
      expect(script.isNotEmpty, true);
    });

    test('deep_derivation_chain.rule loads', () {
      final script = loadFixture('deep_derivation_chain.rule');
      expect(script.isNotEmpty, true);
    });
  }, skip: 'Pending implementation of DSL v1.1 parser/evaluator');
}
