// Firebase web configuration for Ubumwe Connect.
//
// HOW TO FILL THIS IN (one time, 3 minutes):
// 1. Go to https://console.firebase.google.com and open your project
//    (the same one your backend uses for verify_id_token).
// 2. Click the gear icon -> Project settings -> "Your apps" -> add/select a
//    "Web app" (</> icon).
// 3. Firebase shows a config block like:
//      const firebaseConfig = {
//        apiKey: "AIza...",
//        authDomain: "my-project.firebaseapp.com",
//        projectId: "my-project",
//        storageBucket: "my-project.appspot.com",
//        messagingSenderId: "1234567890",
//        appId: "1:1234567890:web:abcdef123456",
//      };
// 4. Copy those values into the constants below.
// 5. In the same page, go to Authentication -> Sign-in method -> Google ->
//    enable it. Then in Google Cloud Console -> APIs & Services -> Credentials,
//    open the "Web client" (created by Firebase for Google sign-in) and copy
//    its "Client ID" into googleWebClientId below.
//
// Until the values are filled in, the app silently skips Firebase on web
// (same behaviour as before) and Google buttons show a helpful message.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Whether the web Firebase config has been filled in by you.
bool get isFirebaseWebConfigured =>
    firebaseWebApiKey.isNotEmpty && !firebaseWebApiKey.startsWith('PASTE_');

const String firebaseWebApiKey = 'AIzaSyDsJ7zRIWvzNy0cMXN0nVYW-J3X95xRWx8';
const String firebaseWebAuthDomain = 'ubumwe-connect.firebaseapp.com';
const String firebaseWebProjectId = 'ubumwe-connect';
const String firebaseWebStorageBucket = 'ubumwe-connect.firebasestorage.app';
const String firebaseWebMessagingSenderId = '701952406577';
const String firebaseWebAppId = '1:701952406577:web:74778bc00ef1abf7235110';

/// The OAuth 2.0 **Web client ID** from Google Cloud Console credentials
/// (the one Firebase created for Google Sign-In). Needed by google_sign_in
/// on web and Android to obtain an idToken Firebase can verify.
const String googleWebClientId = '817451010649-tbhrmvjruqi0a1rha5r4mf7pg6c7ph7j.apps.googleusercontent.com';

FirebaseOptions get firebaseWebOptions => const FirebaseOptions(
      apiKey: firebaseWebApiKey,
      authDomain: firebaseWebAuthDomain,
      projectId: firebaseWebProjectId,
      storageBucket: firebaseWebStorageBucket,
      messagingSenderId: firebaseWebMessagingSenderId,
      appId: firebaseWebAppId,
    );
