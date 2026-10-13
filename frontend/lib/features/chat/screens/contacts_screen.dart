import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../features/auth/models/user_model.dart';
import '../providers/chat_provider.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/widgets/avatar_widget.dart';

final contactsProvider = FutureProvider<List<UserModel>>((ref) async {
  final api = ref.read(apiServiceProvider);
  final data = await api.getList('/users/contacts/list');
  if (data is List) {
    return data.map((u) => UserModel.fromJson(u as Map<String, dynamic>)).toList();
  }
  return [];
});

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Contacts', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
        actions: [
          IconButton(icon: const Icon(Icons.person_add_outlined), onPressed: () => _showAddContact()),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); })
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: contactsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
              data: (contacts) {
                final filtered = _searchQuery.isEmpty
                    ? contacts
                    : contacts.where((c) => c.displayName.toLowerCase().contains(_searchQuery.toLowerCase()) || c.username.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: SizedBox(
                      width: double.maxFinite,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('👥', style: TextStyle(fontSize: 56)),
                          SizedBox(height: 12),
                          Text('No contacts yet', style: TextStyle(fontSize: 16, color: AppColors.textSecondary, fontFamily: 'Poppins')),
                          SizedBox(height: 4),
                          Text('Add people to start chatting', style: TextStyle(fontSize: 13, color: AppColors.textHint, fontFamily: 'Poppins')),
                        ],
                      ),
                    ),
                  );
                }

                // Group by first letter
                final grouped = <String, List<UserModel>>{};
                for (final c in filtered) {
                  final name = c.displayName.trim();
                  final key = name.isEmpty ? '#' : name[0].toUpperCase();
                  grouped.putIfAbsent(key, () => []).add(c);
                }
                final keys = grouped.keys.toList()..sort();

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(contactsProvider),
                  child: ListView.builder(
                    itemCount: keys.length,
                    itemBuilder: (context, i) {
                      final letter = keys[i];
                      final group = grouped[letter]!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(letter, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary, fontFamily: 'Poppins')),
                          ),
                          ...group.map((contact) => _ContactTile(contact: contact)),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddContact() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _AddContactSheet(),
    );
  }
}

class _ContactTile extends ConsumerWidget {
  final UserModel contact;
  const _ContactTile({required this.contact});

  String _getLanguageFlag(String lang) {
    const flags = {'kinyarwanda': '🇷🇼', 'english': '🇬🇧', 'french': '🇫🇷', 'swahili': '🇹🇿'};
    return flags[lang] ?? '🌐';
  }

  Future<void> _startDirectChat(BuildContext context, WidgetRef ref) async {
    final navigator = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final conversation = await ref.read(conversationsProvider.notifier).createConversation(
        participantIds: [contact.id],
        type: 'direct',
      );
      navigator.push('/chat/${conversation.id}');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not start chat: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: UserAvatar(displayName: contact.displayName, avatarUrl: contact.avatarUrl, isOnline: contact.isOnline, size: AvatarSize.medium),
      title: Text(contact.displayName, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text('@${contact.username}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_getLanguageFlag(contact.preferredLanguage), style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Chat',
            icon: const Icon(Icons.chat_outlined, color: AppColors.primary),
            onPressed: () => _startDirectChat(context, ref),
          ),
        ],
      ),
      onTap: () => context.push('/user/${contact.id}'),
    );
  }
}

class _AddContactSheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends ConsumerState<_AddContactSheet> {
  final _controller = TextEditingController();
  List<dynamic> _results = [];
  bool _isSearching = false;

  Future<void> _search(String query) async {
    if (query.length < 2) return;
    setState(() => _isSearching = true);
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getList('/users/search?q=$query');
      setState(() => _results = data is List ? data : []);
    } catch (_) {} finally {
      setState(() => _isSearching = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
            const Text('Add Contact', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (v) => _search(v),
              decoration: const InputDecoration(hintText: 'Search by username or email', prefixIcon: Icon(Icons.search)),
            ),
            const SizedBox(height: 16),
            if (_isSearching) const Center(child: CircularProgressIndicator()),
            ..._results.map((r) {
              final user = r as Map<String, dynamic>;
              return ListTile(
                leading: UserAvatar(
                  displayName: user['display_name']?.toString() ?? '',
                  avatarUrl: user['avatar_url']?.toString(),
                  size: AvatarSize.medium,
                ),
                title: Text(user['display_name']?.toString() ?? '', style: const TextStyle(fontFamily: 'Poppins')),
                subtitle: Text('@${user['username'] ?? ''}', style: const TextStyle(fontFamily: 'Poppins')),
                trailing: ElevatedButton(
                  onPressed: () async {
                    final api = ref.read(apiServiceProvider);
                    await api.post('/users/contacts/${user['id']}');
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(80, 36)),
                  child: const Text('Add'),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
