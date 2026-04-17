class EmployerModeration {
  final String employerId;
  final String companyName;
  final int adminDeletedJobCount;
  final bool isBanned;
  final DateTime? bannedAt;
  final String banReason;
  final DateTime? updatedAt;

  const EmployerModeration({
    required this.employerId,
    this.companyName = '',
    this.adminDeletedJobCount = 0,
    this.isBanned = false,
    this.bannedAt,
    this.banReason = '',
    this.updatedAt,
  });

  factory EmployerModeration.fromJson(Map<String, dynamic> json) {
    return EmployerModeration(
      employerId:
          json['employer_id']?.toString() ?? json['employerId']?.toString() ?? '',
      companyName:
          json['company_name']?.toString() ?? json['companyName']?.toString() ?? '',
      adminDeletedJobCount:
          (json['admin_deleted_job_count'] as num?)?.toInt() ??
          (json['adminDeletedJobCount'] as num?)?.toInt() ??
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
    'employer_id': employerId,
    'company_name': companyName,
    'admin_deleted_job_count': adminDeletedJobCount,
    'is_banned': isBanned,
    'banned_at': bannedAt?.toIso8601String(),
    'ban_reason': banReason,
    'updated_at': updatedAt?.toIso8601String(),
  };
}