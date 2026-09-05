import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/core/networking/orbit_websocket_client.dart';
import 'package:orbit_mobile/protocol/messages/orbit_response.dart';
import 'package:orbit_mobile/features/ai/controllers/ai_conversation_controller.dart';
import 'package:orbit_mobile/features/ai/models/ai_conversation_models.dart';

void main() {
  group('Orbit Conversation Models', () {
    test('OrbitConversation parses from JSON and serializes back', () {
      final json = {
        'id': 'conv_123',
        'title': 'Explain README architecture',
        'created_at': 1700000000,
        'updated_at': 1700000500,
        'project_path': '/home/developer/orbit',
        'directory_path': null,
        'context_type': 'project',
        'open_code_session_id': 'ses_abc',
        'provider_id': 'openai',
        'model_id': 'gpt-4o',
        'status': 'completed',
        'last_message_preview': 'Here is the explanation...',
        'message_count': 4,
      };

      final conv = OrbitConversation.fromJson(json);
      expect(conv.id, equals('conv_123'));
      expect(conv.title, equals('Explain README architecture'));
      expect(conv.createdAt, equals(1700000000));
      expect(conv.updatedAt, equals(1700000500));
      expect(conv.projectPath, equals('/home/developer/orbit'));
      expect(conv.openCodeSessionId, equals('ses_abc'));
      expect(conv.providerId, equals('openai'));
      expect(conv.modelId, equals('gpt-4o'));
      expect(conv.status, equals('completed'));
      expect(conv.lastMessagePreview, equals('Here is the explanation...'));
      expect(conv.messageCount, equals(4));

      final serialized = conv.toJson();
      expect(serialized['id'], equals('conv_123'));
      expect(serialized['title'], equals('Explain README architecture'));
    });

    test('OrbitConversationMessage parses activities and error', () {
      final json = {
        'id': 'msg_01',
        'conversation_id': 'conv_123',
        'role': 'assistant',
        'content': 'I inspected the file.',
        'created_at': 1700000100,
        'status': 'completed',
        'task_id': 'task_xyz',
        'provider_id': 'openai',
        'model_id': 'gpt-4o',
        'activities': [
          {
            'activityId': 'act_01',
            'taskId': 'task_xyz',
            'title': 'Reading README.md',
            'tool': 'read_file',
            'command': 'README.md',
            'status': 'completed',
            'activityType': 'reading',
          }
        ],
      };

      final msg = OrbitConversationMessage.fromJson(json);
      expect(msg.id, equals('msg_01'));
      expect(msg.role, equals('assistant'));
      expect(msg.isAssistant, isTrue);
      expect(msg.isUser, isFalse);
      expect(msg.activities.length, equals(1));
      expect(msg.activities[0].tool, equals('read_file'));
    });

    test('OrbitProviderSummary parses masked credentials', () {
      final json = {
        'provider_id': 'openai',
        'name': 'OpenAI',
        'connected': true,
        'auth_method': 'api_key',
        'masked_credential': '••••••••sk42',
        'last_verified': 'Today',
      };

      final prov = OrbitProviderSummary.fromJson(json);
      expect(prov.providerId, equals('openai'));
      expect(prov.name, equals('OpenAI'));
      expect(prov.connected, isTrue);
      expect(prov.maskedCredential, equals('••••••••sk42'));
    });

    test('OrbitModelSummary parses capabilities and context window', () {
      final json = {
        'id': 'gpt-4o',
        'name': 'GPT-4o',
        'provider': 'openai',
        'context_window': 128000,
        'supports_tools': true,
        'supports_streaming': true,
        'default_model': true,
      };

      final model = OrbitModelSummary.fromJson(json);
      expect(model.id, equals('gpt-4o'));
      expect(model.contextWindow, equals(128000));
      expect(model.supportsTools, isTrue);
      expect(model.defaultModel, isTrue);
    });
  });

  group('AiConversationController Protocol & State Tests', () {
    late _MockClient client;
    late AiConversationController controller;

    setUp(() {
      client = _MockClient();
      controller = AiConversationController(client);
    });

    test('selectConversation sends ai.conversation.get with conversationId and id, loads detail', () async {
      client.responseHandler = (action, payload) {
        if (action == 'ai.conversation.get') {
          return OrbitResponse(
            id: 'resp_1',
            action: action,
            success: true,
            payload: {
              'id': 'conv_test_1',
              'title': 'Test Conversation',
              'createdAt': 1700000000,
              'updatedAt': 1700000500,
              'projectPath': '/home/dev/orbit',
              'modelId': 'big-pickle',
              'messages': [
                {
                  'id': 'msg_1',
                  'conversationId': 'conv_test_1',
                  'role': 'user',
                  'content': 'Hello AI',
                  'createdAt': 1700000000,
                  'status': 'completed',
                },
                {
                  'id': 'msg_2',
                  'conversationId': 'conv_test_1',
                  'role': 'assistant',
                  'content': 'Hello human',
                  'createdAt': 1700000100,
                  'status': 'completed',
                },
              ],
            },
          );
        }
        return OrbitResponse(id: 'resp_default', action: action, success: true, payload: {});
      };

      final detail = await controller.selectConversation('conv_test_1');

      // Verify protocol payload contains conversationId
      final getReq = client.sent.firstWhere((r) => r['action'] == 'ai.conversation.get');
      expect(getReq['payload']?['conversationId'], equals('conv_test_1'));
      expect(getReq['payload']?['id'], equals('conv_test_1'));

      // Verify controller state updated
      expect(detail, isNotNull);
      expect(detail!.summary.id, equals('conv_test_1'));
      expect(detail.messages.length, equals(2));
      expect(controller.state.activeConversation?.summary.id, equals('conv_test_1'));
      expect(controller.state.selectedModel, equals('big-pickle'));
    });

    test('deleteConversation sends ai.conversation.delete with conversationId and id, updates state', () async {
      // Setup initial state with a conversation
      final initialConv = OrbitConversation(
        id: 'conv_del_1',
        title: 'To Delete',
        createdAt: 1700000000,
        updatedAt: 1700000500,
        projectPath: '/home/dev/orbit',
      );
      final detail = OrbitConversationDetail(
        summary: initialConv,
        messages: [],
      );

      controller.state = controller.state.copyWith(
        conversations: [initialConv],
        activeConversation: detail,
      );

      client.responseHandler = (action, payload) {
        if (action == 'ai.conversation.delete') {
          return OrbitResponse(id: 'del_ok', action: action, success: true, payload: {'success': true});
        }
        if (action == 'ai.conversation.list') {
          return OrbitResponse(id: 'list_ok', action: action, success: true, payload: {'conversations': []});
        }
        return OrbitResponse(id: 'ok', action: action, success: true, payload: {});
      };

      final success = await controller.deleteConversation('conv_del_1');
      expect(success, isTrue);

      // Verify protocol payload contains conversationId
      final delReq = client.sent.firstWhere((r) => r['action'] == 'ai.conversation.delete');
      expect(delReq['payload']?['conversationId'], equals('conv_del_1'));
      expect(delReq['payload']?['id'], equals('conv_del_1'));

      // Verify active conversation cleared and removed from list
      expect(controller.state.activeConversation, isNull);
      expect(controller.state.conversations, isEmpty);
    });

    test('searchConversations parses results list and updates state', () async {
      client.responseHandler = (action, payload) {
        if (action == 'ai.conversation.search') {
          return OrbitResponse(
            id: 'search_ok',
            action: action,
            success: true,
            payload: {
              'results': [
                {
                  'id': 'conv_match_1',
                  'title': 'Matched Conversation',
                  'createdAt': 1700000000,
                  'updatedAt': 1700000500,
                },
              ],
            },
          );
        }
        return OrbitResponse(id: 'ok', action: action, success: true, payload: {});
      };

      await controller.searchConversations('Matched');

      final searchReq = client.sent.firstWhere((r) => r['action'] == 'ai.conversation.search');
      expect(searchReq['payload']?['query'], equals('Matched'));
      expect(controller.state.conversations.length, equals(1));
      expect(controller.state.conversations.first.title, equals('Matched Conversation'));
    });
  });
}

class _MockClient extends OrbitWebSocketClient {
  final List<Map<String, dynamic>> sent = [];
  OrbitResponse Function(String action, Map<String, dynamic>? payload)? responseHandler;

  @override
  Future<OrbitResponse> sendRequest(
    String action, {
    Map<String, dynamic>? payload,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    sent.add({'action': action, 'payload': payload});
    if (responseHandler != null) {
      return responseHandler!(action, payload);
    }
    return OrbitResponse(id: 'mock_resp', action: action, success: true, payload: {});
  }
}
