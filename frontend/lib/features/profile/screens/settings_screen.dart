import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _pushNotifications = true;
  bool _messageSound = true;
  bool _vibration = true;
  bool _messagePreview = true;
  bool _autoTranslate = true;
  bool _showOriginal = false;
  bool _darkMode = false;

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
            trailing: Switch(value: _darkMode, onChanged: (v) => setState(() => _darkMode = v), activeColor: AppColors.primary),
          ),

          _SectionHeader('Language & Translation'),
          _SettingsTile(
            icon: Icons.translate,
            title: 'My Language',
            subtitle: 'English',
            onTap: () => context.push('/settings/language'),
          ),
          _SettingsTile(
            icon: Icons.auto_awesome_outlined,
            title: 'Auto-Translate Messages',
            trailing: Switch(value: _autoTranslate, onChanged: (v) => setState(() => _autoTranslate = v), activeColor: AppColors.primary),
          ),
          _SettingsTile(
            icon: Icons.visibility_outlined,
            title: 'Show Original Alongside Translation',
            trailing: Switch(value: _showOriginal, onChanged: (v) => setState(() => _showOriginal = v), activeColor: AppColors.primary),
          ),

          _SectionHeader('Notifications'),
          _SettingsTile(
            icon: Icons.notifications_outlined,
            title: 'Push Notifications',
            trailing: Switch(value: _pushNotifications, onChanged: (v) => setState(() => _pushNotifications = v), activeColor: AppColors.primary),
          ),
          _SettingsTile(
            icon: Icons.volume_up_outlined,
            title: 'Message Sound',
            trailing: Switch(value: _messageSound, onChanged: (v) => setState(() => _messageSound = v), activeColor: AppColors.primary),
          ),
          _SettingsTile(
            icon: Icons.vibration_outlined,
            title: 'Vibration',
            trailing: Switch(value: _vibration, onChanged: (v) => setState(() => _vibration = v), activeColor: AppColors.primary),
          ),
          _SettingsTile(
            icon: Icons.preview_outlined,
            title: 'Message Preview in Notifications',
            trailing: Switch(value: _messagePreview, onChanged: (v) => setState(() => _messagePreview = v), activeColor: AppColors.primary),
          ),

          _SectionHeader('Privacy'),
          _SettingsTile(icon: Icons.access_time_outlined, title: 'Last Seen', subtitle: 'Everyone', onTap: () {}),
          _SettingsTile(icon: Icons.photo_outlined, title: 'Profile Photo', subtitle: 'Everyone', onTap: () {}),
          _SettingsTile(icon: Icons.circle_outlined, title: 'Online Status', subtitle: 'Everyone', onTap: () {}),

          _SectionHeader('Storage'),
          _SettingsTile(icon: Icons.photo_library_outlined, title: 'Auto-Download Media', subtitle: 'On Wi-Fi', onTap: () {}),
          _SettingsTile(icon: Icons.storage_outlined, title: 'Storage Usage', subtitle: 'Manage cache', onTap: () {}),

          _SectionHeader('Account'),
          _SettingsTile(icon: Icons.security_outlined, title: 'Two-Factor Authentication', onTap: () {}),
          _SettingsTile(icon: Icons.delete_outline, title: 'Delete Account', titleColor: AppColors.error, iconColor: AppColors.error, onTap: () => _confirmDeleteAccount()),

          _SectionHeader('About'),
          _SettingsTile(icon: Icons.info_outline, title: 'App Version', subtitle: '1.0.0'),
          _SettingsTile(icon: Icons.article_outlined, title: 'Terms of Service', onTap: () {}),
          _SettingsTile(icon: Icons.privacy_tip_outlined, title: 'Privacy Policy', onTap: () {}),
          _SettingsTile(icon: Icons.code_outlined, title: 'Open Source Licenses', onTap: () {}),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppColors.error)),
        content: const Text('This action is permanent and cannot be undone. All your messages and data will be deleted.', style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () {}, child: const Text('Delete', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700))),
        ],
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
