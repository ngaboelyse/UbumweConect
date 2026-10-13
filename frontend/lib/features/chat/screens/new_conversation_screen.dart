import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../features/auth/models/user_model.dart';
import '../providers/chat_provider.dart';
import 'contacts_screen.dart';
import '../../../shared/widgets/avatar_widget.dart';

class NewConversationScreen extends ConsumerStatefulWidget {
  const NewConversationScreen({super.key});

  @override
  ConsumerState<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends ConsumerState<NewConversationScreen> {
  bool _isGroup = false;
  final _groupNameController = TextEditingController();
  final Set<UserModel> _selected = {};
  bool _isCreating = false;

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_selected.isEmpty) return;
    if (_isGroup && _groupNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a group name')));
      return;
    }
    setState(() => _isCreating = true);
    try {
      final conv = await ref.read(conversationsProvider.notifier).createConversation(
        participantIds: _selected.map((u) => u.id).toList(),
        type: _isGroup ? 'group' : 'direct',
        name: _isGroup ? _groupNameController.text.trim() : null,
      );
      if (mounted) {
        context.pop();
        context.push('/chat/${conv.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('New Conversation', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: _isCreating ? null : _create,
              child: _isCreating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Type selector
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() { _isGroup = false; if (_selected.length > 1) _selected.remove(_selected.last); }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_isGroup ? AppColors.primary : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                        border: Border.all(color: AppColors.primary),
                      ),
                      child: Center(child: Text('Direct Message', style: TextStyle(color: !_isGroup ? Colors.white : AppColors.primary, fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isGroup = true),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _isGroup ? AppColors.primary : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                        border: Border.all(color: AppColors.primary),
                      ),
                      child: Center(child: Text('Group', style: TextStyle(color: _isGroup ? Colors.white : AppColors.primary, fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_isGroup)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _groupNameController,
                decoration: const InputDecoration(labelText: 'Group Name', prefixIcon: Icon(Icons.group)),
              ),
            ),

          if (_selected.isNotEmpty)
            SizedBox(
              height: 64,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                scrollDirection: Axis.horizontal,
                itemCount: _selected.length,
                itemBuilder: (_, i) {
                  final user = _selected.elementAt(i);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        UserAvatar(displayName: user.displayName, avatarUrl: user.avatarUrl, size: AvatarSize.medium),
                        Positioned(
                          top: 0, right: 0,
                          child: GestureDetector(
                            onTap: () => setState(() => _selected.remove(user)),
                            child: Container(
                              width: 16, height: 16,
                              decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 10, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          const Divider(height: 1),

          Expanded(
            child: contactsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (contacts) => ListView.builder(
                itemCount: contacts.length,
                itemBuilder: (_, i) {
                  final contact = contacts[i];
                  final isSelected = _selected.contains(contact);
                  return ListTile(
                    leading: UserAvatar(displayName: contact.displayName, avatarUrl: contact.avatarUrl, isOnline: contact.isOnline, size: AvatarSize.medium),
                    title: Text(contact.displayName, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                    subtitle: Text('@${contact.username}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint)),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: AppColors.primary) : const Icon(Icons.circle_outlined, color: AppColors.textHint),
                    onTap: () {
                      if (!_isGroup && !isSelected) {
                        setState(() { _selected.clear(); _selected.add(contact); });
                      } else {
                        setState(() { if (isSelected) {
                          _selected.remove(contact);
                        } else {
                          _selected.add(contact);
                        } });
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
