/// 사용자 프로필 모델.
///
/// `profiles` 테이블과 1:1 매핑.
class Profile {
  final String id;
  final String name;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Profile({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      name: map['name'] as String,
      avatarUrl: map['avatar_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'avatar_url': avatarUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Profile copyWith({
    String? name,
    String? Function()? avatarUrl,
  }) {
    return Profile(
      id: id,
      name: name ?? this.name,
      avatarUrl: avatarUrl != null ? avatarUrl() : this.avatarUrl,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
