import 'dart:convert' show base64Encode;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart' show ConsumerStatefulWidget, ConsumerState;
import 'package:url_launcher/url_launcher.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/local_storage_service.dart';
import '../../../shared/widgets/avatar_widget.dart' show resolveMediaUrl;
import '../models/message_model.dart';
import 'audio_playback.dart';

/// Resolve a server-relative URL (e.g. /files/...) against the API host.
String _resolveUrl(String url) {
  if (url.startsWith('http')) return url;
  final origin = AppConstants.baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');
  return '$origin$url';
}

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
  AudioPlayer? _audioPlayer;
  AudioPlayback? _webAudio;
  bool _isPlaying = false;
  bool _isTtsPlaying = false;
  bool _ttsLoading = false;
  AudioPlayer? _ttsPlayer;
  AudioPlayback? _ttsWebAudio;

  Future<void> _togglePlay() async {
    final url = widget.message.audioUrl;
    if (url == null || url.isEmpty) return;
    final resolved = _resolveUrl(url);

    if (kIsWeb) {
      // Use the browser's own <audio> element — the most reliable path on web.
      if (_isPlaying) {
        _webAudio?.pause();
        if (mounted) setState(() => _isPlaying = false);
        return;
      }
      final a = _webAudio ?? WebAudio();
      _webAudio = a;
      try {
        await a.play(resolved, () {
          if (mounted) setState(() => _isPlaying = false);
        });
        if (mounted) setState(() => _isPlaying = true);
      } catch (e) {
        debugPrint('Audio playback failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not play audio: $e'), backgroundColor: AppColors.error),
          );
          setState(() => _isPlaying = false);
        }
      }
      return;
    }

    // Native platforms: audioplayers.
    _audioPlayer ??= AudioPlayer();
    final player = _audioPlayer!;
    try {
      if (_isPlaying) {
        await player.stop();
        if (mounted) setState(() => _isPlaying = false);
      } else {
        player.onPlayerComplete.first.then((_) {
          if (mounted) setState(() => _isPlaying = false);
        });
        await player.play(UrlSource(resolved));
        if (mounted) setState(() => _isPlaying = true);
      }
    } catch (e) {
      debugPrint('Audio playback failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not play audio: $e'), backgroundColor: AppColors.error),
        );
      }
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    _webAudio?.pause();
    _ttsPlayer?.dispose();
    _ttsWebAudio?.pause();
    super.dispose();
  }

  /// Play (or fetch+play) the TTS audio of this voice note in the viewer's
  /// preferred language. Text messages use the translated content; voice notes
  /// use the Whisper transcript already stored in translated_contents.
  Future<void> _toggleTranslatedAudio() async {
    final msg = widget.message;
    final translated = msg.getContentForLanguage(widget.preferredLanguage);
    if (translated.isEmpty) return;

    if (_isTtsPlaying) {
      if (kIsWeb) {
        _ttsWebAudio?.pause();
      } else {
        await _ttsPlayer?.stop();
      }
      if (mounted) setState(() => _isTtsPlaying = false);
      return;
    }

    if (mounted) setState(() => _ttsLoading = true);
    try {
      // Ask the backend to synthesize speech in the preferred language.
      // Token must be sent explicitly — this standalone Dio instance has no
      // auth interceptor, and the endpoint requires a Bearer token.
      final token = await LocalStorageService().getAccessToken();
      final response = await dio_pkg.Dio(
        dio_pkg.BaseOptions(
          baseUrl: AppConstants.baseUrl,
          responseType: dio_pkg.ResponseType.bytes,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'audio/mpeg',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      ).post('/translation/tts', data: {
        'text': translated,
        'language': widget.preferredLanguage,
      });
      final bytes = response.data as List<int>;

      if (kIsWeb) {
        final a = _ttsWebAudio ?? WebAudio();
        _ttsWebAudio = a;
        // WebAudio plays from a URL; serve the bytes via a blob data URI is
        // not available, so fall back to the data: URL with base64.
        final base64Audio = base64Encode(Uint8List.fromList(bytes));
        await a.play('data:audio/mpeg;base64,$base64Audio', () {
          if (mounted) setState(() => _isTtsPlaying = false);
        });
        if (mounted) setState(() => _isTtsPlaying = true);
      } else {
        _ttsPlayer ??= AudioPlayer();
        final player = _ttsPlayer!;
        player.onPlayerComplete.first.then((_) {
          if (mounted) setState(() => _isTtsPlaying = false);
        });
        // Play the synthesized MP3 directly from memory.
        await player.play(BytesSource(Uint8List.fromList(bytes)));
        if (mounted) setState(() => _isTtsPlaying = true);
      }
    } catch (e) {
      debugPrint('TTS playback failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not synthesize speech: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _ttsLoading = false);
    }
  }

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
                    // Bubble (WhatsApp style)
                    Container(
                      decoration: BoxDecoration(
                        color: widget.isMe ? AppColors.sentBubble : AppColors.receivedBubble,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(8),
                          topRight: const Radius.circular(8),
                          bottomLeft: Radius.circular(widget.isMe ? 8 : 0),
                          bottomRight: Radius.circular(widget.isMe ? 0 : 8),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 1,
                            offset: const Offset(0, 1),
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
                                   color: AppColors.receivedBubbleText,
                                   fontFamily: 'Poppins',
                                   height: 1.4,
                                 ),
                               )
                            else if (widget.message.isVoice)
                              _buildVoiceMessage()
                            else if (widget.message.isImage)
                              _buildImageMessage()
                            else if (widget.message.isFile)
                              _buildFileMessage()
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
                                                                  color: widget.isMe ? Colors.grey[700] : AppColors.textHint,
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
                                      return const Icon(Icons.done_all, size: 14, color: AppColors.primaryLight);
                                    case 'delivered':
                                      return const Icon(Icons.done_all, size: 14, color: AppColors.textHint);
                                    default:
                                      return const Icon(Icons.done, size: 14, color: AppColors.textHint);
                                  }
                                }

  Widget _buildVoiceMessage() {
    final msg = widget.message;
    final translatedText = msg.getContentForLanguage(widget.preferredLanguage);
    final hasTranscript = translatedText.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _togglePlay,
              child: Icon(
                _isPlaying ? Icons.pause_circle_filled : Icons.play_arrow,
                color: widget.isMe ? Colors.white : AppColors.primary,
                size: 32,
              ),
            ),
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
                          color: (widget.isMe ? Colors.white : AppColors.primary).withOpacity(_isPlaying ? 0.95 : 0.7),
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
            // Listen to the voice note spoken in YOUR language (TTS).
            if (hasTranscript) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _ttsLoading ? null : _toggleTranslatedAudio,
                child: _ttsLoading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.isMe ? Colors.white : AppColors.primary,
                        ),
                      )
                    : Icon(
                        _isTtsPlaying ? Icons.pause_circle_outline : Icons.graphic_eq,
                        color: widget.isMe ? Colors.white : AppColors.primary,
                        size: 24,
                      ),
              ),
            ],
          ],
        ),
        // Transcript / translated text under the waveform.
        if (hasTranscript) ...[
          const SizedBox(height: 6),
          Text(
            translatedText,
            style: TextStyle(
              fontSize: 13,
              color: widget.isMe ? Colors.white : AppColors.textPrimary,
              fontFamily: 'Poppins',
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  /// Downloadable document/file attachment (pdf, docx, zip, ...).
  Widget _buildFileMessage() {
    final url = widget.message.fileUrl ?? '';
    final name = widget.message.fileName ?? 'Document';
    final sizeKb = widget.message.fileSize;
    final sizeLabel = sizeKb == null
        ? ''
        : sizeKb > 1024 * 1024
            ? ' ${(sizeKb / (1024 * 1024)).toStringAsFixed(1)} MB'
            : ' ${(sizeKb / 1024).toStringAsFixed(0)} KB';

    return InkWell(
      onTap: () async {
        if (url.isEmpty) return;
        final resolved = _resolveUrl(url);
        final uri = Uri.tryParse(resolved);
        if (uri == null) return;
        try {
          final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!launched && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No app available to open this file')),
            );
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open file')),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (widget.isMe ? Colors.white : AppColors.primary).withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file, color: widget.isMe ? Colors.white : AppColors.primary, size: 28),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: widget.isMe ? Colors.white : AppColors.textPrimary, fontFamily: 'Poppins'),
                  ),
                  if (sizeLabel.isNotEmpty)
                    Text(sizeLabel.trim(), style: TextStyle(fontSize: 11, color: widget.isMe ? Colors.white70 : AppColors.textHint, fontFamily: 'Poppins')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageMessage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        resolveMediaUrl(widget.message.fileUrl ?? ''),
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
