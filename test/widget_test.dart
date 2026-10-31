import 'package:flutter_test/flutter_test.dart';
import 'package:pcmouse/main.dart';

void main() {
  testWidgets('Dashboard loads cleanly smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RemotePcApp());
    expect(find.text('Remote PC Controller'), findsOneWidget);
  });
}
