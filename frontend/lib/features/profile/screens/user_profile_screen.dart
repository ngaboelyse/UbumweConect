import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../features/auth/models/user_model.dart';
import '../../../shared/services/api_service.dart';
import '../../chat/providers/chat_provider.dart';

final userProfileProvider = FutureProvider.family<UserModel, String>((ref, userId) async {
  final api = ref.read(apiServiceProvider);
  final data = await api.get('/users/$userId');
  return UserModel.fromJson(data as Map<String, dynamic>);
});

class UserProfileScreen extends ConsumerWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider(userId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (user) => _UserProfileBody(user: user),
      ),
    );
  }
}

class _UserProfileBody extends ConsumerWidget {
  final UserModel user;
  const _UserProfileBody({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final langInfo = AppConstants.supportedLanguages.firstWhere(
      (l) => l['code'] == user.preferredLanguage,
      orElse: () => {'flag': '🌐', 'native': 'Unknown', 'code': 'unknown'},
    );

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 240,
          pinned: true,
          backgroundColor: AppColors.primary,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: Colors.white.withOpacity(0.3),
                          backgroundImage: user.avatarUrl != null
                              ? CachedNetworkImageProvider(user.avatarUrl!)
                              : null,
                          child: user.avatarUrl == null
                              ? Text(user.initials, style: const TextStyle(fontSize: 36, color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'Poppins'))
                              : null,
                        ),
                        if (user.isOnline)
                          Positioned(
                            bottom: 4, right: 4,
                            child: Container(
                              width: 16, height: 16,
                              decoration: BoxDecoration(color: AppColors.online, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(user.displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white, fontFamily: 'Poppins')),
                    Text('@${user.username}', style: const TextStyle(fontSize: 13, color: Colors.white70, fontFamily: 'Poppins')),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6, height: 6,
                                decoration: BoxDecoration(
                                  color: user.isOnline ? AppColors.online : Colors.white54,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(user.isOnline ? 'Online' : 'Offline', style: const TextStyle(fontSize: 11, color: Colors.white, fontFamily: 'Poppins')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.chat_outlined,
                        label: 'Message',
                        color: AppColors.primary,
                        onTap: () => _startChat(context, ref),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.call_outlined,
                        label: 'Voice Call',
                        color: AppColors.success,
                        onTap: () => _startCall(context, 'voice'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.videocam_outlined,
                        label: 'Video',
                        color: AppColors.secondary,
                        onTap: () => _startCall(context, 'video'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Bio
                if (user.bio != null && user.bio!.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 8)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('About', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHint, fontFamily: 'Poppins', letterSpacing: 0.5)),
                        const SizedBox(height: 6),
                        Text(user.bio!, style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Poppins', height: 1.5, fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Language preference
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 8)],
                  ),
                  child: Row(
                    children: [
                      Text(langInfo['flag']!, style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Speaks', style: TextStyle(fontSize: 11, color: AppColors.textHint, fontFamily: 'Poppins')),
                          Text(langInfo['native']!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFamily: 'Poppins')),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.translate, size: 14, color: AppColors.primary),
                            SizedBox(width: 4),
                            Text('Auto-translate', style: TextStyle(fontSize: 11, color: AppColors.primary, fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Translation note
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: AppColors.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Messages will be automatically translated between your languages so you can communicate naturally.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFamily: 'Poppins', height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _startChat(BuildContext context, WidgetRef ref) async {
    try {
      final conv = await ref.read(conversationsProvider.notifier).createConversation(
        participantIds: [user.id],
        type: 'direct',
      );
      if (context.mounted) context.push('/chat/${conv.id}');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  void _startCall(BuildContext context, String type) {
    context.push('/call/$type/${user.id}');
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: color, fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
