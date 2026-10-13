import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/screens/splash_screen.dart';
import '../features/auth/screens/onboarding_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/forgot_password_screen.dart';
import '../features/chat/screens/home_screen.dart';
import '../features/chat/screens/chat_list_screen.dart';
import '../features/chat/screens/chat_screen.dart';
import '../features/chat/screens/contacts_screen.dart';
import '../features/chat/screens/new_conversation_screen.dart';
import '../features/calls/screens/voice_call_screen.dart';
import '../features/calls/screens/video_call_screen.dart';
import '../features/calls/screens/incoming_call_screen.dart';
import '../features/profile/screens/profile_screen.dart';
import '../features/profile/screens/edit_profile_screen.dart';
import '../features/profile/screens/user_profile_screen.dart';
import '../features/profile/screens/settings_screen.dart';
import '../features/profile/screens/help_support_screen.dart';
import '../features/translation/screens/language_settings_screen.dart';
import '../features/auth/providers/auth_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ValueNotifier<DateTime>(DateTime.now());

  ref.listen(authNotifierProvider, (_, __) {
    refreshNotifier.value = DateTime.now();
  });

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/register') ||
          state.matchedLocation.startsWith('/onboarding') ||
          state.matchedLocation.startsWith('/forgot-password') ||
          state.matchedLocation.startsWith('/splash');

      if (!isLoggedIn && !isAuthRoute) {
        return '/login';
      }
      if (isLoggedIn && (state.matchedLocation == '/login' || state.matchedLocation == '/register')) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),

      // Main shell with bottom navigation
      ShellRoute(
        builder: (context, state, child) => HomeScreen(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const ChatListScreen(),
          ),
          GoRoute(
            path: '/contacts',
            builder: (context, state) => const ContactsScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),

      // Chat
      GoRoute(
        path: '/chat/:conversationId',
        builder: (context, state) => ChatScreen(
          conversationId: state.pathParameters['conversationId']!,
        ),
      ),
      GoRoute(
        path: '/new-conversation',
        builder: (context, state) => const NewConversationScreen(),
      ),

      // Calls
      GoRoute(
        path: '/call/voice/:callId',
        builder: (context, state) => VoiceCallScreen(
          callId: state.pathParameters['callId']!,
        ),
      ),
      GoRoute(
        path: '/call/video/:callId',
        builder: (context, state) => VideoCallScreen(
          callId: state.pathParameters['callId']!,
        ),
      ),
      GoRoute(
        path: '/incoming-call',
        builder: (context, state) => IncomingCallScreen(
          callId: state.uri.queryParameters['call_id'] ?? '',
          callType: state.uri.queryParameters['call_type'] ?? 'voice',
          callerName: state.uri.queryParameters['caller_name'] ?? 'Unknown',
          callerAvatar: state.uri.queryParameters['caller_avatar'] ?? '',
        ),
      ),

      // Profile
      GoRoute(
        path: '/user/:userId',
        builder: (context, state) => UserProfileScreen(
          userId: state.pathParameters['userId']!,
        ),
      ),
      GoRoute(
        path: '/edit-profile',
        builder: (context, state) => const EditProfileScreen(),
      ),

      // Settings
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/language',
        builder: (context, state) => const LanguageSettingsScreen(),
      ),
      GoRoute(
        path: '/help',
        builder: (context, state) => const HelpSupportScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.error}'),
      ),
    ),
  );
});
