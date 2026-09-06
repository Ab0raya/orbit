import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit_mobile/app.dart';
import 'package:orbit_mobile/core/providers.dart';
import 'package:orbit_mobile/features/splash/views/orbit_splash_screen.dart';
import 'storage_test.dart';


void main() {
  testWidgets('OrbitApp displays ConnectionScreen initially', (WidgetTester tester) async {
    final mockStorage = InMemoryStorage();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(mockStorage),
        ],
        child: const OrbitApp(),
      ),
    );

    // Initially displays OrbitSplashScreen
    expect(find.byType(OrbitSplashScreen), findsOneWidget);

    // After splash duration completes, smoothly transitions to ConnectionScreen
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();

    expect(find.byType(OrbitSplashScreen), findsNothing);
    expect(find.text('ORBIT'), findsOneWidget);
    expect(find.text('Connect to PC'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });

}
