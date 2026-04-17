class AuthUser {
  const AuthUser({
    required this.username,
    required this.password,
    required this.role,
    required this.displayName,
  });

  final String username;
  final String password;
  final String role;
  final String displayName;

  bool get isAdmin => role == 'admin';

  Map<String, dynamic> toJson() => {
        'username': username,
        'password': password,
        'role': role,
        'displayName': displayName,
      };

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        username: json['username'] as String,
        password: json['password'] as String? ?? '',
        role: json['role'] as String? ?? 'viewer',
        displayName: json['displayName'] as String? ?? (json['username'] as String? ?? ''),
      );
}
