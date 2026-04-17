import '../models/admin_action_log.dart';
import '../models/application.dart';
import '../models/employer_profile.dart';
import '../models/job_listing.dart';
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

  // Delete (soft delete recommended)
  Future<void> deleteApplication(String appId, String reason);
  Future<void> deleteJobListing(String jobId, String reason);

  // Analytics / Support
  Future<int> getApplicationCountForJob(String jobId);
  Future<int> getTotalJobSeekerCount();
  Future<int> getTotalEmployerCount();
  Future<List<JobListing>> getAllJobListings();
  Future<List<Application>> getAllApplications();
}
