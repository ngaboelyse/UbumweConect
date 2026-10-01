import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../auth/providers/auth_provider.dart';

class LanguageSettingsScreen extends ConsumerStatefulWidget {
  const LanguageSettingsScreen({super.key});

  @override
  ConsumerState<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends ConsumerState<LanguageSettingsScreen> {
  bool _autoTranslate = true;
  bool _showOriginal = false;
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final selectedLang = user?.preferredLanguage ?? 'english';

    // Sample translations for preview
    final previews = {
      'kinyarwanda': 'Muraho! Amakuru yawe?',
      'english': 'Hello! How are you?',
      'french': 'Bonjour! Comment ça va?',
      'swahili': 'Habari! Habari gani?',
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Language Settings', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Language', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary, fontFamily: 'Poppins', letterSpacing: 1)),
            const SizedBox(height: 8),
            const Text('Messages will be automatically translated to this language.', style: TextStyle(fontSize: 13, color: AppColors.textHint, fontFamily: 'Poppins')),
            const SizedBox(height: 16),

            // Language selector
            ...AppConstants.supportedLanguages.map((lang) {
              final isSelected = lang['code'] == selectedLang;
              return GestureDetector(
                onTap: () async {
                  if (isSelected) return;
                  setState(() => _isSaving = true);
                  try {
                    await ref.read(authNotifierProvider.notifier).updateProfile(preferredLanguage: lang['code']);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Language changed to ${lang['native']}'), backgroundColor: AppColors.success),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isSaving = false);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary.withOpacity(0.08) : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected ? AppColors.primary : AppColors.divider, width: isSelected ? 2 : 1),
                    boxShadow: isSelected ? [BoxShadow(color: AppColors.primary.withOpacity(0.15), blurRadius: 8)] : [],
                  ),
                  child: Row(
                    children: [
                      Text(lang['flag']!, style: const TextStyle(fontSize: 32)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(lang['native']!, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isSelected ? AppColors.primary : AppColors.textPrimary, fontFamily: 'Poppins')),
                            Text(lang['name']!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFamily: 'Poppins')),
                          ],
                        ),
                      ),
                      if (isSelected) const Icon(Icons.check_circle, color: AppColors.primary),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 24),

            // Translation preview
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.preview_outlined, color: AppColors.primary, size: 18),
                      SizedBox(width: 8),
                      Text('Translation Preview', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary, fontFamily: 'Poppins')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Someone sends in Kinyarwanda:', style: TextStyle(fontSize: 11, color: AppColors.textHint, fontFamily: 'Poppins')),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.receivedBubble, borderRadius: BorderRadius.circular(12)),
                    child: Text('Muraho! Amakuru yawe?', style: const TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                  ),
                  const SizedBox(height: 8),
                  Text('You see it in ${AppConstants.supportedLanguages.firstWhere((l) => l['code'] == selectedLang)['native']}:', style: const TextStyle(fontSize: 11, color: AppColors.textHint, fontFamily: 'Poppins')),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.receivedBubble, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(previews[selectedLang] ?? previews['english']!, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                        const SizedBox(height: 4),
                        Row(
                          children: const [
                            Icon(Icons.translate, size: 12, color: AppColors.textHint),
                            SizedBox(width: 4),
                            Text('Translated from Kinyarwanda', style: TextStyle(fontSize: 11, color: AppColors.textHint, fontFamily: 'Poppins')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Settings
            const Text('Translation Options', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary, fontFamily: 'Poppins', letterSpacing: 1)),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Auto-Translate Messages', style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                    subtitle: const Text('Automatically translate all incoming messages', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint)),
                    value: _autoTranslate,
                    onChanged: (v) => setState(() => _autoTranslate = v),
                    activeColor: AppColors.primary,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Show Original Text', style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                    subtitle: const Text('Display original message alongside translation', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint)),
                    value: _showOriginal,
                    onChanged: (v) => setState(() => _showOriginal = v),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
