import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/ui/app_settings/script_screen.dart';

void main() {
  const withDiscord = '''define r for roll *d*
  make selection @ALL
  use selection @ALL
    aggregate over selection sum
    on result [*:*] discord https://discord.com/api/webhooks/x/y''';

  test('detects the deprecated discord target keyword', () {
    expect(scriptUsesDeprecatedDiscord(withDiscord), isTrue);
  });

  test('does not flag the new `with discord` syntax', () {
    const s = '    on result [*:*] webhook https://x/y with discord';
    expect(scriptUsesDeprecatedDiscord(s), isFalse);
  });

  test('migrate rewrites the discord target to `webhook … with discord`', () {
    final out = migrateDeprecatedDiscord(withDiscord);
    expect(out, contains('webhook https://discord.com/api/webhooks/x/y with discord'));
    expect(scriptUsesDeprecatedDiscord(out), isFalse);
    // other lines untouched
    expect(out, contains('aggregate over selection sum'));
  });
}
