import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../models/message_model.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../../../shared/services/websocket_service.dart';
import '../../../shared/widgets/avatar_widget.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  const ChatScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isTyping = false;
  Timer? _typingTimer;
  String? _replyToId;
  String? _replyToContent;
  WebSocketService? _ws;

  @override
  void initState() {
    super.initState();
    _subscribeToWebSocket();
    _scrollController.addListener(_onScroll);
    _ws = ref.read(websocketServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ws?.joinConversation(widget.conversationId);
      // Mark the conversation as read when opening it
      ref.read(conversationsProvider.notifier).markRead(widget.conversationId);
    });
  }

  void _onScroll() {
    // List is reversed: reaching the far end (top of history) loads older messages
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(messagesProvider(widget.conversationId).notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _ws?.leaveConversation(widget.conversationId);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _subscribeToWebSocket() {
    final ws = ref.read(websocketServiceProvider);
    ws.messages.listen((event) {
      final eventType = event['event'] as String?;
      final data = event['data'] as Map<String, dynamic>? ?? {};

      switch (eventType) {
        case 'new_message':
          if (data['conversation_id'] == widget.conversationId) {
            final message = MessageModel.fromJson(data);
            ref.read(messagesProvider(widget.conversationId).notifier).prependMessage(message);
            _scrollToBottom();
          }
          break;
        case 'typing_indicator':
          if (data['conversation_id'] == widget.conversationId) {
            final userId = data['user_id'] as String;
            final isTyping = data['is_typing'] as bool;
            final typing = ref.read(typingUsersProvider(widget.conversationId));
            final updated = Set<String>.from(typing);
            if (isTyping) updated.add(userId); else updated.remove(userId);
            ref.read(typingUsersProvider(widget.conversationId).notifier).state = updated;
          }
          break;
        case 'message_status':
          final msgId = data['message_id'] as String?;
          final status = data['status'] as String?;
          if (msgId != null && status != null) {
            ref.read(messagesProvider(widget.conversationId).notifier).updateMessageStatus(msgId, status);
          }
          break;
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChanged(String text) {
    final ws = ref.read(websocketServiceProvider);
    final currentUser = ref.read(currentUserProvider);

    if (text.isNotEmpty && !_isTyping) {
      setState(() => _isTyping = true);
      ws.sendTyping(widget.conversationId, true, currentUser?.displayName ?? '');
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        setState(() => _isTyping = false);
        ws.sendTyping(widget.conversationId, false, currentUser?.displayName ?? '');
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    setState(() { _replyToId = null; _replyToContent = null; });

    try {
      await ref.read(messagesProvider(widget.conversationId).notifier).sendMessage(
        content: text,
        type: 'text',
        replyToId: _replyToId,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    await _recorder.start(const RecordConfig(), path: '/tmp/voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    setState(() => _isRecording = false);
    if (path != null && mounted) {
      await _sendAttachment(path, kind: 'voice', caption: 'Voice message');
    }
  }

  Future<void> _sendAttachment(String filePath, {required String kind, required String caption}) async {
    try {
      await ref.read(messagesProvider(widget.conversationId).notifier).sendAttachment(
            filePath: filePath,
            kind: kind,
            caption: caption,
            replyToId: _replyToId,
          );
      setState(() { _replyToId = null; _replyToContent = null; });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send attachment: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _pickImage({required bool fromCamera}) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 80,
    );
    if (image != null && mounted) {
      await _sendAttachment(image.path, kind: 'image', caption: 'Photo');
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    final file = result?.files.single;
    if (file?.path != null && mounted) {
      await _sendAttachment(file!.path!, kind: 'file', caption: file.name);
    }
  }

  void _setReply(MessageModel message) {
    setState(() {
      _replyToId = message.id;
      _replyToContent = message.originalContent ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messagesProvider(widget.conversationId));
    final currentUser = ref.watch(currentUserProvider);
    final typingUsers = ref.watch(typingUsersProvider(widget.conversationId));
    final preferredLanguage = currentUser?.preferredLanguage ?? 'english';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: _buildAppBar(typingUsers),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (messages) => messages.isEmpty
                  ? _buildEmptyMessages()
                  : ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (context, i) {
                        final msg = messages[i];
                        final isMe = msg.senderId == currentUser?.id;
                        final showDate = i == messages.length - 1 ||
                            !_isSameDay(msg.createdAt, messages[i + 1].createdAt);

                        return Column(
                          children: [
                            if (showDate) _buildDateSeparator(msg.createdAt),
                            MessageBubble(
                              message: msg,
                              isMe: isMe,
                              preferredLanguage: preferredLanguage,
                              onReply: () => _setReply(msg),
                              onLongPress: () => _showMessageOptions(msg, isMe),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),

          // Typing indicator
          if (typingUsers.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 16, bottom: 4),
              child: Align(alignment: Alignment.centerLeft, child: TypingIndicatorWidget()),
            ),

          // Input area
          _buildInputArea(),
        ],
      ),
    );
  }

  AppBar _buildAppBar(Set<String> typingUsers) {
    final conversationsAsync = ref.watch(conversationsProvider);
    final currentUser = ref.watch(currentUserProvider);

    String title = 'Chat';
    String? avatarUrl;
    bool isOnline = false;

    conversationsAsync.whenData((convs) {
      final conv = convs.firstWhere((c) => c.id == widget.conversationId, orElse: () => convs.first);
      title = conv.getDisplayName(currentUser?.id ?? '');
      avatarUrl = conv.getDisplayAvatar(currentUser?.id ?? '');
      isOnline = conv.getOtherUserOnlineStatus(currentUser?.id ?? '');
    });

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      title: Row(
        children: [
          UserAvatar(displayName: title, avatarUrl: avatarUrl, isOnline: isOnline, size: AvatarSize.small),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Poppins')),
                Text(
                  typingUsers.isNotEmpty ? 'typing...' : (isOnline ? 'Online' : 'Offline'),
                  style: TextStyle(
                    fontSize: 12,
                    color: typingUsers.isNotEmpty ? AppColors.primary : (isOnline ? AppColors.online : AppColors.textHint),
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () {}),
        IconButton(icon: const Icon(Icons.call_outlined), onPressed: () {}),
        IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
      ],
    );
  }

  Widget _buildInputArea() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Reply preview
            if (_replyToId != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppColors.primary.withOpacity(0.05),
                child: Row(
                  children: [
                    Container(width: 3, height: 36, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Replying to', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600, fontFamily: 'Poppins')),
                          Text(_replyToContent ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFamily: 'Poppins')),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() { _replyToId = null; _replyToContent = null; }),
                    ),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Attachment button
                  IconButton(
                    icon: const Icon(Icons.attach_file, color: AppColors.textSecondary),
                    onPressed: _showAttachmentOptions,
                  ),

                  // Text field
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: TextField(
                        controller: _messageController,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: _onTextChanged,
                        decoration: const InputDecoration(
                          hintText: 'Message...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Send or microphone
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _messageController,
                    builder: (context, value, _) {
                      final hasText = value.text.trim().isNotEmpty;
                      return GestureDetector(
                        onTap: hasText ? _sendMessage : null,
                        onLongPressStart: !hasText ? (_) => _startRecording() : null,
                        onLongPressEnd: !hasText ? (_) => _stopRecording() : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _isRecording ? AppColors.error : AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isRecording ? Icons.stop : (hasText ? Icons.send : Icons.mic),
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _AttachOption(icon: Icons.photo, label: 'Gallery', color: Colors.purple, onTap: () { Navigator.pop(context); _pickImage(fromCamera: false); }),
                  _AttachOption(icon: Icons.camera_alt, label: 'Camera', color: Colors.blue, onTap: () { Navigator.pop(context); _pickImage(fromCamera: true); }),
                  _AttachOption(icon: Icons.insert_drive_file, label: 'File', color: Colors.orange, onTap: () { Navigator.pop(context); _pickFile(); }),
                  _AttachOption(icon: Icons.mic, label: 'Voice', color: Colors.green, onTap: () { Navigator.pop(context); _startRecording(); }),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showReactionPicker(MessageModel message) {
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: emojis
                .map((e) => GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          await ref.read(messagesProvider(widget.conversationId).notifier).toggleReaction(message.id, e);
                        } catch (_) {}
                      },
                      child: Text(e, style: const TextStyle(fontSize: 32)),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  void _editMessage(MessageModel message) {
    final controller = TextEditingController(text: message.originalContent ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message', style: TextStyle(fontFamily: 'Poppins')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          style: const TextStyle(fontFamily: 'Poppins'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final text = controller.text.trim();
              if (text.isEmpty || text == message.originalContent) return;
              try {
                await ref.read(messagesProvider(widget.conversationId).notifier).editMessage(message.id, text);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to edit: $e'), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(MessageModel message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?', style: TextStyle(fontFamily: 'Poppins')),
        content: const Text('This message will be removed for everyone.', style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(messagesProvider(widget.conversationId).notifier).deleteMessage(message.id);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete: $e'), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(MessageModel message, bool isMe) {
    if (message.isDeleted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
            // Quick reactions
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['👍', '❤️', '😂', '😮', '😢', '🙏']
                    .map((e) => GestureDetector(
                          onTap: () async {
                            Navigator.pop(context);
                            try {
                              await ref.read(messagesProvider(widget.conversationId).notifier).toggleReaction(message.id, e);
                            } catch (_) {}
                          },
                          child: Text(e, style: const TextStyle(fontSize: 26)),
                        ))
                    .toList(),
              ),
            ),
            ListTile(leading: const Icon(Icons.reply), title: const Text('Reply'), onTap: () { Navigator.pop(context); _setReply(message); }),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Text'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.originalContent ?? ''));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.emoji_emotions_outlined),
              title: const Text('React'),
              onTap: () { Navigator.pop(context); _showReactionPicker(message); },
            ),
            if (isMe && message.isText)
              ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit'), onTap: () { Navigator.pop(context); _editMessage(message); }),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text('Delete', style: TextStyle(color: AppColors.error)),
                onTap: () { Navigator.pop(context); _confirmDelete(message); },
              ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    String label;
    if (_isSameDay(date, now)) label = 'Today';
    else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) label = 'Yesterday';
    else label = '${date.day}/${date.month}/${date.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textHint, fontFamily: 'Poppins')),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  Widget _buildEmptyMessages() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('👋', style: TextStyle(fontSize: 56)),
          SizedBox(height: 12),
          Text('Start the conversation!', style: TextStyle(fontSize: 16, color: AppColors.textSecondary, fontFamily: 'Poppins')),
          SizedBox(height: 4),
          Text('Messages are translated automatically', style: TextStyle(fontSize: 12, color: AppColors.textHint, fontFamily: 'Poppins')),
        ],
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachOption({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontFamily: 'Poppins', color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
