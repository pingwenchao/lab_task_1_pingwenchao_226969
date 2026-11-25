import 'package:flutter_test/flutter_test.dart';
import 'package:lab_task_1_pingwenchao_226969/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('GeoPhotoHomePage renders initial UI elements', (WidgetTester tester) async {
    // Initialize mock SharedPreferences storage for widget testing
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Verify core UI elements are present on startup
    expect(find.text('GeoPhoto Cache'), findsOneWidget);
    expect(find.text('No Photo Captured Yet'), findsOneWidget);
    expect(find.text('Capture & Tag GPS'), findsOneWidget);
  });
}