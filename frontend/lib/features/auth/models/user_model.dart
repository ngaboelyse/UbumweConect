import 'package:equatable/equatable.dart';

class UserModel extends Equatable {
  final String id;
  final String email; // May be absent in profile-style responses (contacts, participants)
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final String? phone;
  final String preferredLanguage;
  final bool isOnline;
  final DateTime? lastSeen;
  final bool isActive;
  final String role;
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.phone,
    required this.preferredLanguage,
    required this.isOnline,
    this.lastSeen,
    required this.isActive,
    required this.role,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      phone: json['phone'] as String?,
      preferredLanguage: json['preferred_language'] as String? ?? 'english',
      isOnline: json['is_online'] as bool? ?? false,
      lastSeen: json['last_seen'] != null
          ? DateTime.tryParse(json['last_seen'] as String)
          : null,
      isActive: json['is_active'] as bool? ?? true,
      role: json['role'] as String? ?? 'user',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'bio': bio,
      'phone': phone,
      'preferred_language': preferredLanguage,
      'is_online': isOnline,
      'last_seen': lastSeen?.toIso8601String(),
      'is_active': isActive,
      'role': role,
      'created_at': createdAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? phone,
    String? preferredLanguage,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return UserModel(
      id: id,
      email: email,
      username: username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      phone: phone ?? this.phone,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      isActive: isActive,
      role: role,
      createdAt: createdAt,
    );
  }

  String get initials {
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
  }

  bool get isAdmin => role == 'admin';

  @override
  List<Object?> get props => [id, email, username, displayName, preferredLanguage, isOnline];
}
