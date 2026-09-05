import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/features/ai/models/ai_conversation_models.dart';

// Guards the backend contract: Rust serializes camelCase
// (serde rename_all). snake_case is accepted only as legacy fallback.
void main() {
  group('OrbitConversation decoding (backend camelCase payload)', () {
    Map<String, dynamic> backendPayload() => {
          'id': 'conv_123',
          'title': 'Hello',
          'createdAt': 1788620000,
          'updatedAt': 1788620100,
          'projectPath': '/home/aburaya/orbit',
          'directoryPath': null,
          'contextType': 'project',
          'openCodeSessionId': 'ses_abc123',
          'providerId': 'openrouter',
          'modelId': 'openrouter/openrouter/free',
          'status': 'active',
          'lastMessagePreview': 'hi',
          'messageCount': 2,
        };

    test('restores session, provider and model ids', () {
      final conv = OrbitConversation.fromJson(backendPayload());
      expect(conv.openCodeSessionId, 'ses_abc123');
      expect(conv.providerId, 'openrouter');
      expect(conv.modelId, 'openrouter/openrouter/free');
      expect(conv.createdAt, 1788620000);
      expect(conv.messageCount, 2);
    });

    test('legacy snake_case still decodes', () {
      final conv = OrbitConversation.fromJson({
        'id': 'c',
        'created_at': 1,
        'updated_at': 2,
        'open_code_session_id': 'ses_x',
        'provider_id': 'p',
        'model_id': 'm',
        'message_count': 0,
      });
      expect(conv.openCodeSessionId, 'ses_x');
      expect(conv.providerId, 'p');
      expect(conv.modelId, 'm');
    });

    test('detail restores messages with model ids', () {
      final detail = OrbitConversationDetail.fromJson({
        ...backendPayload(),
        'messages': [
          {
            'id': 'm1',
            'conversationId': 'conv_123',
            'role': 'assistant',
            'content': 'hi',
            'createdAt': 1788620100,
            'status': 'completed',
            'modelId': 'openrouter/openrouter/free',
            'activities': [],
          },
        ],
      });
      expect(detail.messages, hasLength(1));
      expect(detail.messages.first.modelId, 'openrouter/openrouter/free');
      expect(detail.summary.modelId, 'openrouter/openrouter/free');
    });
  });

  group('OrbitModelSummary / OrbitProviderSummary decoding', () {
    test('model catalog keeps real ids', () {
      final m = OrbitModelSummary.fromJson({
        'modelId': 'openrouter/openrouter/free',
        'providerId': 'openrouter',
        'name': 'free',
        'contextWindow': 128000,
        'supportsTools': true,
      });
      expect(m.id, 'openrouter/openrouter/free');
      expect(m.provider, 'openrouter');
      expect(m.contextWindow, 128000);
    });

    test('provider keeps id and masked credential, tolerates int timestamp', () {
      final p = OrbitProviderSummary.fromJson({
        'providerId': 'openrouter',
        'name': 'OpenRouter',
        'connected': true,
        'authMethod': 'API Key',
        'maskedCredential': '••••••••1234',
        'lastVerified': 1788620000,
      });
      expect(p.providerId, 'openrouter');
      expect(p.connected, isTrue);
      expect(p.maskedCredential, '••••••••1234');
      expect(p.lastVerified, isNotNull);
    });
  });

  group('OrbitAiDefaults decoding', () {
    test('reads backend camelCase defaults', () {
      final d = OrbitAiDefaults.fromJson({
        'providerId': 'openrouter',
        'modelId': 'openrouter/openrouter/free',
        'agent': 'plan',
        'contextBehavior': 'none',
      });
      expect(d.defaultProvider, 'openrouter');
      expect(d.defaultModel, 'openrouter/openrouter/free');
    });
  });
}
