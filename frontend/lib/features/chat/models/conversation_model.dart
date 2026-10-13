import 'package:equatable/equatable.dart';
import '../../auth/models/user_model.dart';
import 'message_model.dart';

class ParticipantModel extends Equatable {
  final String id;
  final String userId;
  final String role;
  final DateTime joinedAt;
  final UserModel? user;

  const ParticipantModel({
    required this.id,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.user,
  });

  factory ParticipantModel.fromJson(Map<String, dynamic> json) {
    return ParticipantModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String? ?? 'member',
      joinedAt: DateTime.tryParse(json['joined_at'] as String? ?? '') ?? DateTime.now(),
      user: json['user'] != null
          ? UserModel.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  List<Object?> get props => [id, userId, role];
}


class ConversationModel extends Equatable {
  final String id;
  final String type;
  final String? name;
  final String? description;
  final String? avatarUrl;
  final String? createdBy;
  final List<ParticipantModel> participants;
  final MessageModel? lastMessage;
  final int unreadCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ConversationModel({
    required this.id,
    required this.type,
    this.name,
    this.description,
    this.avatarUrl,
    this.createdBy,
    required this.participants,
    this.lastMessage,
    required this.unreadCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id'] as String,
      type: json['type'] as String? ?? 'direct',
      name: json['name'] as String?,
      description: json['description'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdBy: json['created_by'] as String?,
      participants: (json['participants'] as List<dynamic>? ?? [])
          .map((p) => ParticipantModel.fromJson(p as Map<String, dynamic>))
          .toList(),
      lastMessage: json['last_message'] != null
          ? MessageModel.fromJson(json['last_message'] as Map<String, dynamic>)
          : null,
      unreadCount: json['unread_count'] as int? ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  bool get isGroup => type == 'group';
  bool get isDirect => type == 'direct';

  String getDisplayName(String currentUserId) {
    if (isGroup) return name ?? 'Group Chat';
    final other = participants.firstWhere(
      (p) => p.userId != currentUserId,
      orElse: () => participants.first,
    );
    return other.user?.displayName ?? 'Unknown';
  }

  String? getDisplayAvatar(String currentUserId) {
    if (avatarUrl != null) return avatarUrl;
    if (isDirect) {
      final other = participants.firstWhere(
        (p) => p.userId != currentUserId,
        orElse: () => participants.first,
      );
      return other.user?.avatarUrl;
    }
    return null;
  }

  bool getOtherUserOnlineStatus(String currentUserId) {
    if (isDirect) {
      final other = participants.firstWhere(
        (p) => p.userId != currentUserId,
        orElse: () => participants.first,
      );
      return other.user?.isOnline ?? false;
    }
    return false;
  }

  @override
  List<Object?> get props => [id, type, name, unreadCount, updatedAt];

  ConversationModel copyWith({int? unreadCount}) {
    return ConversationModel(
      id: id,
      type: type,
      name: name,
      description: description,
      avatarUrl: avatarUrl,
      createdBy: createdBy,
      participants: participants,
      lastMessage: lastMessage ?? lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
