class Application {
  final String id;
  final String jobSeekerId;
  final String jobId;
  final String employerId;
  final String status; // 'applied', 'viewed', 'interested', 'rejected'
  final int matchPercentage;
  final String coverLetter;
  final DateTime appliedAt;
  final DateTime updatedAt;

  const Application({
    required this.id,
    required this.jobSeekerId,
    required this.jobId,
    required this.employerId,
    required this.status,
    required this.matchPercentage,
    required this.coverLetter,
    required this.appliedAt,
    required this.updatedAt,
  });

  bool get isPerfectMatch => matchPercentage >= 90;
  bool get isGoodMatch => matchPercentage >= 70 && matchPercentage < 90;
  bool get isStretchMatch => matchPercentage < 70;

  factory Application.fromJson(Map<String, dynamic> json) {
    return Application(
      id: json['id']?.toString() ?? '',
      jobSeekerId: json['jobSeekerId']?.toString() ?? '',
      jobId: json['jobId']?.toString() ?? '',
      employerId: json['employerId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'applied',
      matchPercentage: (json['matchPercentage'] as num?)?.toInt() ?? 0,
      coverLetter: json['coverLetter']?.toString() ?? '',
      appliedAt: json['appliedAt'] != null
          ? DateTime.tryParse(json['appliedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'jobSeekerId': jobSeekerId,
    'jobId': jobId,
    'employerId': employerId,
    'status': status,
    'matchPercentage': matchPercentage,
    'coverLetter': coverLetter,
    'appliedAt': appliedAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  Application copyWith({String? status, DateTime? updatedAt}) {
    return Application(
      id: id,
      jobSeekerId: jobSeekerId,
      jobId: jobId,
      employerId: employerId,
      status: status ?? this.status,
      matchPercentage: matchPercentage,
      coverLetter: coverLetter,
      appliedAt: appliedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
