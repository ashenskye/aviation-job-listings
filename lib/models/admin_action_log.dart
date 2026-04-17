class AdminActionLog {
  final String id;
  final String adminUserId;
  final String actionType; // 'create', 'update', 'delete', 'view'
  final String resourceType; // 'application', 'job_listing', 'job_seeker_profile', 'employer_profile'
  final String resourceId;
  final Map<String, dynamic>? changesBefore; // Only for updates
  final Map<String, dynamic>? changesAfter; // Only for updates
  final String? reason; // Why admin made this change
  final DateTime timestamp;
  final String? ipAddress; // Optional: for tracking

  static const String actionCreate = 'create';
  static const String actionUpdate = 'update';
  static const String actionDelete = 'delete';
  static const String actionView = 'view';

  static const String resourceApplication = 'application';
  static const String resourceJobListing = 'job_listing';
  static const String resourceJobSeekerProfile = 'job_seeker_profile';
  static const String resourceEmployerProfile = 'employer_profile';

  const AdminActionLog({
    required this.id,
    required this.adminUserId,
    required this.actionType,
    required this.resourceType,
    required this.resourceId,
    this.changesBefore,
    this.changesAfter,
    this.reason,
    required this.timestamp,
    this.ipAddress,
  });

  factory AdminActionLog.fromJson(Map<String, dynamic> json) {
    return AdminActionLog(
      id: json['id']?.toString() ?? '',
      adminUserId:
          json['admin_user_id']?.toString() ??
          json['adminUserId']?.toString() ??
          '',
      actionType:
          json['action_type']?.toString() ??
          json['actionType']?.toString() ??
          actionView,
      resourceType:
          json['resource_type']?.toString() ??
          json['resourceType']?.toString() ??
          '',
      resourceId:
          json['resource_id']?.toString() ??
          json['resourceId']?.toString() ??
          '',
      changesBefore: json['changes_before'] != null
          ? Map<String, dynamic>.from(
              json['changes_before'] as Map<dynamic, dynamic>,
            )
          : json['changesBefore'] != null
          ? Map<String, dynamic>.from(
              json['changesBefore'] as Map<dynamic, dynamic>,
            )
          : null,
      changesAfter: json['changes_after'] != null
          ? Map<String, dynamic>.from(
              json['changes_after'] as Map<dynamic, dynamic>,
            )
          : json['changesAfter'] != null
          ? Map<String, dynamic>.from(
              json['changesAfter'] as Map<dynamic, dynamic>,
            )
          : null,
      reason:
          json['reason']?.toString(),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      ipAddress: json['ip_address']?.toString() ?? json['ipAddress']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'admin_user_id': adminUserId,
    'action_type': actionType,
    'resource_type': resourceType,
    'resource_id': resourceId,
    if (changesBefore != null) 'changes_before': changesBefore,
    if (changesAfter != null) 'changes_after': changesAfter,
    if (reason != null) 'reason': reason,
    'timestamp': timestamp.toIso8601String(),
    if (ipAddress != null) 'ip_address': ipAddress,
  };

  AdminActionLog copyWith({
    String? actionType,
    String? resourceType,
    String? resourceId,
    Map<String, dynamic>? changesBefore,
    Map<String, dynamic>? changesAfter,
    String? reason,
    DateTime? timestamp,
    String? ipAddress,
  }) {
    return AdminActionLog(
      id: id,
      adminUserId: adminUserId,
      actionType: actionType ?? this.actionType,
      resourceType: resourceType ?? this.resourceType,
      resourceId: resourceId ?? this.resourceId,
      changesBefore: changesBefore ?? this.changesBefore,
      changesAfter: changesAfter ?? this.changesAfter,
      reason: reason ?? this.reason,
      timestamp: timestamp ?? this.timestamp,
      ipAddress: ipAddress ?? this.ipAddress,
    );
  }
}
