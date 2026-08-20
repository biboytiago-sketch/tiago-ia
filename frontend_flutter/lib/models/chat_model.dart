enum ChatRole { user, ai, system }

class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;
  final DateTime timestamp;

  ChatMessage({
    String? id,
    required this.role,
    this.content = '',
    DateTime? timestamp,
  })  : id = id ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
        timestamp = timestamp ?? DateTime.now();

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final String? roleStr = json['role'] as String?;
    final ChatRole role = roleStr == 'user'
        ? ChatRole.user
        : (roleStr == 'ai' || roleStr == 'assistant' ? ChatRole.ai : ChatRole.system);

    final bool? isUser = json['isUser'] is bool ? json['isUser'] as bool : null;
    final ChatRole roleCompat = isUser == null
        ? role
        : (isUser ? ChatRole.user : ChatRole.ai);

    return ChatMessage(
      id: json['id'] as String? ?? '',
      role: roleCompat,
      content: (json['content'] as String?) ??
          (json['text'] as String?) ??
          '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  bool get isUser => role == ChatRole.user;
  bool get isAi => role == ChatRole.ai;
  String get text => content;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'role': role.name,
      'content': content,
      'isUser': isUser,
      'text': content,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  ChatMessage copyWith({
    String? id,
    ChatRole? role,
    String? content,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
