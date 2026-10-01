import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/avatar_widget.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulse1;
  late Animation<double> _pulse2;
  late Animation<double> _pulse3;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _pulse1 = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _pulseController, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _pulse2 = Tween<double>(begin: 1.0, end: 1.8).animate(
      CurvedAnimation(parent: _pulseController, curve: const Interval(0.2, 0.8, curve: Curves.easeOut)),
    );
    _pulse3 = Tween<double>(begin: 1.0, end: 2.1).animate(
      CurvedAnimation(parent: _pulseController, curve: const Interval(0.4, 1.0, curve: Curves.easeOut)),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.callGradient),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 40),

              // Caller info with pulse animation
              Column(
                children: [
                  const Text('Ubumwe Connect', style: TextStyle(color: Colors.white54, fontSize: 14, fontFamily: 'Poppins')),
                  const SizedBox(height: 8),
                  const Text('Incoming Voice Call', style: TextStyle(color: Colors.white70, fontSize: 16, fontFamily: 'Poppins')),
                  const SizedBox(height: 40),

                  // Animated avatar
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pulse rings
                          _PulseRing(scale: _pulse3.value, opacity: (1 - _pulseController.value).clamp(0.0, 1.0) * 0.3),
                          _PulseRing(scale: _pulse2.value, opacity: (1 - _pulseController.value).clamp(0.0, 1.0) * 0.5),
                          _PulseRing(scale: _pulse1.value, opacity: (1 - _pulseController.value).clamp(0.0, 1.0) * 0.7),
                          child!,
                        ],
                      );
                    },
                    child: const UserAvatar(displayName: 'Caller', size: AvatarSize.xlarge),
                  ),

                  const SizedBox(height: 24),
                  const Text('Caller Name', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
                  const SizedBox(height: 8),
                  const Text('+250 7XX XXX XXX', style: TextStyle(color: Colors.white60, fontSize: 16, fontFamily: 'Poppins')),
                ],
              ),

              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Decline
                    Column(
                      children: [
                        GestureDetector(
                          onTap: () => context.pop(),
                          child: Container(
                            width: 72, height: 72,
                            decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                            child: const Icon(Icons.call_end, color: Colors.white, size: 32),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text('Decline', style: TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'Poppins')),
                      ],
                    ),

                    // Accept
                    Column(
                      children: [
                        GestureDetector(
                          onTap: () => context.pushReplacement('/call/voice/new'),
                          child: Container(
                            width: 72, height: 72,
                            decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                            child: const Icon(Icons.call, color: Colors.white, size: 32),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text('Accept', style: TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'Poppins')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulseRing extends StatelessWidget {
  final double scale;
  final double opacity;

  const _PulseRing({required this.scale, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(opacity), width: 2),
        ),
      ),
    );
  }
}
