import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';

class VideoCallScreen extends ConsumerStatefulWidget {
  final String callId;
  const VideoCallScreen({super.key, required this.callId});

  @override
  ConsumerState<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends ConsumerState<VideoCallScreen> {
  bool _isMuted = false;
  bool _isCameraOn = true;
  bool _showCaptions = true;
  bool _showControls = true;
  String _duration = '00:00';
  String _liveCaption = '';
  Timer? _durationTimer;
  Timer? _controlsTimer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _simulateCaptions();
    _scheduleHideControls();
  }

  void _startTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _seconds++;
      final m = (_seconds ~/ 60).toString().padLeft(2, '0');
      final s = (_seconds % 60).toString().padLeft(2, '0');
      if (mounted) setState(() => _duration = '$m:$s');
    });
  }

  void _simulateCaptions() {
    final samples = [
      'Bonjour, comment ça va?',
      '(Translated: Hello, how are you?)',
      'Je suis très bien, merci!',
      '(Translated: I am very well, thank you!)',
    ];
    int i = 0;
    Timer.periodic(const Duration(seconds: 5), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _liveCaption = samples[i % samples.length]);
      i++;
    });
  }

  void _scheduleHideControls() {
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onTap() {
    setState(() => _showControls = true);
    _controlsTimer?.cancel();
    _scheduleHideControls();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _controlsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _onTap,
        child: Stack(
          children: [
            // Remote video (full screen placeholder)
            Container(
              width: double.infinity,
              height: double.infinity,
              color: const Color(0xFF1A1A2E),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(radius: 60, backgroundColor: Color(0xFF2D2D44), child: Text('U', style: TextStyle(fontSize: 48, color: Colors.white, fontFamily: 'Poppins'))),
                    SizedBox(height: 16),
                    Text('Contact Name', style: TextStyle(color: Colors.white54, fontSize: 16, fontFamily: 'Poppins')),
                  ],
                ),
              ),
            ),

            // Self video (PiP - top right)
            Positioned(
              top: 60,
              right: 16,
              child: Container(
                width: 100,
                height: 140,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D44),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _isCameraOn
                      ? const Center(child: Icon(Icons.videocam, color: Colors.white54, size: 32))
                      : const Center(child: Icon(Icons.videocam_off, color: Colors.white38, size: 32)),
                ),
              ),
            ),

            // Top bar
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          const Text('Contact Name', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Poppins')),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.success.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
                            child: Text(_duration, style: const TextStyle(color: AppColors.success, fontSize: 12, fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                          ),
                          const Spacer(),
                          const Icon(Icons.signal_cellular_alt, color: Colors.white70, size: 18),
                          const SizedBox(width: 4),
                          const Text('HD', style: TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Poppins')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Live captions
            if (_showCaptions && _liveCaption.isNotEmpty)
              Positioned(
                bottom: 120,
                left: 16,
                right: 16,
                child: AnimatedOpacity(
                  opacity: _liveCaption.isNotEmpty ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.closed_caption, color: Colors.white60, size: 14),
                            SizedBox(width: 4),
                            Text('Live Captions (English)', style: TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'Poppins')),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(_liveCaption, style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Poppins', height: 1.4)),
                      ],
                    ),
                  ),
                ),
              ),

            // Bottom controls
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _VideoCallButton(
                            icon: _isMuted ? Icons.mic_off : Icons.mic,
                            label: _isMuted ? 'Unmute' : 'Mute',
                            onTap: () => setState(() => _isMuted = !_isMuted),
                            active: _isMuted,
                          ),
                          _VideoCallButton(
                            icon: Icons.flip_camera_ios_outlined,
                            label: 'Flip',
                            onTap: () {},
                          ),
                          GestureDetector(
                            onTap: () => context.pop(),
                            child: Container(
                              width: 64, height: 64,
                              decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                              child: const Icon(Icons.call_end, color: Colors.white, size: 28),
                            ),
                          ),
                          _VideoCallButton(
                            icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
                            label: 'Camera',
                            onTap: () => setState(() => _isCameraOn = !_isCameraOn),
                            active: !_isCameraOn,
                          ),
                          _VideoCallButton(
                            icon: Icons.closed_caption,
                            label: 'Captions',
                            onTap: () => setState(() => _showCaptions = !_showCaptions),
                            active: _showCaptions,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoCallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _VideoCallButton({required this.icon, required this.label, required this.onTap, this.active = false});

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
              color: active ? AppColors.primary : Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'Poppins')),
        ],
      ),
    );
  }
}
