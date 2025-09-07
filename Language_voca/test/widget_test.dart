import 'package:flutter_test/flutter_test.dart';
import 'package:study_tool_fr1/main.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App should build and show initial UI', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Allow the app to settle.
    await tester.pumpAndSettle();

    // Verify that the main screen title is displayed.
    expect(find.text('Our study folders'), findsOneWidget);

    // Verify that at least one of the language folders is present.
    expect(find.text('English'), findsOneWidget);

    // Verify that the guestbook section is present.
    expect(find.text('Guestbook'), findsOneWidget);
  });
}
