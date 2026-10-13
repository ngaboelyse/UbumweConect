import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/services/local_storage_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<_OnboardingData> _pages = [
    _OnboardingData(
      emoji: '💬',
      title: 'Chat in Any Language',
      description: 'Send messages in Kinyarwanda, English, French, or Swahili. Your friends see them in their own language — automatically.',
      gradientColors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
    ),
    _OnboardingData(
      emoji: '🌐',
      title: 'Instant AI Translation',
      description: 'Our AI translates every message in real-time. No delays, no awkward pauses. Just seamless, natural conversation.',
      gradientColors: [Color(0xFF00838F), Color(0xFF00ACC1)],
    ),
    _OnboardingData(
      emoji: '📞',
      title: 'Voice & Video Calls',
      description: 'Make crystal-clear voice and video calls over WebRTC.',
      gradientColors: [Color(0xFFE65100), Color(0xFFFF6F00)],
    ),
  ];

  Future<void> _done() async {
    final storage = LocalStorageService();
    await storage.setOnboardingDone();
    if (mounted) context.go('/login');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: _pages.length,
            itemBuilder: (context, i) {
              final page = _pages[i];
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: page.gradientColors,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(page.emoji, style: const TextStyle(fontSize: 96)),
                        const SizedBox(height: 40),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          page.description,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withOpacity(0.9),
                            height: 1.6,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // Bottom area
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  // Page indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == i ? Colors.white : Colors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Buttons
                  Row(
                    children: [
                      if (_currentPage < _pages.length - 1) ...[
                        Expanded(
                          child: TextButton(
                            onPressed: _done,
                            child: Text('Skip', style: TextStyle(color: Colors.white.withOpacity(0.8), fontFamily: 'Poppins', fontSize: 16)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () => _controller.nextPage(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOut,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.primary,
                            ),
                            child: const Text('Next'),
                          ),
                        ),
                      ] else
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _done,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.primary,
                            ),
                            child: const Text('Get Started 🚀'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingData {
  final String emoji;
  final String title;
  final String description;
  final List<Color> gradientColors;

  const _OnboardingData({
    required this.emoji,
    required this.title,
    required this.description,
    required this.gradientColors,
  });
}
