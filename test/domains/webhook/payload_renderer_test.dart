import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/domains/webhook/payload_context.dart';
import 'package:roll_feathers/domains/webhook/payload_renderer.dart';
import 'package:roll_feathers/domains/webhook/payload_template.dart';

// Tokens are Mustache-style {{ }} — single braces are literal (JSON uses them).
void main() {
  final ctx = PayloadContext.sample;
  String json(String t) => PayloadRenderer.render(t, ctx, PayloadFormat.json);
  String query(String t) => PayloadRenderer.render(t, ctx, PayloadFormat.form);
  String text(String t) => PayloadRenderer.render(t, ctx, PayloadFormat.text);

  group('scalars', () {
    test('dotted paths; numbers bare, strings quoted by author', () {
      expect(json('{"rule":"{{rule.name}}","total":{{aggregate}}}'),
          '{"rule":"attackRoll","total":18}');
    });
    test('die alias = first result die at top level', () {
      expect(json('{"c":"{{die.name}} rolled {{die.value}}"}'), '{"c":"Gandalf rolled 18"}');
    });
    test('indexed array access', () {
      expect(json('{"x":"{{resultDice.1.name}}"}'), '{"x":"Shadowfax"}');
    });
    test('nested map path + bool', () {
      expect(json('{"s":{{matched.start}},"si":{{matched.startInclusive}}}'), '{"s":15,"si":true}');
    });
  });

  group('loops', () {
    test('json loop joins with comma (normalized)', () {
      expect(json('[{{#resultDice}}{"v":{{die.value}}}{{/resultDice}}]'), '[{"v":18},{"v":11}]');
    });
    test('trailing comma inside the loop block is normalized away', () {
      expect(json('[{{#resultDice}}{"v":{{die.value}}},{{/resultDice}}]'), '[{"v":18},{"v":11}]');
    });
    test('empty collection → valid empty array', () {
      const empty = PayloadContext({'resultDice': []});
      expect(PayloadRenderer.render('[{{#resultDice}}{"v":{{die.value}}}{{/resultDice}}]', empty, PayloadFormat.json), '[]');
    });
    test('loops nest via the `die` scope alias (current item)', () {
      const nested = PayloadContext({
        'groups': [
          {'name': 'A', 'items': [{'v': 1}, {'v': 2}]},
          {'name': 'B', 'items': [{'v': 3}]},
        ],
      });
      expect(
        PayloadRenderer.render(
          '[{{#groups}}{"g":"{{die.name}}","vs":[{{#die.items}}{{die.v}},{{/die.items}}]}{{/groups}}]',
          nested,
          PayloadFormat.json,
        ),
        '[{"g":"A","vs":[1,2]},{"g":"B","vs":[3]}]',
      );
    });
  });

  group('conditional', () {
    test('renders block when present, omits when null', () {
      expect(
        json('[{{#resultDice}}{"n":"{{die.name}}"{{?die.battery}},"b":{{die.battery}}{{/?}}}{{/resultDice}}]'),
        '[{"n":"Gandalf","b":87},{"n":"Shadowfax"}]',
      );
    });
  });

  group('null handling', () {
    test('null numeric in unquoted position → null literal', () {
      expect(json('{"b":{{resultDice.1.battery}}}'), '{"b":null}');
    });
    test('null inside a JSON string → empty, not the literal word null', () {
      // Shadowfax (resultDice.1) has a null battery.
      expect(json('{"msg":"battery {{resultDice.1.battery}} pct"}'), '{"msg":"battery  pct"}');
    });
  });

  group('escaping', () {
    test('json escapes string contents, stays valid', () {
      const c = PayloadContext({'x': 'He said "hi"\nok'});
      expect(PayloadRenderer.render('{"c":"{{x}}"}', c, PayloadFormat.json), '{"c":"He said \\"hi\\"\\nok"}');
    });
    test('query url-encodes values (not keys)', () {
      const c = PayloadContext({'msg': 'a b&c'});
      expect(PayloadRenderer.render('text={{msg}}', c, PayloadFormat.form), 'text=a+b%26c');
    });
  });

  group('query mode', () {
    test('flat params', () {
      expect(query('rule={{rule.name}}&aggregate={{aggregate}}'), 'rule=attackRoll&aggregate=18');
    });
    test('loop → repeated params joined with &', () {
      expect(query('{{#resultDice}}die[]={{die.value}}{{/resultDice}}'), 'die[]=18&die[]=11');
    });
  });

  group('text mode', () {
    test('raw substitution, no escaping', () {
      expect(text('{{die.name}} rolled {{die.value}}'), 'Gandalf rolled 18');
    });
  });

  group('xml mode', () {
    test('escapes values and concatenates loop iterations', () {
      const c = PayloadContext({
        'aggregate': 3,
        'resultDice': [
          {'name': 'A<b>', 'value': 1},
          {'name': 'C&D', 'value': 2},
        ],
      });
      final out = PayloadRenderer.render(
        '<roll total="{{aggregate}}">{{#resultDice}}<die>{{die.name}}</die>{{/resultDice}}</roll>',
        c,
        PayloadFormat.xml,
      );
      expect(out, '<roll total="3"><die>A&lt;b&gt;</die><die>C&amp;D</die></roll>');
    });
  });

  group('convenience tokens', () {
    test('count / names / values', () {
      expect(json('{"n":{{resultDice.count}}}'), '{"n":2}');
      expect(text('{{resultDice.names}}'), 'Gandalf,Shadowfax');
      expect(text('{{resultDice.values}}'), '18,11');
    });
  });

  group('pretty vs minified', () {
    test('default minifies; pretty indents', () {
      expect(json('{ "a" : 1 }'), '{"a":1}');
      final pretty = PayloadRenderer.render('{"a":1}', ctx, PayloadFormat.json, pretty: true);
      expect(pretty.contains('\n'), isTrue);
    });
  });

  group('errors', () {
    test('unbalanced loop throws', () {
      expect(() => json('[{{#resultDice}}{"v":{{die.value}}}]'), throwsA(isA<PayloadRenderException>()));
    });
    test('invalid JSON output throws', () {
      expect(() => json('{"a":}'), throwsA(isA<PayloadRenderException>()));
    });
  });
}
