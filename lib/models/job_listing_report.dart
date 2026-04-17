class JobListingReport {
  final String id;
  final String jobListingId;
  final String reporterUserId;
  final String? employerId;
  final String reason;
  final String details;
  final String status;
  final String jobTitle;
  final String company;
  final String location;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reviewedByAdminUserId;
  final String? adminNotes;

  static const String statusOpen = 'open';
  static const String statusReviewed = 'reviewed';
  static const String statusDeleted = 'deleted';
  static const String statusDismissed = 'dismissed';

  const JobListingReport({
    required this.id,
    required this.jobListingId,
    required this.reporterUserId,
    this.employerId,
    required this.reason,
    this.details = '',
    this.status = statusOpen,
    required this.jobTitle,
    required this.company,
    required this.location,
    required this.createdAt,
    this.reviewedAt,
    this.reviewedByAdminUserId,
    this.adminNotes,
  });

  factory JobListingReport.fromJson(Map<String, dynamic> json) {
    return JobListingReport(
      id: json['id']?.toString() ?? '',
      jobListingId:
          json['job_listing_id']?.toString() ??
          json['jobListingId']?.toString() ??
          '',
      reporterUserId:
          json['reporter_user_id']?.toString() ??
          json['reporterUserId']?.toString() ??
          '',
      employerId:
          json['employer_id']?.toString() ?? json['employerId']?.toString(),
      reason: json['reason']?.toString() ?? 'Other',
      details: json['details']?.toString() ?? '',
      status:
          json['status']?.toString().trim().toLowerCase() ?? JobListingReport.statusOpen,
      jobTitle:
          json['job_title']?.toString() ?? json['jobTitle']?.toString() ?? '',
      company:
          json['company']?.toString() ?? json['company_snapshot']?.toString() ?? '',
      location:
          json['location']?.toString() ??
          json['location_snapshot']?.toString() ??
          '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.tryParse(json['reviewed_at'].toString())
          : json['reviewedAt'] != null
          ? DateTime.tryParse(json['reviewedAt'].toString())
          : null,
      reviewedByAdminUserId:
          json['reviewed_by_admin_user_id']?.toString() ??
          json['reviewedByAdminUserId']?.toString(),
      adminNotes:
          json['admin_notes']?.toString() ?? json['adminNotes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'job_listing_id': jobListingId,
    'reporter_user_id': reporterUserId,
    'employer_id': employerId,
    'reason': reason,
    'details': details,
    'status': status,
    'job_title': jobTitle,
    'company': company,
    'location': location,
    'created_at': createdAt.toIso8601String(),
    'reviewed_at': reviewedAt?.toIso8601String(),
    'reviewed_by_admin_user_id': reviewedByAdminUserId,
    'admin_notes': adminNotes,
  };

  JobListingReport copyWith({
    String? status,
    DateTime? reviewedAt,
    String? reviewedByAdminUserId,
    String? adminNotes,
  }) {
    return JobListingReport(
      id: id,
      jobListingId: jobListingId,
      reporterUserId: reporterUserId,
      employerId: employerId,
      reason: reason,
      details: details,
      status: status ?? this.status,
      jobTitle: jobTitle,
      company: company,
      location: location,
      createdAt: createdAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedByAdminUserId: reviewedByAdminUserId ?? this.reviewedByAdminUserId,
      adminNotes: adminNotes ?? this.adminNotes,
    );
  }
}