import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../models/user_model.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/local_storage_service.dart';

// Firebase auth state stream
final authStateProvider = StreamProvider<User?>((ref) {
  if (Firebase.apps.isEmpty) {
    return Stream<User?>.value(null);
  }
  return FirebaseAuth.instance.authStateChanges();
});

// Current app user (from backend)
final currentUserProvider = StateProvider<UserModel?>((ref) => null);

// Auth notifier
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AsyncValue<UserModel?>>((ref) {
  return AuthNotifier(
    ref.read(apiServiceProvider),
    ref.read(localStorageServiceProvider),
    ref,
  );
});

class AuthNotifier extends StateNotifier<AsyncValue<UserModel?>> {
  final ApiService _api;
  final LocalStorageService _storage;
  final Ref _ref;

  AuthNotifier(this._api, this._storage, this._ref) : super(const AsyncValue.loading()) {
    _loadCachedUser();
  }

  Future<void> _loadCachedUser() async {
    final user = await _storage.getUser();
    if (user != null) {
      state = AsyncValue.data(user);
      _ref.read(currentUserProvider.notifier).state = user;
    } else {
      state = const AsyncValue.data(null);
    }
  }

  Future<UserModel> login(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final data = await _api.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      await _saveAuthData(data);
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      state = AsyncValue.data(user);
      return user;
    } on DioException catch (e) {
      final message = _extractError(e);
      state = AsyncValue.error(message, StackTrace.current);
      throw Exception(message);
    }
  }

  Future<UserModel> register({
    required String email,
    required String password,
    required String username,
    required String displayName,
    required String preferredLanguage,
    String? phone,
  }) async {
    state = const AsyncValue.loading();
    try {
      final data = await _api.post('/auth/register', data: {
        'email': email,
        'password': password,
        'username': username,
        'display_name': displayName,
        'preferred_language': preferredLanguage,
        if (phone != null) 'phone': phone,
      });
      await _saveAuthData(data);
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      state = AsyncValue.data(user);
      return user;
    } on DioException catch (e) {
      final message = _extractError(e);
      state = AsyncValue.error(message, StackTrace.current);
      throw Exception(message);
    }
  }

  Future<UserModel> loginWithFirebase(String firebaseToken, {String preferredLanguage = 'english'}) async {
    state = const AsyncValue.loading();
    try {
      final data = await _api.post('/auth/firebase-login', data: {
        'firebase_token': firebaseToken,
        'preferred_language': preferredLanguage,
      });
      await _saveAuthData(data);
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      state = AsyncValue.data(user);
      return user;
    } on DioException catch (e) {
      final message = _extractError(e);
      state = AsyncValue.error(message, StackTrace.current);
      throw Exception(message);
    }
  }

  Future<void> logout() async {
    try {
      final refreshToken = await _storage.getRefreshToken();
      if (refreshToken != null) {
        await _api.post('/auth/logout', data: {'refresh_token': refreshToken});
      }
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    await _storage.clearAll();
    state = const AsyncValue.data(null);
    _ref.read(currentUserProvider.notifier).state = null;
  }

  Future<void> resetPassword(String email) async {
    await _api.post('/auth/forgot-password', data: {'email': email});
  }

  Future<void> updateProfile({
    String? displayName,
    String? bio,
    String? phone,
    String? preferredLanguage,
  }) async {
    final data = await _api.put('/users/profile', data: {
      if (displayName != null) 'display_name': displayName,
      if (bio != null) 'bio': bio,
      if (phone != null) 'phone': phone,
      if (preferredLanguage != null) 'preferred_language': preferredLanguage,
    });
    final user = UserModel.fromJson(data);
    await _storage.saveUser(user);
    state = AsyncValue.data(user);
    _ref.read(currentUserProvider.notifier).state = user;
  }

  Future<void> deleteAccount(String password) async {
    await _api.delete('/users/me', data: {
      'password': password,
      'confirmation': 'DELETE MY ACCOUNT',
    });
    await logout();
  }

  Future<void> _saveAuthData(Map<String, dynamic> data) async {
    await _storage.saveTokens(
      data['access_token'] as String,
      data['refresh_token'] as String,
    );
    final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
    await _storage.saveUser(user);
    _ref.read(currentUserProvider.notifier).state = user;
  }

  String _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map) return data['detail']?.toString() ?? 'An error occurred';
    return e.message ?? 'An error occurred';
  }
}
