import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_user.dart';

class AuthRepository {
  static const _usersKey = 'grems_users';
  static const _sessionKey = 'grems_auth';

  Future<List<AuthUser>> loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_usersKey);
    if (stored == null) {
      return const [
        AuthUser(username: 'admin', password: 'admin', role: 'admin', displayName: 'Administrator'),
        AuthUser(username: 'test', password: 'test', role: 'viewer', displayName: 'Test User'),
      ];
    }
    final data = (jsonDecode(stored) as List).cast<Map<String, dynamic>>();
    return data.map(AuthUser.fromJson).toList();
  }

  Future<void> saveUsers(List<AuthUser> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usersKey, jsonEncode(users.map((e) => e.toJson()).toList()));
  }

  Future<AuthUser?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_sessionKey);
    if (stored == null) {
      return null;
    }
    return AuthUser.fromJson((jsonDecode(stored) as Map).cast<String, dynamic>());
  }

  Future<void> saveSession(AuthUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(user.toJson()));
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }
}
