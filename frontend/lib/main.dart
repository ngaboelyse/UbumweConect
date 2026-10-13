import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'app/app.dart';
import 'core/constants/app_constants.dart';
import 'firebase_options.dart' as fb_opts;
import 'shared/services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
    ),
  );

  // Discover the backend host on the LAN before the first API call (mobile
  // and desktop). On web the host comes from the browser URL instead.
  try {
    await AppConstants.initHost();
  } catch (e) {
    debugPrint('Host discovery skipped: $e');
  }

  // Initialize Firebase.
  // - Mobile: uses native config bundled in the build (google-services.plist /
  //   resources) — actually this project relies on default host resources, so
  //   init is wrapped in try/catch and skipped when unconfigured.
  // - Web: needs explicit options. When lib/firebase_options.dart has been
  //   filled in with the real project values, it initializes with those;
  //   otherwise it is skipped exactly as before.
  try {
    if (kIsWeb) {
      if (fb_opts.isFirebaseWebConfigured) {
        await Firebase.initializeApp(options: fb_opts.firebaseWebOptions);
      } else {
        debugPrint('Firebase web not configured: fill in lib/firebase_options.dart to enable Google sign-in on web.');
      }
    } else {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('Firebase initialization skipped: $e');
  }

  // Firebase Messaging requires an initialized Firebase app. Web also needs
  // generated Firebase options and a service worker, so leave it disabled
  // when this project is run locally without that configuration.
  if (!kIsWeb && Firebase.apps.isNotEmpty) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  runApp(
    const ProviderScope(
      child: UbumweConnectApp(),
    ),
  );
}
