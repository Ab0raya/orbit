import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/core/storage/local_storage.dart';
import 'package:orbit_mobile/protocol/models/ai_models.dart';
import 'package:orbit_mobile/protocol/models/pairing_models.dart';
import 'package:orbit_mobile/features/ai/models/ai_message.dart';
import 'package:orbit_mobile/features/ai/widgets/ai_response_markdown.dart';
import 'package:orbit_mobile/features/ai/views/ai_command_center_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FakeStorage implements ILocalStorage {
  String? deviceId;
  PairedDeviceRecord? pairedDevice;
  Map<String, dynamic>? recentConn;

  @override
  Future<String> getOrCreateInstallationDeviceId() async {
    deviceId ??= 'orbit_dev_test_device_123';
    return deviceId!;
  }

  @override
  Future<void> clearPairedDevice() async {
    pairedDevice = null;
  }

  @override
  Future<PairedDeviceRecord?> getPairedDevice() async => pairedDevice;

  @override
  Future<Map<String, dynamic>?> getRecentConnection() async => recentConn;

  @override
  Future<void> savePairedDevice(PairedDeviceRecord record) async {
    pairedDevice = record;
  }

  @override
  Future<void> saveRecentConnection(String host, int port) async {
    recentConn = {'host': host, 'port': port};
  }

  bool _showHiddenFiles = false;

  @override
  Future<void> saveShowHiddenFiles(bool show) async {
    _showHiddenFiles = show;
  }

  @override
  Future<bool> getShowHiddenFiles() async => _showHiddenFiles;
}

void main() {
  group('Milestone 08.6 — Flutter AI Conversation & UX Tests', () {
    test('1. Stable deviceId persistence across calls', () async {
      final storage = FakeStorage();
      final id1 = await storage.getOrCreateInstallationDeviceId();
      final id2 = await storage.getOrCreateInstallationDeviceId();
      expect(id1, equals(id2));
      expect(id1, isNotEmpty);
    });

    test('2. QR payload parsing and validation', () {
      final uriStr = 'orbit://pair/v1?host=192.168.1.50&port=4371&code=123456&expires=9999999999999';
      final payload = OrbitPairingQrPayload.parse(uriStr);

      expect(payload.host, equals('192.168.1.50'));
      expect(payload.port, equals(4371));
      expect(payload.code, equals('123456'));
      expect(payload.version, equals('v1'));
      expect(payload.isExpired, isFalse);
    });

    test('3. Expired QR payload detection', () {
      final pastTimestamp = DateTime.now().millisecondsSinceEpoch - 10000;
      final uriStr = 'orbit://pair/v1?host=127.0.0.1&port=4371&code=654321&expires=$pastTimestamp';
      final payload = OrbitPairingQrPayload.parse(uriStr);

      expect(payload.isExpired, isTrue);
    });

    test('4. Invalid QR payload rejection', () {
      expect(() => OrbitPairingQrPayload.parse('https://example.com'), throwsA(isA<FormatException>()));
      expect(() => OrbitPairingQrPayload.parse('orbit://other'), throwsA(isA<FormatException>()));
      expect(() => OrbitPairingQrPayload.parse('orbit://pair/v1?host=&port=4371&code=123456'), throwsA(isA<FormatException>()));
      expect(() => OrbitPairingQrPayload.parse('orbit://pair/v1?host=127.0.0.1&port=invalid&code=123456'), throwsA(isA<FormatException>()));
      expect(() => OrbitPairingQrPayload.parse('orbit://pair/v1?host=127.0.0.1&port=4371&code=12'), throwsA(isA<FormatException>()));
      expect(OrbitPairingQrPayload.tryParse('invalid_uri'), isNull);
    });

    test('5. PairingPayload includes deviceId', () {
      const payload = PairingPayload(
        code: '123456',
        name: 'iPhone 15',
        platform: 'ios',
        deviceId: 'orbit_dev_stable_abc',
      );

      final json = payload.toJson();
      expect(json['code'], equals('123456'));
      expect(json['deviceId'], equals('orbit_dev_stable_abc'));
    });

    test('6. AiMessage structure and sender properties', () {
      final userMsg = AiMessage(
        id: 'msg_1',
        sender: AiMessageSender.user,
        text: 'Explain README.md',
        contextPath: '/home/user/project',
        timestamp: DateTime.now(),
      );

      expect(userMsg.isUser, isTrue);
      expect(userMsg.isAssistant, isFalse);
      expect(userMsg.text, equals('Explain README.md'));

      final assistantMsg = AiMessage(
        id: 'msg_2',
        sender: AiMessageSender.assistant,
        text: 'This project is Orbit.',
        taskId: 'task_100',
        timestamp: DateTime.now(),
        status: AiMessageStatus.completed,
      );

      expect(assistantMsg.isAssistant, isTrue);
      expect(assistantMsg.isUser, isFalse);
      expect(assistantMsg.taskId, equals('task_100'));
      expect(assistantMsg.status, equals(AiMessageStatus.completed));
    });

    test('7. AiTask response field serialization', () {
      final task = AiTask(
        taskId: 'task_abc',
        projectPath: '/tmp/project',
        status: AiTaskStatus.completed,
        agent: AiAgent.plan,
        readOnly: true,
        startedAt: 1000,
        response: 'Comprehensive architecture explanation',
      );

      final json = task.toJson();
      expect(json['response'], equals('Comprehensive architecture explanation'));

      final restored = AiTask.fromJson(json);
      expect(restored.response, equals('Comprehensive architecture explanation'));
    });

    testWidgets('8. AiResponseMarkdown renders paragraphs and code blocks', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AiResponseMarkdown(
              text: '### Architecture Overview\n\nOrbit connects directly.\n\n```dart\nfinal x = 42;\n```',
            ),
          ),
        ),
      );

      expect(find.textContaining('Architecture Overview'), findsOneWidget);
      expect(find.textContaining('Orbit connects directly'), findsOneWidget);
      expect(find.textContaining('final x = 42;'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('9. AiCommandCenterScreen renders empty state suggestions', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AiCommandCenterScreen(),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('ORBIT AI COMMAND CENTER'), findsOneWidget);
      expect(find.text('Explain README.md'), findsOneWidget);
      expect(find.text('What does this project do?'), findsOneWidget);
    });

    testWidgets('10. AiCommandCenterScreen pre-fills initialPrompt', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AiCommandCenterScreen(
              initialPrompt: 'Explain main.dart',
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Explain main.dart'), findsOneWidget);
    });
  });
}
