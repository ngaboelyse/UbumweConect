import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/avatar_widget.dart';

class VoiceCallScreen extends ConsumerStatefulWidget {
  final String callId;
  const VoiceCallScreen({super.key, required this.callId});

  @override
  ConsumerState<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends ConsumerState<VoiceCallScreen> {
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _showSubtitles = true;
  String _callStatus = 'Connecting...';
  String _duration = '00:00';
  String _liveSubtitle = '';
  Timer? _durationTimer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _startCall();
  }

  void _startCall() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _callStatus = 'Connected');
        _startTimer();
        _simulateSubtitles();
      }
    });
  }

  void _startTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _seconds++;
      final m = (_seconds ~/ 60).toString().padLeft(2, '0');
      final s = (_seconds % 60).toString().padLeft(2, '0');
      if (mounted) setState(() => _duration = '$m:$s');
    });
  }

  void _simulateSubtitles() {
    final samples = [
      'Muraho! Amakuru yawe?',
      '(Translated: Hello! How are you?)',
      'Ndi meza, urakoze!',
      '(Translated: I\'m fine, thank you!)',
    ];
    int i = 0;
    Timer.periodic(const Duration(seconds: 4), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _liveSubtitle = samples[i % samples.length]);
      i++;
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              const UserAvatar(displayName: 'Contact Name', size: AvatarSize.xlarge),
              const SizedBox(height: 20),
              const Text('Contact Name', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
              const SizedBox(height: 8),
              Text(_callStatus, style: const TextStyle(color: Colors.white60, fontSize: 16, fontFamily: 'Poppins')),

              const Spacer(),

              // Live subtitle box
              if (_showSubtitles && _liveSubtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: AnimatedOpacity(
                    opacity: _liveSubtitle.isNotEmpty ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.closed_caption, color: Colors.white70, size: 16),
                              SizedBox(width: 6),
                              Text('Live Subtitle', style: TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Poppins')),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(_liveSubtitle, style: const TextStyle(color: Colors.white, fontSize: 15, fontFamily: 'Poppins', height: 1.4)),
                        ],
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallButton(
                      icon: _isMuted ? Icons.mic_off : Icons.mic,
                      label: _isMuted ? 'Unmute' : 'Mute',
                      onTap: () => setState(() => _isMuted = !_isMuted),
                      active: _isMuted,
                    ),
                    _CallButton(
                      icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                      label: 'Speaker',
                      onTap: () => setState(() => _isSpeakerOn = !_isSpeakerOn),
                      active: _isSpeakerOn,
                    ),
                    // End call (large red)
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: 72, height: 72,
                        decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                        child: const Icon(Icons.call_end, color: Colors.white, size: 32),
                      ),
                    ),
                    _CallButton(
                      icon: Icons.closed_caption,
                      label: 'Subtitles',
                      onTap: () => setState(() => _showSubtitles = !_showSubtitles),
                      active: _showSubtitles,
                    ),
                    _CallButton(
                      icon: Icons.videocam_outlined,
                      label: 'Video',
                      onTap: () {},
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
