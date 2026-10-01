import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/models/user_model.dart';
import '../../core/constants/app_constants.dart';

final localStorageServiceProvider = Provider<LocalStorageService>((ref) {
  return LocalStorageService();
});

class LocalStorageService {
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ─── Tokens ───────────────────────────────────────────────
  // NOTE: flutter_secure_storage is not supported on the web build.
  // On web we fall back to SharedPreferences; native platforms use secure storage.
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyAccessToken, accessToken);
      await prefs.setString(AppConstants.keyRefreshToken, refreshToken);
      return;
    }
    await Future.wait([
      _secureStorage.write(key: AppConstants.keyAccessToken, value: accessToken),
      _secureStorage.write(key: AppConstants.keyRefreshToken, value: refreshToken),
    ]);
  }

  Future<String?> getAccessToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(AppConstants.keyAccessToken);
    }
    return _secureStorage.read(key: AppConstants.keyAccessToken);
  }

  Future<String?> getRefreshToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(AppConstants.keyRefreshToken);
    }
    return _secureStorage.read(key: AppConstants.keyRefreshToken);
  }

  Future<void> clearTokens() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.keyAccessToken);
      await prefs.remove(AppConstants.keyRefreshToken);
      return;
    }
    await Future.wait([
      _secureStorage.delete(key: AppConstants.keyAccessToken),
      _secureStorage.delete(key: AppConstants.keyRefreshToken),
    ]);
  }

  // ─── User ─────────────────────────────────────────────────
  Future<void> saveUser(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyUser, jsonEncode(user.toJson()));
  }

  Future<UserModel?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(AppConstants.keyUser);
    if (data == null) return null;
    try {
      return UserModel.fromJson(jsonDecode(data) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyUser);
  }

  // ─── Language ─────────────────────────────────────────────
  Future<void> saveLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyLanguage, language);
  }

  Future<String> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.keyLanguage) ?? 'english';
  }

  // ─── Dark Mode ────────────────────────────────────────────
  Future<void> saveDarkMode(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyDarkMode, isDark);
  }

  Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppConstants.keyDarkMode) ?? false;
  }

  // ─── Onboarding ───────────────────────────────────────────
  Future<void> setOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyOnboardingDone, true);
  }

  Future<bool> isOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppConstants.keyOnboardingDone) ?? false;
  }

  // ─── Clear All ────────────────────────────────────────────
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!kIsWeb) {
      await _secureStorage.deleteAll();
    }
  }
}
