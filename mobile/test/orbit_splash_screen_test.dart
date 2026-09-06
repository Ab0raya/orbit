import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/features/splash/views/orbit_splash_screen.dart';

void main() {
  testWidgets('OrbitSplashScreen renders full-screen orbit_splash_screen.png artwork',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OrbitSplashScreen(
          duration: Duration(milliseconds: 1000),
          nextScreen: Scaffold(body: Text('Next Destination')),
        ),
      ),
    );

    // Initial frame renders OrbitSplashScreen
    expect(find.byType(OrbitSplashScreen), findsOneWidget);

    // Verify Scaffold background is pure black
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Colors.black);

    // Verify Image.asset is present with BoxFit.cover
    final imageFinder = find.byType(Image);
    expect(imageFinder, findsOneWidget);
    final imageWidget = tester.widget<Image>(imageFinder);
    expect(imageWidget.fit, BoxFit.cover);
    expect(imageWidget.alignment, Alignment.center);
    final assetImage = imageWidget.image as AssetImage;
    expect(assetImage.assetName, 'assets/images/orbit_splash_screen.png');

    // Verify PopScope has canPop: false to prevent back button from popping splash
    final popScopeFinder = find.byType(PopScope);
    expect(popScopeFinder, findsOneWidget);
    final popScopeWidget = tester.widget<PopScope>(popScopeFinder);
    expect(popScopeWidget.canPop, false);

    // Verify no buttons, spinners, appbars, or extra UI chrome
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);

    // Advance time past duration and allow transition to settle
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    // Verify it transitioned to Next Destination
    expect(find.text('Next Destination'), findsOneWidget);
    // Verify OrbitSplashScreen is no longer in widget tree (replaced via pushReplacement)
    expect(find.byType(OrbitSplashScreen), findsNothing);
  });

  testWidgets('OrbitSplashScreen does not pop when back navigation is attempted',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OrbitSplashScreen(
          duration: Duration(milliseconds: 2000),
          nextScreen: Scaffold(body: Text('Destination Screen')),
        ),
      ),
    );

    // Simulate system back gesture / back button
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pump();

    // OrbitSplashScreen must still be present and not popped
    expect(find.byType(OrbitSplashScreen), findsOneWidget);

    // Now let duration elapse
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pumpAndSettle();

    expect(find.text('Destination Screen'), findsOneWidget);
    expect(find.byType(OrbitSplashScreen), findsNothing);
  });
}
