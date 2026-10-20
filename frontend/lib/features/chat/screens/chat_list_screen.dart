import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../app/theme/app_colors.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../models/conversation_model.dart';
import '../providers/chat_provider.dart';
import '../../../shared/widgets/avatar_widget.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversationsAsync = ref.watch(conversationsProvider);
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 68,
        title: const Text(
          'UbumweConnect',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textOnPrimary, fontFamily: 'Poppins'),
        ),
        actions: [
          IconButton(
            tooltip: _isSearching ? 'Close search' : 'Search conversations',
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) { _searchController.clear(); _searchQuery = ''; }
            }),
          ),
          IconButton(tooltip: 'Notifications', icon: const Icon(Icons.notifications_outlined), onPressed: () => _showNotifications(context)),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_isSearching ? 116 : 52),
          child: Column(children: [
            if (_isSearching) Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (value) => setState(() => _searchQuery = value.trim()),
                decoration: InputDecoration(
                  hintText: 'Search conversations',
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                  suffixIcon: _searchQuery.isEmpty ? null : IconButton(
                    tooltip: 'Clear search', icon: const Icon(Icons.clear),
                    onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); },
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.textOnPrimary,
              unselectedLabelColor: Colors.white70,
              indicatorColor: AppColors.textOnPrimary,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14),
              tabs: const [Tab(text: 'All'), Tab(text: 'Direct'), Tab(text: 'Groups')],
            ),
          ]),
        ),
      ),
      body: conversationsAsync.when(
        loading: () => _buildShimmer(),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text('Failed to load chats', style: TextStyle(color: AppColors.textSecondary)),
              TextButton(onPressed: () => ref.invalidate(conversationsProvider), child: const Text('Retry')),
            ],
          ),
        ),
        data: (conversations) {
          if (conversations.isEmpty) return _buildEmptyState(filter: null);

          final currentUserId = currentUser?.id ?? '';
          final preferredLanguage = currentUser?.preferredLanguage ?? 'english';

          return TabBarView(
            controller: _tabController,
            children: [
              _buildConversationList(conversations, currentUserId, preferredLanguage, null),
              _buildConversationList(conversations, currentUserId, preferredLanguage, 'direct'),
              _buildConversationList(conversations, currentUserId, preferredLanguage, 'group'),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/new-conversation'),
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }

  Widget _buildConversationList(List<ConversationModel> conversations, String currentUserId, String preferredLanguage, String? filter) {
    var filtered = filter != null ? conversations.where((c) => c.type == filter).toList() : conversations;
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((c) {
        final name = c.getDisplayName(currentUserId).toLowerCase();
        return name.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    if (filtered.isEmpty) return _buildEmptyState(filter: filter, isSearchResult: _searchQuery.isNotEmpty);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(conversationsProvider),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.5, indent: 72, endIndent: 16, color: AppColors.divider),
        itemBuilder: (context, i) => _ConversationTile(
          conversation: filtered[i],
          currentUserId: currentUserId,
          preferredLanguage: preferredLanguage,
          onTap: () => context.push('/chat/${filtered[i].id}'),
        ),
      ),
    );
  }

  /// Notifications panel: unread conversations and a muted-notifications note.
  void _showNotifications(BuildContext context) {
    final conversationsAsync = ref.watch(conversationsProvider);
    final unread = conversationsAsync.valueOrNull?.where((c) => c.unreadCount > 0).toList() ?? [];
    final currentUserId = ref.watch(currentUserProvider)?.id ?? '';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetCtx).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: unread.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_none, size: 48, color: AppColors.textHint),
                            SizedBox(height: 12),
                            Text('You\'re all caught up', style: TextStyle(fontFamily: 'Poppins', fontSize: 15, color: AppColors.textSecondary)),
                            SizedBox(height: 4),
                            Text('No unread messages', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: unread.length,
                        itemBuilder: (ctx, i) {
                          final conv = unread[i];
                          final name = conv.getDisplayName(currentUserId);
                          return ListTile(
                            leading: UserAvatar(displayName: name, avatarUrl: conv.getDisplayAvatar(currentUserId), size: AvatarSize.medium),
                            title: Text(name, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text('${conv.unreadCount} new message${conv.unreadCount > 1 ? 's' : ''}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint)),
                            trailing: Text(timeago.format(conv.lastMessage?.createdAt ?? DateTime.now(), locale: 'en_short'), style: const TextStyle(fontSize: 11, color: AppColors.textHint, fontFamily: 'Poppins')),
                            onTap: () {
                              Navigator.pop(sheetCtx);
                              context.push('/chat/${conv.id}');
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        itemCount: 8,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const CircleAvatar(radius: 28, backgroundColor: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 14, width: 120, color: Colors.white, margin: const EdgeInsets.only(bottom: 6)),
                    Container(height: 12, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({String? filter, bool isSearchResult = false}) {
    final String title;
    final String subtitle;
    final IconData icon;

    if (isSearchResult) {
      title = 'No conversations found';
      subtitle = 'Try another name or clear your search';
      icon = Icons.search_off;
    } else {
      switch (filter) {
        case 'direct':
          title = 'No direct messages';
          subtitle = 'Start a one-on-one conversation with a contact';
          icon = Icons.person_outline;
          break;
        case 'group':
          title = 'No group chats';
          subtitle = 'Create a group to chat with multiple people';
          icon = Icons.group_outlined;
          break;
        default:
          title = 'No conversations yet';
          subtitle = 'Start a conversation to connect across languages';
          icon = Icons.forum_outlined;
      }
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .08), shape: BoxShape.circle),
            child: Icon(icon, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFamily: 'Poppins'),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Poppins'),
          ),
          const SizedBox(height: 24),
          if (!isSearchResult)
            ElevatedButton.icon(
              onPressed: () => context.push('/new-conversation'),
              icon: const Icon(Icons.add),
              label: const Text('New Conversation'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(160, 48)),
            ),
        ],
      ),
    );
  }

}

class _ConversationTile extends StatelessWidget {
  final ConversationModel conversation;
  final String currentUserId;
  final String preferredLanguage;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.currentUserId,
    required this.preferredLanguage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = conversation.getDisplayName(currentUserId);
    final avatarUrl = conversation.getDisplayAvatar(currentUserId);
    final isOnline = conversation.getOtherUserOnlineStatus(currentUserId);
    final lastMsg = conversation.lastMessage;
    final lastMsgText = lastMsg?.getContentForLanguage(preferredLanguage) ?? '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            UserAvatar(
              displayName: displayName,
              avatarUrl: avatarUrl,
              isOnline: isOnline,
              size: AvatarSize.medium,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFamily: 'Poppins'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (lastMsg != null)
                        Text(
                          timeago.format(lastMsg.createdAt, locale: 'en_short'),
                          style: TextStyle(
                            fontSize: 11,
                            color: conversation.unreadCount > 0 ? AppColors.primary : AppColors.textHint,
                            fontFamily: 'Poppins',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastMsg?.isDeleted == true ? 'Message deleted' : (lastMsgText.isEmpty ? 'No messages yet' : lastMsgText),
                          style: TextStyle(
                            fontSize: 13,
                            color: conversation.unreadCount > 0 ? AppColors.textPrimary : AppColors.textSecondary,
                            fontWeight: conversation.unreadCount > 0 ? FontWeight.w500 : FontWeight.w400,
                            fontFamily: 'Poppins',
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (conversation.unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${conversation.unreadCount}',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'Poppins'),
                          ),
                        ),
                    ],
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

