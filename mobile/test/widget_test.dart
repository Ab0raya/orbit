import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit_mobile/app.dart';
import 'package:orbit_mobile/core/providers.dart';
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

    await tester.pumpAndSettle();

    expect(find.text('ORBIT'), findsOneWidget);
    expect(find.text('Connect to PC'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });
}
