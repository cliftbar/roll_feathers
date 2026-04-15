import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/dice_sdks.dart';
import 'package:roll_feathers/ui/die_screen/die_list_tile.dart';

void main() {
  testWidgets('DieListTile should not display dieId (UUID)', (tester) async {
    const uuid = '550e8400-e29b-41d4-a716-446655440000';
    final die = VirtualDie(
      dType: GenericDTypeFactory.getKnownChecked('d6'),
      name: 'Test Die',
      dieId: uuid,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DieListTile(
          die: die,
          onTap: () {},
        ),
      ),
    ));

    // Should find the name
    expect(find.textContaining('Test Die'), findsOneWidget);
    // Should NOT find the UUID
    expect(find.textContaining(uuid), findsNothing);
  });

  testWidgets('DieListTile should show "Unknown d6" when name is empty', (tester) async {
    const uuid = '550e8400-e29b-41d4-a716-446655440000';
    // Use StaticVirtualDie or similar if we want to bypass the improved VirtualDie.friendlyName,
    // but better to just test the behavior we want.
    final die = VirtualDie(
      dType: GenericDTypeFactory.getKnownChecked('d6'),
      name: '', // empty name
      dieId: uuid,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DieListTile(
          die: die,
          onTap: () {},
        ),
      ),
    ));

    // Should show "Virtual d6" because VirtualDie.friendlyName was updated
    expect(find.textContaining('Virtual d6'), findsOneWidget);
    // Should NOT find the UUID
    expect(find.textContaining(uuid), findsNothing);
  });
}
