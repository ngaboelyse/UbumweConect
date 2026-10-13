import 'package:equatable/equatable.dart';
import '../../auth/models/user_model.dart';

class MessageModel extends Equatable {
  final String id;
  final String conversationId;
  final String senderId;
  final String messageType;
  final String? originalContent;
  final String? originalLanguage;
  final Map<String, String>? translatedContents;
  final String? audioUrl;
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final double? durationSeconds;
  final bool isDeleted;
  final bool isEdited;
  final String? replyToId;
  final String? status;
  final DateTime createdAt;
  final UserModel? sender;
  /// Raw reaction rows: [{user_id: ..., emoji: ...}]
  final List<Map<String, String>> reactions;

  const MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.messageType,
    this.originalContent,
    this.originalLanguage,
    this.translatedContents,
    this.audioUrl,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.durationSeconds,
    required this.isDeleted,
    this.isEdited = false,
    this.replyToId,
    this.status,
    required this.createdAt,
    this.sender,
    this.reactions = const [],
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      messageType: json['message_type'] as String? ?? 'text',
      originalContent: json['original_content'] as String?,
      originalLanguage: json['original_language'] as String?,
      translatedContents: json['translated_contents'] != null
          ? Map<String, String>.from(json['translated_contents'] as Map)
          : null,
      audioUrl: json['audio_url'] as String?,
      fileUrl: json['file_url'] as String?,
      fileName: json['file_name'] as String?,
      fileSize: json['file_size'] as int?,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
      isDeleted: json['is_deleted'] as bool? ?? false,
      isEdited: json['is_edited'] as bool? ?? false,
      replyToId: json['reply_to_id'] as String?,
      status: json['status'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      sender: json['sender'] != null
          ? UserModel.fromJson(json['sender'] as Map<String, dynamic>)
          : null,
      reactions: (json['reactions'] as List<dynamic>? ?? [])
          .map((r) => (r as Map<String, dynamic>).map(
                (k, v) => MapEntry(k, v?.toString() ?? ''),
              ))
          .toList(),
    );
  }

  /// Returns the best content for the given preferred language
  String getContentForLanguage(String preferredLanguage) {
    if (isDeleted) return '🚫 This message was deleted';
    if (translatedContents != null && translatedContents!.containsKey(preferredLanguage)) {
      return translatedContents![preferredLanguage]!;
    }
    return originalContent ?? '';
  }

  bool hasTranslation(String language) {
    return translatedContents != null &&
        translatedContents!.containsKey(language) &&
        originalLanguage != language;
  }

  String? getTranslationSource() {
    if (originalLanguage == null) return null;
    final langNames = {
      'kinyarwanda': 'Kinyarwanda',
      'english': 'English',
      'french': 'French',
      'swahili': 'Swahili',
    };
    return langNames[originalLanguage];
  }

  bool get isText => messageType == 'text';
  bool get isVoice => messageType == 'voice';
  bool get isImage => messageType == 'image';
  bool get isFile => messageType == 'file';
  bool get isSystem => messageType == 'system';

  /// Aggregated emoji -> count map for display (e.g. {👍: 2, ❤️: 1})
  Map<String, int> get reactionCounts {
    final counts = <String, int>{};
    for (final r in reactions) {
      final emoji = r['emoji'];
      if (emoji != null && emoji.isNotEmpty) {
        counts[emoji] = (counts[emoji] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Copy constructor for optimistic state updates in providers.
  MessageModel copyWith({
    String? originalContent,
    bool? isEdited,
    bool? isDeleted,
    String? status,
    List<Map<String, String>>? reactions,
  }) {
    return MessageModel(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      messageType: messageType,
      originalContent: originalContent ?? this.originalContent,
      originalLanguage: originalLanguage,
      translatedContents: translatedContents,
      audioUrl: audioUrl,
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: fileSize,
      durationSeconds: durationSeconds,
      isDeleted: isDeleted ?? this.isDeleted,
      isEdited: isEdited ?? this.isEdited,
      replyToId: replyToId,
      status: status ?? this.status,
      createdAt: createdAt,
      sender: sender,
      reactions: reactions ?? this.reactions,
    );
  }

  @override
  List<Object?> get props => [id, conversationId, senderId, messageType, originalContent, isEdited, isDeleted, createdAt, status, reactions];
}
