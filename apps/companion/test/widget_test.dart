import 'package:dekereke_companion/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shell renders all three areas and navigates', (tester) async {
    await tester.pumpWidget(const CompanionApp());

    expect(find.text('Health check'), findsOneWidget);
    expect(find.text('Database health check'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.textContaining('checkpoint automatically'), findsOneWidget);

    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();
    expect(find.textContaining('one-time invite link'), findsOneWidget);
  });

  testWidgets('health screen shows the open button, no premature results',
      (tester) async {
    await tester.pumpWidget(const CompanionApp());
    expect(find.text('Open database…'), findsOneWidget);
    expect(find.text('Everything looks good!'), findsNothing);
  });
}
