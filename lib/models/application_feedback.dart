class ApplicationFeedback {
  final String id;
  final String applicationId;
  final String message;
  final String feedbackType; // 'interested', 'not_fit', 'custom'
  final bool sentByEmployer;
  final DateTime sentAt;

  static const String feedbackTypeInterested = 'interested';
  static const String feedbackTypeNotFit = 'not_fit';
  static const String feedbackTypeCustom = 'custom';

  const ApplicationFeedback({
    required this.id,
    required this.applicationId,
    required this.message,
    required this.feedbackType,
    required this.sentByEmployer,
    required this.sentAt,
  });

  factory ApplicationFeedback.fromJson(Map<String, dynamic> json) {
    return ApplicationFeedback(
      id: json['id']?.toString() ?? '',
      applicationId:
          json['application_id']?.toString() ??
          json['applicationId']?.toString() ??
          '',
      message: json['message']?.toString() ?? '',
      feedbackType:
          json['feedback_type']?.toString() ??
          json['feedbackType']?.toString() ??
          feedbackTypeCustom,
      sentByEmployer:
          (json['sent_by_employer'] as bool?) ??
          (json['sentByEmployer'] as bool?) ??
          true,
      sentAt: json['sent_at'] != null
          ? DateTime.tryParse(json['sent_at'].toString()) ?? DateTime.now()
          : json['sentAt'] != null
          ? DateTime.tryParse(json['sentAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'application_id': applicationId,
    'message': message,
    'feedback_type': feedbackType,
    'sent_by_employer': sentByEmployer,
    'sent_at': sentAt.toIso8601String(),
  };

  ApplicationFeedback copyWith({
    String? message,
    String? feedbackType,
    bool? sentByEmployer,
    DateTime? sentAt,
  }) {
    return ApplicationFeedback(
      id: id,
      applicationId: applicationId,
      message: message ?? this.message,
      feedbackType: feedbackType ?? this.feedbackType,
      sentByEmployer: sentByEmployer ?? this.sentByEmployer,
      sentAt: sentAt ?? this.sentAt,
    );
  }
}
