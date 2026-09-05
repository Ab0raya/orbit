import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit_mobile/features/ai/widgets/orbit_ai_header.dart';
import 'package:orbit_mobile/features/ai/widgets/ai_conversations_history_sheet.dart';
import 'package:orbit_mobile/features/ai/controllers/ai_conversation_controller.dart';
import 'package:orbit_mobile/features/ai/models/ai_conversation_models.dart';
import 'package:orbit_mobile/features/ai/views/ai_command_center_screen.dart';
import 'package:orbit_mobile/protocol/models/ai_context.dart';

void main() {
  group('Minimal Orbit AI Command Bar & Header Tests', () {
    testWidgets('1. OrbitAiHeader renders at 56px height with minimal identity and status', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: OrbitAiHeader(
              showLeading: true,
              isWorking: false,
              activeTaskCount: 9,
              onOpenHistory: () {},
              onNewChat: () {},
              onOpenTasks: () {},
            ),
            body: const SizedBox(),
          ),
        ),
      );

      final header = tester.widget<OrbitAiHeader>(find.byType(OrbitAiHeader));
      expect(header.preferredSize.height, equals(56.0));

      expect(find.text('ORBIT AI'), findsOneWidget);
      expect(find.text('READY'), findsOneWidget);
      expect(find.text('9 ACTIVE'), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    });

    testWidgets('2. AiControlBar renders the three compact controls in a single row', (tester) async {
      bool modelTapped = false;
      bool contextTapped = false;
      bool modeTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiControlBar(
              modelLabel: 'Default',
              onOpenModelPicker: () => modelTapped = true,
              contextLabel: 'No context',
              onOpenContextPicker: () => contextTapped = true,
              isPlan: true,
              onOpenModePicker: () => modeTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Default'), findsOneWidget);
      expect(find.text('No context'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);

      await tester.tap(find.text('Default'));
      expect(modelTapped, isTrue);

      await tester.tap(find.text('No context'));
      expect(contextTapped, isTrue);

      await tester.tap(find.text('Plan'));
      expect(modeTapped, isTrue);
    });

    testWidgets('3. Responsive layout without overflow across 320px, 360px, 390px, 430px', (tester) async {
      final widths = [320.0, 360.0, 390.0, 430.0];

      for (final width in widths) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;

        // Test Header alone
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: OrbitAiHeader(
                showLeading: true,
                isWorking: true,
                activeTaskCount: 3,
                onOpenHistory: () {},
                onNewChat: () {},
                onOpenTasks: () {},
              ),
              body: const SizedBox(),
            ),
          ),
        );
        await tester.pump();
        final excHeader = tester.takeException();

        // Test ControlBar alone
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AiControlBar(
                modelLabel: 'big-pickle',
                onOpenModelPicker: () {},
                contextLabel: 'Project: orbit',
                onOpenContextPicker: () {},
                isPlan: false,
                onOpenModePicker: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        final excBar = tester.takeException();

        expect(excHeader, isNull, reason: 'Header layout overflow at width $width');
        expect(excBar, isNull, reason: 'ControlBar layout overflow at width $width');
        expect(find.text('big-pickle'), findsOneWidget);
        expect(find.text('Build'), findsOneWidget);
      }

      addTearDown(() => tester.view.resetPhysicalSize());
    });

    testWidgets('4. AiModePickerSheet displays Plan and Build options and calls callback', (tester) async {
      bool? selectedPlan;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AiModePickerSheet.show(
                    context,
                    isPlan: true,
                    onSelected: (val) => selectedPlan = val,
                  );
                },
                child: const Text('Open Mode Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Mode Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('SELECT EXECUTION MODE'), findsOneWidget);
      expect(find.text('PLAN'), findsOneWidget);
      expect(find.text('Read-only · Safe, no file changes'), findsOneWidget);
      expect(find.text('BUILD'), findsOneWidget);
      expect(find.text('Execute · Allows file changes'), findsOneWidget);

      await tester.tap(find.text('BUILD'));
      await tester.pumpAndSettle();

      expect(selectedPlan, isFalse);
    });

    testWidgets('5. AiCommandCenterScreen has ONE execution-mode control, no duplication at composer', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: AiCommandCenterScreen(
              initialContext: AiContext.none(),
            ),
          ),
        ),
      );

      await tester.pump();

      // Control row has Plan
      expect(find.text('Plan'), findsOneWidget);

      // Composer has Ask Orbit input and Send button, but NO duplicate Plan/Build selector
      expect(find.textContaining('Ask Orbit'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.text('BUILD · EXECUTE'), findsNothing);
      expect(find.text('PLAN · READ-ONLY'), findsNothing);
    });

    testWidgets('6. AiConversationsHistorySheet renders without pixel overflow across 320px, 360px, 390px, 430px', (tester) async {
      final sampleConversations = [
        const OrbitConversation(
          id: 'conv_long',
          title: 'A very lengthy conversation title that might wrap or cause RenderFlex overflow across small screens',
          createdAt: 1700000000,
          updatedAt: 1700000500,
          projectPath: '/very/deeply/nested/directory/structure/my_extraordinarily_long_project_name',
          modelId: 'openrouter/anthropic/claude-3.5-sonnet-latest-2026-experimental',
          messageCount: 42,
        ),
        const OrbitConversation(
          id: 'conv_normal',
          title: 'Implement Minimal AI Command Center',
          createdAt: 1700000000,
          updatedAt: 1700000200,
          projectPath: '/projects/orbit',
          modelId: 'big-pickle',
          messageCount: 6,
        ),
      ];

      final fakeState = AiConversationState(
        conversations: sampleConversations,
      );

      for (final width in [320.0, 360.0, 390.0, 430.0]) {
        tester.view.physicalSize = Size(width, 844.0);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              aiConversationControllerProvider.overrideWith(
                (ref) => _FakeConversationController(fakeState),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: AiConversationsHistorySheet(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final exc = tester.takeException();
        expect(exc, isNull, reason: 'Pixel overflow in history sheet at width $width');
        expect(find.text('CONVERSATION HISTORY'), findsOneWidget);
        expect(find.text('New Chat'), findsOneWidget);
      }

      addTearDown(() => tester.view.resetPhysicalSize());
    });

    testWidgets('7. Tapping history button in AiCommandCenterScreen opens reformed history sheet', (tester) async {
      final sampleConversations = [
        const OrbitConversation(
          id: 'conv_1',
          title: 'Initial architectural review',
          createdAt: 1700000000,
          updatedAt: 1700000200,
          projectPath: '/projects/orbit',
          modelId: 'big-pickle',
        ),
      ];

      final fakeState = AiConversationState(
        conversations: sampleConversations,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiConversationControllerProvider.overrideWith(
              (ref) => _FakeConversationController(fakeState),
            ),
          ],
          child: MaterialApp(
            home: AiCommandCenterScreen(
              initialContext: AiContext.none(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap history button in header
      await tester.tap(find.byIcon(Icons.history));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // History sheet is shown
      expect(find.text('CONVERSATION HISTORY'), findsOneWidget);
      expect(find.text('Initial architectural review'), findsOneWidget);
      expect(find.text('New Chat'), findsOneWidget);

      // Tap close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // History sheet is dismissed
      expect(find.text('CONVERSATION HISTORY'), findsNothing);
    });
  });
}

class _FakeConversationController extends StateNotifier<AiConversationState>
    implements AiConversationController {
  _FakeConversationController(super.state);

  @override
  Future<void> loadConversations() async {}

  @override
  Future<void> loadProviders() async {}

  @override
  Future<void> loadModels() async {}

  @override
  void clearActiveConversation() {
    state = state.copyWith(clearActiveConversation: true);
  }

  @override
  Future<void> searchConversations(String query) async {
    state = state.copyWith(searchQuery: query);
  }

  @override
  Future<bool> deleteConversation(
    String id, {
    bool deleteSession = false,
  }) async {
    final updated = state.conversations.where((c) => c.id != id).toList();
    state = state.copyWith(conversations: updated);
    return true;
  }

  @override
  Future<OrbitConversationDetail?> selectConversation(String id) async {
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
