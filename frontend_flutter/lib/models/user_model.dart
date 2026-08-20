class UserModel {
  final String id;
  final String username;
  final String token;
  final bool isLoggedIn;

  UserModel({
    this.id = '',
    this.username = '',
    this.token = '',
    this.isLoggedIn = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      token: json['token'] as String? ?? '',
      isLoggedIn: json['isLoggedIn'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'token': token,
      'isLoggedIn': isLoggedIn,
    };
  }

  UserModel copyWith({
    String? id,
    String? username,
    String? token,
    bool? isLoggedIn,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      token: token ?? this.token,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
    );
  }
}
