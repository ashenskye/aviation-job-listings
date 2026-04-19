import '../models/admin_action_log.dart';
import '../models/application.dart';
import '../models/employer_moderation.dart';
import '../models/employer_profile.dart';
import '../models/job_listing.dart';
import '../models/job_listing_report.dart';
import '../models/job_seeker_moderation.dart';
import '../models/job_seeker_profile.dart';

abstract class AdminRepository {
  // Action Logging
  Future<void> logAdminAction(AdminActionLog log);
  Future<List<AdminActionLog>> getAdminActionLogs({
    DateTime? startDate,
    DateTime? endDate,
    String? actionType,
    String? resourceType,
  });

  // View data as admin
  Future<JobSeekerProfile?> getJobSeekerProfile(String userId);
  Future<EmployerProfile?> getEmployerProfile(String employerId);
  Future<List<Application>> getApplicationsForJob(String jobId);
  Future<List<JobListingReport>> getJobListingReports({String? status});
  Future<List<EmployerModeration>> getEmployerModerationSummaries();
  Future<List<JobSeekerModeration>> getJobSeekerModerationSummaries();
  Future<List<JobListing>> getExternalJobListings();

  // Edit/Fix Data
  Future<void> updateJobListing(
    String jobId,
    JobListing updated,
    String reason,
  );
  Future<void> updateApplication(
    String appId,
    Application updated,
    String reason,
  );
  Future<void> updateJobSeekerProfile(
    String userId,
    JobSeekerProfile updated,
    String reason,
  );
  Future<void> updateEmployerProfile(
    String empId,
    EmployerProfile updated,
    String reason,
  );
  Future<JobListing> createExternalJobListing({
    required String title,
    required String company,
    required String location,
    required String employmentType,
    required String description,
    String crewRole = 'Single Pilot',
    String? crewPosition,
    List<String> faaRules = const [],
    String? part135SubType,
    List<String> faaCertificates = const [],
    List<String> typeRatingsRequired = const [],
    Map<String, int> flightHours = const {},
    List<String> preferredFlightHours = const [],
    Map<String, int> instructorHours = const {},
    List<String> preferredInstructorHours = const [],
    Map<String, int> specialtyHours = const {},
    List<String> preferredSpecialtyHours = const [],
    List<String> aircraftFlown = const [],
    String? salaryRange,
    int? minimumHours,
    List<String> benefits = const [],
    DateTime? deadlineDate,
    int autoRejectThreshold = 0,
    int reapplyWindowDays = 30,
    String? externalApplyUrl,
    String? contactName,
    String? contactEmail,
    String? companyPhone,
    String? companyUrl,
    String? reason,
  });

  // Delete (soft delete recommended)
  Future<void> deleteApplication(String appId, String reason);
  Future<void> deleteJobListing(String jobId, String reason);
  Future<void> hardDeleteJobListing(String jobId, String reason);
  Future<void> deleteEmployerProfile(String employerId, String reason);
  Future<void> deleteJobSeekerProfile(String userId, String reason);
  Future<void> resolveJobListingReport(
    String reportId, {
    required String status,
    String? adminNotes,
  });
  Future<void> setEmployerBan(
    String employerId, {
    required bool isBanned,
    String? reason,
    String? companyName,
  });
  Future<void> setJobSeekerBan(
    String userId, {
    required bool isBanned,
    String? reason,
    String? displayName,
    String? email,
  });

  // Analytics / Support
  Future<int> getApplicationCountForJob(String jobId);
  Future<int> getTotalJobSeekerCount();
  Future<int> getTotalEmployerCount();
  Future<List<JobListing>> getAllJobListings();
  Future<List<Application>> getAllApplications();
}
