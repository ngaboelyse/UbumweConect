import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../../../shared/services/api_service.dart';

// Conversations list
final conversationsProvider = AsyncNotifierProvider<ConversationsNotifier, List<ConversationModel>>(
  ConversationsNotifier.new,
);

// Messages for a specific conversation
final messagesProvider = AsyncNotifierProviderFamily<MessagesNotifier, List<MessageModel>, String>(
  MessagesNotifier.new,
);

// Typing users per conversation
final typingUsersProvider = StateProvider.family<Set<String>, String>((ref, convId) => {});

class ConversationsNotifier extends AsyncNotifier<List<ConversationModel>> {
  @override
  Future<List<ConversationModel>> build() async {
    return _fetchConversations();
  }

  Future<List<ConversationModel>> _fetchConversations() async {
    final api = ref.read(apiServiceProvider);
    final data = await api.getList('/conversations');
    if (data is List) {
      return data.map((c) => ConversationModel.fromJson(c as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetchConversations);
  }

  Future<ConversationModel> createConversation({
    required List<String> participantIds,
    required String type,
    String? name,
  }) async {
    final api = ref.read(apiServiceProvider);
    final data = await api.post('/conversations', data: {
      'participant_ids': participantIds,
      'type': type,
      if (name != null) 'name': name,
    });
    final conversation = ConversationModel.fromJson(data);
    state = AsyncValue.data([conversation, ...state.value ?? []]);
    return conversation;
  }

  /// Mark all messages in a conversation as read for the current user.
  Future<void> markRead(String conversationId) async {
    try {
      await ref.read(apiServiceProvider).post('/conversations/$conversationId/read');
      // Clear the unread badge locally
      final current = state.value ?? [];
      final index = current.indexWhere((c) => c.id == conversationId);
      if (index >= 0 && current[index].unreadCount > 0) {
        final updated = [...current];
        updated[index] = current[index].copyWith(unreadCount: 0);
        state = AsyncValue.data(updated);
      }
    } catch (_) {
      // Non-fatal: badge clearing is best-effort
    }
  }

  void addOrUpdateConversation(ConversationModel conversation) {
    final current = state.value ?? [];
    final index = current.indexWhere((c) => c.id == conversation.id);
    if (index >= 0) {
      final updated = [...current];
      updated[index] = conversation;
      state = AsyncValue.data(updated);
    } else {
      state = AsyncValue.data([conversation, ...current]);
    }
  }
}

class MessagesNotifier extends FamilyAsyncNotifier<List<MessageModel>, String> {
  String? _nextCursor;
  bool _hasMore = true;

  @override
  Future<List<MessageModel>> build(String conversationId) async {
    return _fetchMessages(conversationId);
  }

  Future<List<MessageModel>> _fetchMessages(String conversationId, {String? cursor}) async {
    final api = ref.read(apiServiceProvider);
    final params = <String, dynamic>{'limit': 50};
    if (cursor != null) params['cursor'] = cursor;

    final data = await api.get('/conversations/$conversationId/messages', params: params);
    _nextCursor = data['next_cursor'] as String?;
    _hasMore = data['has_more'] as bool? ?? false;

    final messages = (data['messages'] as List<dynamic>? ?? [])
        .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
        .toList();

    // API returns newest-first, which matches the reverse:true ListView
    // (index 0 renders at the bottom of the screen).
    return messages;
  }

  Future<void> loadMore() async {
    if (!_hasMore || _nextCursor == null) return;
    final more = await _fetchMessages(arg, cursor: _nextCursor);
    state = AsyncValue.data([...(state.value ?? []), ...more]);
  }

  Future<MessageModel> sendMessage({
    required String content,
    required String type,
    String? replyToId,
    String? mediaUrl,
    String? fileName,
    int? fileSize,
    double? durationSeconds,
  }) async {
    final api = ref.read(apiServiceProvider);
    final data = await api.post('/conversations/$arg/messages', data: {
      'content': content,
      'message_type': type,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (fileName != null) 'file_name': fileName,
      if (fileSize != null) 'file_size': fileSize,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
    });
    final message = MessageModel.fromJson(data);
    prependMessage(message);
    return message;
  }

  /// Upload an attachment file, then send a message referencing it.
  Future<MessageModel> sendAttachment({
    required String filePath,
    required String kind, // image | file | voice
    required String caption,
    String? replyToId,
    double? durationSeconds,
    Uint8List? fileBytes, // required on web (no real file path exists)
  }) async {
    final api = ref.read(apiServiceProvider);
    final fileName = filePath.split(RegExp(r'[/\\]')).last;

    final uploadResult = await api.postMultipart(
      '/conversations/$arg/attachments',
      FormData.fromMap({
        'kind': kind,
        'file': fileBytes != null
            ? MultipartFile.fromBytes(fileBytes, filename: fileName)
            : await MultipartFile.fromFile(filePath, filename: fileName),
      }),
    );

    return sendMessage(
      content: caption,
      type: kind,
      replyToId: replyToId,
      mediaUrl: uploadResult['url'] as String,
      fileName: uploadResult['file_name'] as String?,
      fileSize: uploadResult['file_size'] as int?,
      durationSeconds: durationSeconds,
    );
  }

  /// Edit a text message (server enforces 15-minute window).
  Future<void> editMessage(String messageId, String newContent) async {
    final updated = await ref
        .read(apiServiceProvider)
        .put('/conversations/$arg/messages/$messageId', data: {'content': newContent});
    _replaceMessage(MessageModel.fromJson(updated));
  }

  /// Soft-delete a message (sender only).
  Future<void> deleteMessage(String messageId) async {
    await ref.read(apiServiceProvider).delete('/conversations/$arg/messages/$messageId');
    final current = state.value ?? [];
    state = AsyncValue.data(
      current.map((m) => m.id == messageId ? m.copyWith(isDeleted: true) : m).toList(),
    );
  }

  /// Add or toggle a reaction on a message.
  Future<void> toggleReaction(String messageId, String emoji) async {
    final updated = await ref
        .read(apiServiceProvider)
        .post('/conversations/$arg/messages/$messageId/reactions', data: {'emoji': emoji});
    _replaceMessage(MessageModel.fromJson(updated));
  }

  void _replaceMessage(MessageModel updated) {
    final current = state.value ?? [];
    state = AsyncValue.data(
      current.map((m) => m.id == updated.id ? updated : m).toList(),
    );
  }

  void prependMessage(MessageModel message) {
    state = AsyncValue.data([message, ...(state.value ?? [])]);
  }

  void updateMessageStatus(String messageId, String status) {
    final current = state.value ?? [];
    state = AsyncValue.data(
      current.map((m) => m.id == messageId ? _copyWithStatus(m, status) : m).toList(),
    );
  }

  MessageModel _copyWithStatus(MessageModel m, String status) {
    return MessageModel(
      id: m.id,
      conversationId: m.conversationId,
      senderId: m.senderId,
      messageType: m.messageType,
      originalContent: m.originalContent,
      originalLanguage: m.originalLanguage,
      translatedContents: m.translatedContents,
      audioUrl: m.audioUrl,
      fileUrl: m.fileUrl,
      fileName: m.fileName,
      fileSize: m.fileSize,
      durationSeconds: m.durationSeconds,
      isDeleted: m.isDeleted,
      replyToId: m.replyToId,
      status: status,
      createdAt: m.createdAt,
      sender: m.sender,
    );
  }
}
