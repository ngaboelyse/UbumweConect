import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../shared/services/api_service.dart';

import '../../../shared/widgets/avatar_widget.dart' show resolveMediaUrl;

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _displayNameController;
  late TextEditingController _usernameController;
  late TextEditingController _bioController;
  String? _selectedLanguage;
  File? _avatarFile;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _displayNameController = TextEditingController(text: user?.displayName ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
    _selectedLanguage = user?.preferredLanguage ?? 'english';
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512, imageQuality: 80);
    if (picked != null) {
      setState(() => _avatarFile = File(picked.path));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      // Upload avatar if changed
      if (_avatarFile != null) {
        final api = ref.read(apiServiceProvider);
        await api.postMultipart(
          '/users/avatar',
          FormData.fromMap({
            'file': await MultipartFile.fromFile(
              _avatarFile!.path,
              filename: 'avatar.jpg',
            ),
          }),
        );
      }

      await ref.read(authNotifierProvider.notifier).updateProfile(
        displayName: _displayNameController.text.trim(),
        bio: _bioController.text.trim(),
        preferredLanguage: _selectedLanguage,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated!'), backgroundColor: AppColors.success),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Edit Profile', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Avatar picker
              Center(
                child: GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                        backgroundImage: _avatarFile != null
                            ? FileImage(_avatarFile!)
                            : (user?.avatarUrl != null
                                ? NetworkImage(resolveMediaUrl(user!.avatarUrl!)) as ImageProvider
                                : null),
                        child: (_avatarFile == null && user?.avatarUrl == null)
                            ? Text(
                                user?.initials ?? 'U',
                                style: const TextStyle(fontSize: 36, color: AppColors.primary, fontWeight: FontWeight.w700, fontFamily: 'Poppins'),
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('Tap to change photo', style: TextStyle(fontSize: 12, color: AppColors.textHint, fontFamily: 'Poppins')),
              const SizedBox(height: 32),

              // Display Name
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Display name is required' : null,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),

              // Username
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.alternate_email),
                  prefixText: '@',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Username is required';
                  if (v.contains(' ')) return 'Username cannot contain spaces';
                  if (v.length < 3) return 'Username must be at least 3 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Bio
              TextFormField(
                controller: _bioController,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  prefixIcon: Icon(Icons.info_outline),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                maxLength: 200,
              ),
              const SizedBox(height: 16),

              // Language
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Preferred Language', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontFamily: 'Poppins')),
              ),
              const SizedBox(height: 8),
              ...AppConstants.supportedLanguages.map((lang) {
                final isSelected = lang['code'] == _selectedLanguage;
                return GestureDetector(
                  onTap: () => setState(() => _selectedLanguage = lang['code']),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary.withOpacity(0.08) : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? AppColors.primary : AppColors.divider, width: isSelected ? 2 : 1),
                    ),
                    child: Row(
                      children: [
                        Text(lang['flag']!, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Text(lang['native']!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isSelected ? AppColors.primary : AppColors.textPrimary, fontFamily: 'Poppins')),
                        const Spacer(),
                        if (isSelected) const Icon(Icons.check_circle, color: AppColors.primary),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
