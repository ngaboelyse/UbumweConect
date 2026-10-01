import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../models/message_model.dart';

class MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final String preferredLanguage;
  final VoidCallback? onReply;
  final VoidCallback? onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.preferredLanguage,
    this.onReply,
    this.onLongPress,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    if (widget.message.isSystem) return _buildSystemMessage();

    final content = _showOriginal
        ? (widget.message.originalContent ?? '')
        : widget.message.getContentForLanguage(widget.preferredLanguage);

    final isTranslated = !_showOriginal &&
        widget.message.hasTranslation(widget.preferredLanguage) &&
        widget.message.originalContent != content;

    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!widget.isMe) const SizedBox(width: 4),

            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                child: Column(
                  crossAxisAlignment: widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    // Bubble
                    Container(
                      decoration: BoxDecoration(
                        color: widget.isMe ? AppColors.sentBubble : AppColors.receivedBubble,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(widget.isMe ? 18 : 4),
                          bottomRight: Radius.circular(widget.isMe ? 4 : 18),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Message content
                            if (widget.message.isText)
                              Text(
                                content,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: widget.isMe ? AppColors.sentBubbleText : AppColors.receivedBubbleText,
                                  fontFamily: 'Poppins',
                                  height: 1.4,
                                ),
                              )
                            else if (widget.message.isVoice)
                              _buildVoiceMessage()
                            else if (widget.message.isImage)
                              _buildImageMessage()
                            else
                              Text(content, style: TextStyle(fontSize: 15, color: widget.isMe ? Colors.white : AppColors.textPrimary, fontFamily: 'Poppins')),

                            const SizedBox(height: 4),

                            // Translation badge
                            if (isTranslated)
                              GestureDetector(
                                onTap: () => setState(() => _showOriginal = !_showOriginal),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.translate, size: 12, color: widget.isMe ? Colors.white70 : AppColors.textHint),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Translated from ${widget.message.getTranslationSource() ?? 'Unknown'}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: widget.isMe ? Colors.white70 : AppColors.textHint,
                                        fontFamily: 'Poppins',
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            if (_showOriginal)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${widget.message.originalContent}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: widget.isMe ? Colors.white60 : AppColors.textSecondary,
                                    fontFamily: 'Poppins',
                                  ),
                                ),
                              ),

                            const SizedBox(height: 4),

                            // Edited indicator
                            if (widget.message.isEdited)
                              Text(
                                'edited',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontStyle: FontStyle.italic,
                                  color: widget.isMe ? Colors.white60 : AppColors.textHint,
                                  fontFamily: 'Poppins',
                                ),
                              ),

                            // Timestamp & status
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatTime(widget.message.createdAt),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: widget.isMe ? Colors.white60 : AppColors.textHint,
                                    fontFamily: 'Poppins',
                                  ),
                                ),
                                if (widget.isMe) ...[
                                  const SizedBox(width: 4),
                                  _buildStatusIcon(),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Reactions row below the bubble
                    _buildReactionsRow(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (widget.message.status) {
      case 'read':
        return const Icon(Icons.done_all, size: 14, color: Colors.lightBlueAccent);
      case 'delivered':
        return const Icon(Icons.done_all, size: 14, color: Colors.white60);
      default:
        return const Icon(Icons.done, size: 14, color: Colors.white60);
    }
  }

  Widget _buildVoiceMessage() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.play_arrow, color: widget.isMe ? Colors.white : AppColors.primary, size: 32),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 32,
                child: Row(
                  children: List.generate(20, (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    width: 3,
                    height: (i % 3 + 1) * 8.0,
                    decoration: BoxDecoration(
                      color: (widget.isMe ? Colors.white : AppColors.primary).withOpacity(0.7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )),
                ),
              ),
              if (widget.message.durationSeconds != null)
                Text(
                  '${widget.message.durationSeconds!.toInt()}s',
                  style: TextStyle(fontSize: 11, color: widget.isMe ? Colors.white70 : AppColors.textHint, fontFamily: 'Poppins'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImageMessage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        widget.message.fileUrl ?? '',
        width: 200,
        height: 200,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 200, height: 200,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildSystemMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.textHint.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.message.originalContent ?? '',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFamily: 'Poppins'),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildReactionsRow() {
    final counts = widget.message.reactionCounts;
    if (counts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: 4, right: widget.isMe ? 8 : 0, left: widget.isMe ? 0 : 8),
      child: Wrap(
        spacing: 4,
        children: counts.entries.map((entry) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Text(
              '${entry.key} ${entry.value > 1 ? entry.value : ''}'.trim(),
              style: const TextStyle(fontSize: 12, fontFamily: 'Poppins'),
            ),
          );
        }).toList(),
      ),
    );
  }
}
