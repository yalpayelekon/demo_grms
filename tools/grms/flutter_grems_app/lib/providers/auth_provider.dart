import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UserRole { viewer, operator, admin }

extension UserRoleX on UserRole {
  String get label => switch (this) {
    UserRole.viewer => 'viewer',
    UserRole.operator => 'operator',
    UserRole.admin => 'admin',
  };

  static UserRole fromString(String label) {
    return switch (label) {
      'admin' => UserRole.admin,
      'operator' => UserRole.operator,
      _ => UserRole.viewer,
    };
  }

  bool get canEditLayout => this == UserRole.admin;
  bool get canManageSettings => this == UserRole.admin;
}

class User {
  final String username;
  final UserRole role;
  final String? displayName;

  User({required this.username, required this.role, this.displayName});

  Map<String, dynamic> toJson() => {
        'username': username,
        'role': role.label,
        'displayName': displayName,
      };

  factory User.fromJson(Map<String, dynamic> json) => User(
        username: json['username'] as String,
        role: UserRoleX.fromString(json['role'] as String),
        displayName: json['displayName'] as String?,
      );
}

class StoredUser extends User {
  final String password;

  StoredUser({
    required super.username,
    required super.role,
    super.displayName,
    required this.password,
  });

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'password': password,
      };

  factory StoredUser.fromJson(Map<String, dynamic> json) => StoredUser(
        username: json['username'] as String,
        role: UserRoleX.fromString(json['role'] as String),
        displayName: json['displayName'] as String?,
        password: json['password'] as String,
      );
}

class AuthState {
  final User? user;
  final List<StoredUser> users;
  final bool isInitialized;

  AuthState({
    this.user,
    this.users = const [],
    this.isInitialized = false,
  });

  bool get isAuthenticated => user != null;
  UserRole get role => user?.role ?? UserRole.viewer;
  bool get isAdmin => role == UserRole.admin;

  AuthState copyWith({
    User? user,
    List<StoredUser>? users,
    bool? isInitialized,
    bool clearUser = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      users: users ?? this.users,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  static const String _storageKey = 'grems_auth';
  static const String _usersStorageKey = 'grems_users';
  static const String _firstLaunchCompletedKey = 'grems_first_launch_completed';

  static final List<StoredUser> _defaultUsers = [
    StoredUser(
      username: 'admin',
      password: 'admin',
      role: UserRole.admin,
      displayName: 'Administrator',
    ),
    StoredUser(
      username: 'test',
      password: 'test',
      role: UserRole.viewer,
      displayName: 'Test User',
    ),
  ];

  @override
  AuthState build() {
    _init();
    return AuthState();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load users
    List<StoredUser> loadedUsers;
    final usersJson = prefs.getString(_usersStorageKey);
    if (usersJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(usersJson);
        loadedUsers = decoded.map((e) => StoredUser.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        loadedUsers = List.from(_defaultUsers);
      }
    } else {
      loadedUsers = List.from(_defaultUsers);
    }

    // Load current session
    User? loadedUser;
    final authJson = prefs.getString(_storageKey);
    if (authJson != null) {
      try {
        loadedUser = User.fromJson(jsonDecode(authJson));
      } catch (e) {
        prefs.remove(_storageKey);
      }
    }

    // Auto-login test user only on the very first app opening.
    final firstLaunchCompleted = prefs.getBool(_firstLaunchCompletedKey) ?? false;
    if (!firstLaunchCompleted && loadedUser == null) {
      final testUser = loadedUsers.cast<User?>().firstWhere(
        (u) => u?.username == 'test',
        orElse: () => null,
      );
      if (testUser != null) {
        loadedUser = User(
          username: testUser.username,
          role: testUser.role,
          displayName: testUser.displayName,
        );
        await prefs.setString(_storageKey, jsonEncode(loadedUser.toJson()));
      }
    }
    if (!firstLaunchCompleted) {
      await prefs.setBool(_firstLaunchCompletedKey, true);
    }

    state = state.copyWith(
      user: loadedUser,
      users: loadedUsers,
      isInitialized: true,
    );
  }

  Future<bool> login(String username, String password) async {
    StoredUser? target;
    for (final u in state.users) {
      if (u.username == username && u.password == password) {
        target = u;
        break;
      }
    }

    if (target != null) {
      final user = User(
        username: target.username,
        role: target.role,
        displayName: target.displayName,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(user.toJson()));
      state = state.copyWith(user: user);
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    state = state.copyWith(clearUser: true);
  }

  Future<void> updateDisplayName(String displayName) async {
    if (state.user != null) {
      final updatedUser = User(
        username: state.user!.username,
        role: state.user!.role,
        displayName: displayName,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(updatedUser.toJson()));
      
      final updatedUsers = state.users.map((u) {
        if (u.username == state.user!.username) {
          return StoredUser(
            username: u.username,
            role: u.role,
            displayName: displayName,
            password: u.password,
          );
        }
        return u;
      }).toList();
      await prefs.setString(_usersStorageKey, jsonEncode(updatedUsers.map((u) => u.toJson()).toList()));
      
      state = state.copyWith(
        user: updatedUser,
        users: updatedUsers,
      );
    }
  }

  Future<({bool success, String message})> addUser(StoredUser newUser) async {
    if (state.users.any((u) => u.username == newUser.username)) {
      return (success: false, message: 'A user with that username already exists.');
    }
    final updatedUsers = [...state.users, newUser];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usersStorageKey, jsonEncode(updatedUsers.map((u) => u.toJson()).toList()));
    state = state.copyWith(users: updatedUsers);
    return (success: true, message: 'User created successfully.');
  }

  Future<({bool success, String message})> updateUser(
    String username,
    String? password,
    UserRole? role,
    String? displayName,
  ) async {
    final index = state.users.indexWhere((u) => u.username == username);
    if (index == -1) {
      return (success: false, message: 'User not found.');
    }

    final oldUser = state.users[index];
    final updatedUser = StoredUser(
      username: username,
      role: role ?? oldUser.role,
      displayName: displayName ?? oldUser.displayName,
      password: password ?? oldUser.password,
    );

    final updatedUsers = List<StoredUser>.from(state.users)..[index] = updatedUser;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usersStorageKey, jsonEncode(updatedUsers.map((u) => u.toJson()).toList()));

    User? currentUser = state.user;
    if (state.user?.username == username) {
      currentUser = User(
        username: username,
        role: updatedUser.role,
        displayName: updatedUser.displayName,
      );
      await prefs.setString(_storageKey, jsonEncode(currentUser.toJson()));
    }

    state = state.copyWith(
      user: currentUser,
      users: updatedUsers,
    );
    return (success: true, message: 'User updated successfully.');
  }

  Future<({bool success, String message})> deleteUser(String username) async {
    if (state.user?.username == username) {
      return (success: false, message: 'You cannot delete the currently signed-in user.');
    }
    
    final target = state.users.firstWhere((u) => u.username == username, orElse: () => throw Exception('User not found'));
    final admins = state.users.where((u) => u.role == UserRole.admin).length;
    
    if (target.role == UserRole.admin && admins <= 1) {
      return (success: false, message: 'At least one admin user must remain.');
    }

    final updatedUsers = state.users.where((u) => u.username != username).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usersStorageKey, jsonEncode(updatedUsers.map((u) => u.toJson()).toList()));
    
    state = state.copyWith(users: updatedUsers);
    return (success: true, message: 'User deleted successfully.');
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

