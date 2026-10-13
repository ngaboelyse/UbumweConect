import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/providers/chat_provider.dart';
import '../providers/call_controller.dart';
import '../widgets/remote_audio_player.dart';

class VoiceCallScreen extends ConsumerStatefulWidget {
  final String callId;
  const VoiceCallScreen({super.key, required this.callId});

  @override
  ConsumerState<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends ConsumerState<VoiceCallScreen> {
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _translationOn = false;
  String _duration = '00:00';
  Timer? _durationTimer;
  int _seconds = 0;

  // On web, remote audio only plays when attached to an <audio> element
  // (flutter_webrtc does that inside RTCVideoRenderer). No-op on mobile.
  final RemoteAudioPlayer _remoteAudio = RemoteAudioPlayerImpl();

  CallController get _call => ref.read(callControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    // The duration timer only ticks once the call is actually active.
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final phase = ref.read(callControllerProvider)?.phase;
      if (phase != CallPhase.active) return;
      _seconds++;
      final m = (_seconds ~/ 60).toString().padLeft(2, '0');
      final s = (_seconds % 60).toString().padLeft(2, '0');
      if (mounted) setState(() => _duration = '$m:$s');
    });
    // Attach now in case the call was already connected when this screen
    // opened (e.g. the callee tapped Accept).
    _remoteAudio.setStream(_call.remoteStream.value);
    _call.remoteStream.addListener(_onRemoteStream);
  }

  void _onRemoteStream() {
    _remoteAudio.setStream(_call.remoteStream.value);
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _call.remoteStream.removeListener(_onRemoteStream);
    _remoteAudio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(callControllerProvider);
    // The controller already ended the call and popped the route.
    if (session == null) return const SizedBox.shrink();

    final currentUser = ref.watch(currentUserProvider);
    final conversationsAsync = ref.watch(conversationsProvider);
    String peerName = session.peerName;
    String? peerAvatar = session.peerAvatar;
    conversationsAsync.whenData((convs) {
      final conv = convs.where((c) => c.id == session.conversationId).firstOrNull;
      if (conv != null) {
        peerName = conv.getDisplayName(currentUser?.id ?? '');
        peerAvatar = conv.getDisplayAvatar(currentUser?.id ?? '');
      }
    });

    final statusText = switch (session.phase) {
      CallPhase.outgoing => 'Ringing...',
      CallPhase.incoming => 'Incoming...',
      CallPhase.active => 'Connected',
      CallPhase.ended => session.error ?? 'Call ended',
      _ => 'Connecting...',
    };

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.callGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Text('Ubumwe Connect', style: TextStyle(color: Colors.white54, fontSize: 13, fontFamily: 'Poppins')),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.success.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                      child: Text(_duration, style: const TextStyle(color: AppColors.success, fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Caller info
              UserAvatar(displayName: peerName, avatarUrl: peerAvatar, size: AvatarSize.xlarge),
              const SizedBox(height: 20),
              Text(peerName, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
              const SizedBox(height: 8),
              Text(session.error ?? statusText, style: const TextStyle(color: Colors.white60, fontSize: 16, fontFamily: 'Poppins')),

              const Spacer(),

              // Controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallButton(
                      icon: _isMuted ? Icons.mic_off : Icons.mic,
                      label: _isMuted ? 'Unmute' : 'Mute',
                      onTap: () {
                        _call.toggleMute();
                        setState(() => _isMuted = !_isMuted);
                      },
                      active: _isMuted,
                    ),
                    _CallButton(
                      icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                      label: 'Speaker',
                      onTap: () {
                        _call.toggleSpeaker();
                        setState(() => _isSpeakerOn = !_isSpeakerOn);
                      },
                      active: _isSpeakerOn,
                    ),
                    _CallButton(
                      icon: Icons.translate,
                      label: 'Translate',
                      onTap: () {
                        if (_translationOn) {
                          _call.stopVoiceTranslation();
                        } else {
                          _call.startVoiceTranslation();
                        }
                        setState(() => _translationOn = !_translationOn);
                      },
                      active: _translationOn,
                    ),
                    // End call (large red)
                    GestureDetector(
                      onTap: () => _call.endCall(),
                      child: Container(
                        width: 72, height: 72,
                        decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                        child: const Icon(Icons.call_end, color: Colors.white, size: 32),
                      ),
                    ),
                    _CallButton(
                      icon: Icons.videocam_outlined,
                      label: 'Video',
                      onTap: () => context.pushReplacement('/call/video/${widget.callId}'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _CallButton({required this.icon, required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'Poppins')),
        ],
      ),
    );
  }
}
