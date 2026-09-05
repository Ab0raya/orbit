import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/orbit_websocket_client.dart';
import '../../../core/providers.dart';
import '../models/ai_conversation_models.dart';

class AiConversationState {
  final bool isLoading;
  final List<OrbitConversation> conversations;
  final OrbitConversationDetail? activeConversation;
  final List<OrbitModelSummary> availableModels;
  final List<OrbitProviderSummary> availableProviders;
  // Null means "no explicit override": the backend resolves the Orbit
  // default model. Never hardcode a model id here — 'gpt-4o' is not a
  // valid id for the configured providers and caused upstream failures.
  final String? selectedModel;
  final String searchQuery;
  final String? errorMessage;

  const AiConversationState({
    this.isLoading = false,
    this.conversations = const [],
    this.activeConversation,
    this.availableModels = const [],
    this.availableProviders = const [],
    this.selectedModel,
    this.searchQuery = '',
    this.errorMessage,
  });

  AiConversationState copyWith({
    bool? isLoading,
    List<OrbitConversation>? conversations,
    OrbitConversationDetail? activeConversation,
    List<OrbitModelSummary>? availableModels,
    List<OrbitProviderSummary>? availableProviders,
    String? selectedModel,
    String? searchQuery,
    String? errorMessage,
    bool clearActiveConversation = false,
    bool clearSelectedModel = false,
  }) {
    return AiConversationState(
      isLoading: isLoading ?? this.isLoading,
      conversations: conversations ?? this.conversations,
      activeConversation: clearActiveConversation
          ? null
          : (activeConversation ?? this.activeConversation),
      availableModels: availableModels ?? this.availableModels,
      availableProviders: availableProviders ?? this.availableProviders,
      selectedModel: clearSelectedModel
          ? null
          : (selectedModel ?? this.selectedModel),
      searchQuery: searchQuery ?? this.searchQuery,
      errorMessage: errorMessage,
    );
  }
}

final aiConversationControllerProvider =
    StateNotifierProvider<AiConversationController, AiConversationState>((ref) {
      final client = ref.watch(webSocketClientProvider);
      return AiConversationController(client);
    });

class AiConversationController extends StateNotifier<AiConversationState> {
  final OrbitWebSocketClient _client;

  AiConversationController(this._client) : super(const AiConversationState()) {
    loadConversations();
    loadProviders();
    loadModels();
  }

  Future<void> loadConversations() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _client.sendRequest(
        'ai.conversation.list',
        payload: {'limit': 100, 'offset': 0},
      );

      if (res.success && res.payload != null) {
        final rawList = res.payload!['conversations'] as List<dynamic>? ?? [];
        final convs = rawList
            .whereType<Map<String, dynamic>>()
            .map((m) => OrbitConversation.fromJson(m))
            .toList();

        state = state.copyWith(conversations: convs, isLoading: false);
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: res.error?.message ?? 'Failed to load conversations',
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<OrbitConversationDetail?> selectConversation(String id) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _client.sendRequest(
        'ai.conversation.get',
        payload: {'conversationId': id, 'id': id},
      );

      if (res.success && res.payload != null) {
        final detail = OrbitConversationDetail.fromJson(res.payload!);
        state = state.copyWith(
          activeConversation: detail,
          selectedModel: detail.summary.modelId ?? state.selectedModel,
          isLoading: false,
        );
        return detail;
      } else {
        final errMsg = res.error?.message ?? 'Failed to get conversation';
        state = state.copyWith(
          isLoading: false,
          errorMessage: errMsg,
        );
        return null;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return null;
    }
  }

  Future<OrbitConversation?> createConversation({
    String? title,
    String? projectPath,
    String? directoryPath,
    String contextType = 'project',
    String? modelId,
  }) async {
    try {
      final payload = <String, dynamic>{'contextType': contextType};
      // Omit when absent so the backend resolves the authoritative default
      // model instead of receiving an invalid placeholder.
      final resolvedModel = modelId ?? state.selectedModel;
      if (resolvedModel != null && resolvedModel.isNotEmpty) {
        payload['modelId'] = resolvedModel;
      }
      if (title != null) payload['title'] = title;
      if (projectPath != null) payload['projectPath'] = projectPath;
      if (directoryPath != null) payload['directoryPath'] = directoryPath;

      final res = await _client.sendRequest(
        'ai.conversation.create',
        payload: payload,
      );

      if (res.success && res.payload != null) {
        final conv = OrbitConversation.fromJson(res.payload!);
        await loadConversations();
        await selectConversation(conv.id);
        return conv;
      }
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
    return null;
  }

  Future<void> renameConversation(String id, String newTitle) async {
    try {
      final res = await _client.sendRequest(
        'ai.conversation.rename',
        payload: {'conversationId': id, 'id': id, 'title': newTitle},
      );

      if (res.success) {
        await loadConversations();
        if (state.activeConversation?.summary.id == id) {
          final updatedSummary = state.activeConversation!.summary.copyWith(
            title: newTitle,
          );
          state = state.copyWith(
            activeConversation: OrbitConversationDetail(
              summary: updatedSummary,
              messages: state.activeConversation!.messages,
            ),
          );
        }
      }
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<bool> deleteConversation(
    String id, {
    bool deleteSession = false,
  }) async {
    final previousList = state.conversations;
    final wasActive = state.activeConversation?.summary.id == id;

    // Optimistically remove from state immediately
    final updatedList = state.conversations.where((c) => c.id != id).toList();
    state = state.copyWith(
      conversations: updatedList,
      clearActiveConversation: wasActive,
    );

    try {
      final res = await _client.sendRequest(
        'ai.conversation.delete',
        payload: {
          'conversationId': id,
          'id': id,
          'deleteSession': deleteSession,
        },
      );

      if (res.success) {
        await loadConversations();
        return true;
      } else {
        // Rollback on failure
        state = state.copyWith(
          conversations: previousList,
          errorMessage: res.error?.message ?? 'Failed to delete conversation',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        conversations: previousList,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<void> searchConversations(String query) async {
    state = state.copyWith(searchQuery: query);
    if (query.trim().isEmpty) {
      await loadConversations();
      return;
    }

    try {
      final res = await _client.sendRequest(
        'ai.conversation.search',
        payload: {'query': query.trim(), 'limit': 50},
      );

      if (res.success && res.payload != null) {
        final rawList = (res.payload!['conversations'] ?? res.payload!['results']) as List<dynamic>? ?? [];
        final convs = rawList
            .whereType<Map<String, dynamic>>()
            .map((m) => OrbitConversation.fromJson(m))
            .toList();

        state = state.copyWith(conversations: convs);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> loadProviders() async {
    try {
      final res = await _client.sendRequest('ai.providers.list', payload: {});
      if (res.success && res.payload != null) {
        final rawList = res.payload!['providers'] as List<dynamic>? ?? [];
        final provs = rawList
            .whereType<Map<String, dynamic>>()
            .map((m) => OrbitProviderSummary.fromJson(m))
            .toList();

        state = state.copyWith(availableProviders: provs);
      }
    } catch (_) {}
  }

  Future<void> loadModels() async {
    try {
      final res = await _client.sendRequest('ai.models.list', payload: {});
      if (res.success && res.payload != null) {
        final rawList = res.payload!['models'] as List<dynamic>? ?? [];
        final mList = rawList
            .whereType<Map<String, dynamic>>()
            .map((m) => OrbitModelSummary.fromJson(m))
            .toList();

        state = state.copyWith(availableModels: mList);
      }
    } catch (_) {}
  }

  void setSelectedModel(String? model) {
    if (model == null || model.isEmpty) {
      state = state.copyWith(clearSelectedModel: true);
    } else {
      state = state.copyWith(selectedModel: model);
    }
  }

  void clearActiveConversation() {
    state = state.copyWith(clearActiveConversation: true);
  }
}
