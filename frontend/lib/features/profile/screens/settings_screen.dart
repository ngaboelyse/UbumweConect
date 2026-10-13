import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/theme_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../shared/services/local_storage_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Toggles are persisted locally so they survive restarts.
  bool _pushNotifications = true;
  bool _messageSound = true;
  bool _vibration = true;
  bool _messagePreview = true;
  bool _autoTranslate = true;
  bool _showOriginal = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final storage = ref.read(localStorageServiceProvider);
    final prefs = await storage.getAllPrefs();
    if (!mounted) return;
    setState(() {
      _pushNotifications = prefs['pref_push_notifications'] as bool? ?? true;
      _messageSound = prefs['pref_message_sound'] as bool? ?? true;
      _vibration = prefs['pref_vibration'] as bool? ?? true;
      _messagePreview = prefs['pref_message_preview'] as bool? ?? true;
      _autoTranslate = prefs['pref_auto_translate'] as bool? ?? true;
      _showOriginal = prefs['pref_show_original'] as bool? ?? false;
      _loaded = true;
    });
  }

  Future<void> _setPref(String key, bool value) async {
    final storage = ref.read(localStorageServiceProvider);
    await storage.setRawBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader('Appearance'),
          _SettingsTile(
            icon: Icons.dark_mode_outlined,
            title: 'Dark Mode',
            trailing: Consumer(builder: (context, ref, _) {
              final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
              return Switch(
                value: isDark,
                onChanged: (v) => ref.read(themeModeProvider.notifier).setDarkMode(v),
                activeColor: AppColors.primary,
              );
            }),
          ),

          _SectionHeader('Language & Translation'),
          _SettingsTile(
            icon: Icons.translate,
            title: 'My Language',
            subtitle: (ref.watch(currentUserProvider)?.preferredLanguage ?? 'english')
                .replaceAllMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase()),
            onTap: () => context.push('/settings/language'),
          ),
          _SettingsTile(
            icon: Icons.auto_awesome_outlined,
            title: 'Auto-Translate Messages',
            trailing: Switch(
              value: _autoTranslate,
              onChanged: _loaded
                  ? (v) { setState(() => _autoTranslate = v); _setPref('pref_auto_translate', v); }
                  : null,
              activeColor: AppColors.primary,
            ),
          ),
          _SettingsTile(
            icon: Icons.visibility_outlined,
            title: 'Show Original Alongside Translation',
            trailing: Switch(
              value: _showOriginal,
              onChanged: _loaded
                  ? (v) { setState(() => _showOriginal = v); _setPref('pref_show_original', v); }
                  : null,
              activeColor: AppColors.primary,
            ),
          ),

          _SectionHeader('Notifications'),
          _SettingsTile(
            icon: Icons.notifications_outlined,
            title: 'Push Notifications',
            trailing: Switch(
              value: _pushNotifications,
              onChanged: _loaded
                  ? (v) { setState(() => _pushNotifications = v); _setPref('pref_push_notifications', v); }
                  : null,
              activeColor: AppColors.primary,
            ),
          ),
          _SettingsTile(
            icon: Icons.volume_up_outlined,
            title: 'Message Sound',
            trailing: Switch(
              value: _messageSound,
              onChanged: _loaded
                  ? (v) { setState(() => _messageSound = v); _setPref('pref_message_sound', v); }
                  : null,
              activeColor: AppColors.primary,
            ),
          ),
          _SettingsTile(
            icon: Icons.vibration_outlined,
            title: 'Vibration',
            trailing: Switch(
              value: _vibration,
              onChanged: _loaded
                  ? (v) { setState(() => _vibration = v); _setPref('pref_vibration', v); }
                  : null,
              activeColor: AppColors.primary,
            ),
          ),
          _SettingsTile(
            icon: Icons.preview_outlined,
            title: 'Message Preview in Notifications',
            trailing: Switch(
              value: _messagePreview,
              onChanged: _loaded
                  ? (v) { setState(() => _messagePreview = v); _setPref('pref_message_preview', v); }
                  : null,
              activeColor: AppColors.primary,
            ),
          ),

          _SectionHeader('Privacy'),
          _SettingsTile(
            icon: Icons.access_time_outlined,
            title: 'Last Seen',
            subtitle: 'Everyone',
            onTap: () => _infoDialog(context, 'Last Seen', 'Everyone can see when you were last active. Finer-grained visibility (contacts only / nobody) is planned in a future release.'),
          ),
          _SettingsTile(
            icon: Icons.photo_outlined,
            title: 'Profile Photo',
            subtitle: 'Everyone',
            onTap: () => _infoDialog(context, 'Profile Photo', 'Your profile photo is visible to people you are in a conversation with. Change it from Profile → Edit Profile.'),
          ),
          _SettingsTile(
            icon: Icons.circle_outlined,
            title: 'Online Status',
            subtitle: 'Everyone',
            onTap: () => _infoDialog(context, 'Online Status', 'Other users see the green dot while you are connected; going offline shows "Offline" instead.'),
          ),

          _SectionHeader('Storage'),
          _SettingsTile(
            icon: Icons.photo_library_outlined,
            title: 'Auto-Download Media',
            subtitle: 'On Wi-Fi',
            onTap: () => _infoDialog(
              context,
              'Auto-Download Media',
              'Media (images, files and voice notes) downloads automatically on Wi-Fi. On mobile data, tap a message to download it manually — keeping data usage under control.',
            ),
          ),
          _SettingsTile(
            icon: Icons.storage_outlined,
            title: 'Storage Usage',
            subtitle: 'Manage cache',
            onTap: () => _infoDialog(
              context,
              'Storage Usage',
              'Your conversations, cached profile data and downloaded media are stored on this device. Message history lives on the server and syncs when you sign in from any device.\n\nClearing app storage only removes the local cache — nothing is deleted from your account.',
            ),
          ),

          _SectionHeader('Account'),
          _SettingsTile(
            icon: Icons.security_outlined,
            title: 'Two-Factor Authentication',
            subtitle: 'Add an extra layer of security',
            onTap: () => _infoDialog(
              context,
              'Two-Factor Authentication',
              'Two-factor authentication is coming soon. Your account is currently protected by your password, server-side session revocation, and automatic logout on other devices when you sign out.',
            ),
          ),
          _SettingsTile(icon: Icons.delete_outline, title: 'Delete Account', titleColor: AppColors.error, iconColor: AppColors.error, onTap: () => _confirmDeleteAccount()),

          _SectionHeader('About'),
          _SettingsTile(icon: Icons.info_outline, title: 'App Version', subtitle: '1.0.0'),
          _SettingsTile(icon: Icons.article_outlined, title: 'Terms of Service', onTap: () => context.push('/help')),
          _SettingsTile(icon: Icons.privacy_tip_outlined, title: 'Privacy Policy', onTap: () => context.push('/help')),
          _SettingsTile(icon: Icons.help_outline, title: 'Help & Support', onTap: () => context.push('/help')),
          _SettingsTile(icon: Icons.code_outlined, title: 'Open Source Licenses', onTap: () => showLicensePage(
            context: context,
            applicationName: 'Ubumwe Connect',
            applicationVersion: '1.0.0',
            applicationLegalese: 'Bringing People Together Beyond Language',
          )),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _confirmDeleteAccount() {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    bool isDeleting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Delete Account', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppColors.error)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This action is permanent and cannot be undone. All devices will be signed out and your account deactivated.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm your password', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                decoration: const InputDecoration(labelText: 'Type "DELETE MY ACCOUNT" to confirm', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: isDeleting
                  ? null
                  : () async {
                      if (passwordController.text.isEmpty || confirmController.text.trim().toUpperCase() != 'DELETE MY ACCOUNT') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter your password and type "DELETE MY ACCOUNT" to confirm'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        return;
                      }
                      setDialogState(() => isDeleting = true);
                      final messenger = ScaffoldMessenger.of(context);
                      final router = GoRouter.of(context);
                      try {
                        await ref.read(authNotifierProvider.notifier).deleteAccount(passwordController.text);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        router.go('/login');
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Your account has been deleted'), backgroundColor: AppColors.error),
                        );
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setDialogState(() => isDeleting = false);
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Failed to delete account — check your password and try again'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    },
              child: isDeleting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }

  void _infoDialog(BuildContext context, String title, String body) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(body, style: const TextStyle(fontFamily: 'Poppins', height: 1.5, fontSize: 13)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHint, letterSpacing: 1.2, fontFamily: 'Poppins'),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  final Color? iconColor;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? AppColors.textSecondary, size: 22),
        title: Text(title, style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: titleColor ?? AppColors.textPrimary)),
        subtitle: subtitle != null ? Text(subtitle!, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint)) : null,
        trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right, color: AppColors.textHint) : null),
        onTap: onTap,
      ),
    );
  }
}
