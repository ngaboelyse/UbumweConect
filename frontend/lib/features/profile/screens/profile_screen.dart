import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../auth/providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final langInfo = AppConstants.supportedLanguages.firstWhere(
      (l) => l['code'] == user.preferredLanguage,
      orElse: () => {'flag': '🌐', 'native': 'Unknown', 'code': 'unknown'},
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverAppBar(
            expandedHeight: 220,
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
                            radius: 48,
                            backgroundColor: Colors.white.withOpacity(0.3),
                            backgroundImage: user.avatarUrl != null
                                ? CachedNetworkImageProvider(user.avatarUrl!)
                                : null,
                            child: user.avatarUrl == null
                                ? Text(user.initials, style: const TextStyle(fontSize: 36, color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'Poppins'))
                                : null,
                          ),
                          Positioned(
                            bottom: 0, right: 0,
                            child: GestureDetector(
                              onTap: () => context.push('/edit-profile'),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                                child: const Icon(Icons.edit, color: Colors.white, size: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(user.displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white, fontFamily: 'Poppins')),
                      Text('@${user.username}', style: const TextStyle(fontSize: 14, color: Colors.white70, fontFamily: 'Poppins')),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white),
                onPressed: () => context.push('/settings'),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      child: Text(user.bio!, style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Poppins', height: 1.5)),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Language chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 8)],
                    ),
                    child: Row(
                      children: [
                        Text(langInfo['flag']!, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Preferred Language', style: TextStyle(fontSize: 12, color: AppColors.textHint, fontFamily: 'Poppins')),
                            Text(langInfo['native']!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFamily: 'Poppins')),
                          ],
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => context.push('/settings/language'),
                          child: const Text('Change', style: TextStyle(fontFamily: 'Poppins')),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Menu
                  _MenuItem(icon: Icons.edit_outlined, title: 'Edit Profile', onTap: () => context.push('/edit-profile')),
                  _MenuItem(icon: Icons.translate_outlined, title: 'Language Settings', onTap: () => context.push('/settings/language')),
                  _MenuItem(icon: Icons.notifications_outlined, title: 'Notifications', onTap: () => context.push('/settings')),
                  _MenuItem(icon: Icons.lock_outline, title: 'Privacy & Security', onTap: () => context.push('/settings')),
                  _MenuItem(icon: Icons.help_outline, title: 'Help & Support', onTap: () {}),
                  _MenuItem(icon: Icons.info_outline, title: 'About Ubumwe Connect', onTap: () => _showAbout(context)),
                  const SizedBox(height: 8),
                  _MenuItem(
                    icon: Icons.logout,
                    title: 'Sign Out',
                    titleColor: AppColors.error,
                    iconColor: AppColors.error,
                    onTap: () => _confirmLogout(context, ref),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubumwe Connect', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version 1.0.0', style: TextStyle(fontFamily: 'Poppins')),
            SizedBox(height: 8),
            Text('Bringing People Together Beyond Language\n\nSupports: Kinyarwanda, English, French, Swahili', style: TextStyle(fontFamily: 'Poppins', height: 1.5)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to sign out?', style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authNotifierProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            child: const Text('Sign Out', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? titleColor;
  final Color? iconColor;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.titleColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? AppColors.textSecondary, size: 22),
        title: Text(
          title,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 15, color: titleColor ?? AppColors.textPrimary),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
        onTap: onTap,
      ),
    );
  }
}
