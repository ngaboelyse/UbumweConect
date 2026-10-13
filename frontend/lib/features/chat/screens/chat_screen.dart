import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../calls/providers/call_controller.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../../../shared/services/websocket_service.dart';
import '../../../shared/services/api_service.dart';
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
  final List<Uint8List> _webChunks = [];
  StreamSubscription<Uint8List>? _streamSub;

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
    final replyToId = _replyToId; // capture BEFORE clearing state
    _messageController.clear();
    setState(() { _replyToId = null; _replyToContent = null; });

    try {
      await ref.read(messagesProvider(widget.conversationId).notifier).sendMessage(
        content: text,
        type: 'text',
        replyToId: replyToId,
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
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission denied. Enable it in app settings.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
      if (kIsWeb) {
        // Web: stream the recording into memory instead of a file path.
        // path_provider has no web implementation (MissingPluginException).
        _webChunks.clear();
        final stream = await _recorder.startStream(const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          numChannels: 1,
          sampleRate: 16000,
        ));
        _streamSub = stream.listen(_webChunks.add);
      } else {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(const RecordConfig(), path: path);
      }
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start recording: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      if (kIsWeb) {
        await _streamSub?.cancel();
        _streamSub = null;
        await _recorder.stop();
        if (mounted) setState(() => _isRecording = false);
        // Concatenate PCM chunks and encode a WAV container.
        final pcm = _webChunks.fold<List<int>>(<int>[], (acc, c) => acc..addAll(c));
        final bytes = Uint8List.fromList(pcm);
        final wav = _encodeWav(bytes, sampleRate: 16000, numChannels: 1, bitsPerSample: 16);
        if (mounted) {
          await _sendBytes(wav, 'voice_note.wav', kind: 'voice', caption: 'Voice message');
        }
        return;
      }
      final path = await _recorder.stop();
      if (mounted) setState(() => _isRecording = false);
      if (path != null && mounted) {
        await _sendAttachment(path, kind: 'voice', caption: 'Voice message');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to finish recording: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Send a voice note from in-memory bytes (used on web, where no file path exists).
  Future<void> _sendBytes(Uint8List bytes, String fileName, {required String kind, required String caption}) async {
    try {
      await ref.read(messagesProvider(widget.conversationId).notifier).sendAttachment(
            filePath: fileName,
            kind: kind,
            caption: caption,
            replyToId: _replyToId,
            fileBytes: bytes,
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

  /// Wrap raw PCM data in a WAV container.
  Uint8List _encodeWav(Uint8List pcm, {required int sampleRate, required int numChannels, required int bitsPerSample}) {
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    final header = BytesBuilder();
    header.add('RIFF'.codeUnits);
    header.add(_u32(36 + pcm.length));
    header.add('WAVE'.codeUnits);
    header.add('fmt '.codeUnits);
    header.add(_u32(16));
    header.add(_u16(1)); // PCM
    header.add(_u16(numChannels));
    header.add(_u32(sampleRate));
    header.add(_u32(byteRate));
    header.add(_u16(blockAlign));
    header.add(_u16(bitsPerSample));
    header.add('data'.codeUnits);
    header.add(_u32(pcm.length));
    final out = BytesBuilder();
    out.add(header.takeBytes());
    out.add(pcm);
    return out.takeBytes();
  }

  Uint8List _u32(int v) => Uint8List(4)..[0] = v & 0xFF..[1] = (v >> 8) & 0xFF..[2] = (v >> 16) & 0xFF..[3] = (v >> 24) & 0xFF;
  Uint8List _u16(int v) => Uint8List(2)..[0] = v & 0xFF..[1] = (v >> 8) & 0xFF;

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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      // withData loads the bytes into memory, which is required on web where
      // picked files have no real filesystem path.
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || !mounted) return;
    if (file.bytes != null) {
      await _sendBytes(file.bytes!, file.name, kind: 'file', caption: file.name);
    } else if (file.path != null) {
      await _sendAttachment(file.path!, kind: 'file', caption: file.name);
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

  /// Creates the call on the backend and opens the outgoing-call screen.
  Future<void> _startCall(CallType type) async {
    final currentUser = ref.read(currentUserProvider);
    final convs = ref.read(conversationsProvider).valueOrNull ?? [];
    ConversationModel? conv;
    for (final c in convs) {
      if (c.id == widget.conversationId) {
        conv = c;
        break;
      }
    }
    if (conv == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Still loading conversation… try again in a moment'), backgroundColor: AppColors.error),
        );
      }
      return;
    }

    // For direct conversations, find the other participant.
    ParticipantModel? peer;
    for (final p in conv.participants) {
      if (p.userId != (currentUser?.id ?? '')) {
        peer = p;
        break;
      }
    }
    if (peer == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot call in this conversation'), backgroundColor: AppColors.error),
        );
      }
      return;
    }

    final callId = await ref.read(callControllerProvider.notifier).createCall(
          conversationId: conv.id,
          peerId: peer.userId,
          peerName: conv.getDisplayName(currentUser?.id ?? ''),
          peerAvatar: conv.getDisplayAvatar(currentUser?.id ?? ''),
          type: type,
        );
    if (callId == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start the call — is the server running?'), backgroundColor: AppColors.error),
        );
      }
      return;
    }

    final route = type == CallType.video ? '/call/video' : '/call/voice';
    if (mounted) context.push('$route/$callId');
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
        IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () => _startCall(CallType.video)),
        IconButton(icon: const Icon(Icons.call_outlined), onPressed: () => _startCall(CallType.voice)),
        IconButton(icon: const Icon(Icons.more_vert), onPressed: _showChatMenu),
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

  /// ⋮ menu in the chat AppBar: conversation info, in-chat search, view contact.
  void _showChatMenu() {
    final conversationsAsync = ref.watch(conversationsProvider);
    final currentUser = ref.watch(currentUserProvider);
    conversationsAsync.whenData((convs) {
      final conv = convs.where((c) => c.id == widget.conversationId).firstOrNull;
      if (conv == null || !mounted) return;
      final peer = conv.participants.firstWhere(
        (p) => p.userId != (currentUser?.id ?? ''),
        orElse: () => conv.participants.first,
      );

      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (sheetCtx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
              ListTile(
                leading: const Icon(Icons.person_search_outlined),
                title: const Text('View Contact', style: TextStyle(fontFamily: 'Poppins')),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  context.push('/user/${peer.userId}');
                },
              ),
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Search Messages', style: TextStyle(fontFamily: 'Poppins')),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showMessageSearch();
                },
              ),
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('Language Settings', style: TextStyle(fontFamily: 'Poppins')),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  context.push('/settings/language');
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Help & Support', style: TextStyle(fontFamily: 'Poppins')),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  context.push('/help');
                },
              ),
            ],
          ),
        ),
      );
    });
  }

  /// Search messages in this conversation via the backend endpoint.
  void _showMessageSearch() {
    final controller = TextEditingController();
    List<dynamic> results = [];
    bool searching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(sheetCtx).size.height * 0.7,
            child: Column(
              children: [
                Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search in this chat...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (q) async {
                      if (q.trim().length < 2) return;
                      setSheetState(() => searching = true);
                      try {
                        final data = await ref.read(apiServiceProvider).getList(
                              '/conversations/${widget.conversationId}/messages/search',
                              params: {'q': q.trim()},
                            );
                        results = data is List ? data : [];
                      } catch (_) {
                        results = [];
                      }
                      setSheetState(() => searching = false);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                if (searching)
                  const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
                Expanded(
                  child: ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (ctx, i) {
                      final m = results[i] as Map<String, dynamic>;
                      return ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(
                          m['original_content']?.toString() ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
                        ),
                        onTap: () => Navigator.pop(sheetCtx),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
