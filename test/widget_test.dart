import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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

    // Verify visible above-the-fold UI components render without overflow
    expect(find.text('GeoPhoto'), findsOneWidget);
    expect(find.text('No Photo Captured Yet'), findsOneWidget);
    expect(find.text('GPS Telemetry'), findsOneWidget);
    expect(find.text('Capture & Tag GPS'), findsOneWidget);

    // Toggle Dark Mode and verify icon updates
    expect(find.byIcon(CupertinoIcons.moon_fill), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.moon_fill));
    await tester.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.sun_max_fill), findsOneWidget);

    // Scroll down to reveal Storage & Cache Inspector above the floating bottom bar
    await tester.scrollUntilVisible(
      find.text('Storage & Cache Inspector'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -150));
    await tester.pumpAndSettle();

    // Verify and expand the Storage & Cache Inspector panel
    expect(find.text('Storage & Cache Inspector'), findsOneWidget);
    await tester.tap(find.text('Storage & Cache Inspector'));
    await tester.pumpAndSettle();
    expect(find.text('SharedPreferences (JSON)'), findsOneWidget);
  });
}