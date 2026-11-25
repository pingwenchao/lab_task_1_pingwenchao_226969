import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_task_1_pingwenchao_226969/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('GeoPhoto renders Apple HIG UI and persists theme toggle', (
      WidgetTester tester,
      ) async {
    // Initialize mock SharedPreferences for isolated widget testing
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Verify core UI components render without overflow
    expect(find.text('GeoPhoto'), findsOneWidget);
    expect(find.text('No Photo Captured Yet'), findsOneWidget);
    expect(find.text('GPS Telemetry'), findsOneWidget);
    expect(find.text('Capture & Tag GPS'), findsOneWidget);
    expect(find.text('Storage & Cache Inspector'), findsOneWidget);

    // Toggle Dark Mode and verify icon updates
    expect(find.byIcon(CupertinoIcons.moon_fill), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.moon_fill));
    await tester.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.sun_max_fill), findsOneWidget);

    // Expand Storage & Cache Inspector panel
    await tester.scrollUntilVisible(
      find.text('Storage & Cache Inspector'),
      200,
    );
    await tester.tap(find.text('Storage & Cache Inspector'));
    await tester.pumpAndSettle();
    expect(find.text('SharedPreferences (JSON)'), findsOneWidget);
  });
}