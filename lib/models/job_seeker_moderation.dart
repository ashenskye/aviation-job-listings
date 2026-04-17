class JobSeekerModeration {
  final String userId;
  final String displayName;
  final String email;
  final int adminDeletedApplicationCount;
  final bool isBanned;
  final DateTime? bannedAt;
  final String banReason;
  final DateTime? updatedAt;

  const JobSeekerModeration({
    required this.userId,
    this.displayName = '',
    this.email = '',
    this.adminDeletedApplicationCount = 0,
    this.isBanned = false,
    this.bannedAt,
    this.banReason = '',
    this.updatedAt,
  });

  factory JobSeekerModeration.fromJson(Map<String, dynamic> json) {
    return JobSeekerModeration(
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      displayName:
          json['display_name']?.toString() ?? json['displayName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      adminDeletedApplicationCount:
          (json['admin_deleted_application_count'] as num?)?.toInt() ??
          (json['adminDeletedApplicationCount'] as num?)?.toInt() ??
          0,
      isBanned:
          (json['is_banned'] as bool?) ?? (json['isBanned'] as bool?) ?? false,
      bannedAt: json['banned_at'] != null
          ? DateTime.tryParse(json['banned_at'].toString())
          : json['bannedAt'] != null
          ? DateTime.tryParse(json['bannedAt'].toString())
          : null,
      banReason:
          json['ban_reason']?.toString() ?? json['banReason']?.toString() ?? '',
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'display_name': displayName,
    'email': email,
    'admin_deleted_application_count': adminDeletedApplicationCount,
    'is_banned': isBanned,
    'banned_at': bannedAt?.toIso8601String(),
    'ban_reason': banReason,
    'updated_at': updatedAt?.toIso8601String(),
  };
}