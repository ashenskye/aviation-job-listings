import '../models/application.dart';
import '../models/application_feedback.dart';
import '../models/employer_profiles_data.dart';
import '../models/job_listing.dart';
import '../models/job_listing_report.dart';
import '../models/job_listing_template.dart';
import '../models/job_load_result.dart';
import '../models/job_seeker_profile.dart';
import '../models/saved_search.dart';

enum FeedbackSaveDestination { remote, local }

abstract class AppRepository {
  Future<Set<String>> loadFavoriteIds();
  Future<void> saveFavoriteIds(Set<String> favoriteIds);

  Future<JobSeekerProfile> loadJobSeekerProfile();
  Future<void> saveJobSeekerProfile(JobSeekerProfile profile);

  Future<EmployerProfilesData> loadEmployerProfiles();
  Future<void> saveEmployerProfiles(EmployerProfilesData data);

  Future<List<JobListingTemplate>> loadJobTemplates();
  Future<void> saveJobTemplates(List<JobListingTemplate> templates);

  Future<JobLoadResult> loadJobs({
    required String backendUrl,
    required List<JobListing> fallbackJobs,
  });

  Future<JobListing> createJob(JobListing job);
  Future<JobListing> updateJob(JobListing job);
  Future<void> deleteJob(JobListing job);

  // Application methods
  Future<void> saveApplication(Application app);
  Future<List<Application>> getApplicationsBySeeker(String seekerId);
  Future<List<Application>> loadApplicationsForEmployer(String employerId);
  Future<void> updateApplicationStatus(String applicationId, String status);
  Future<void> updateApplicationArchived(String applicationId, bool isArchived);
  Future<void> deleteApplication(String applicationId);
  Future<void> deleteApplications(List<String> applicationIds);
  Future<bool> hasApplied(String seekerId, String jobId);
  Future<Application?> getLatestApplicationForJob(
    String seekerId,
    String jobId,
  );
  Future<void> reportJobListing(JobListingReport report);

  // Application feedback methods
  Future<FeedbackSaveDestination> saveFeedback(ApplicationFeedback feedback);
  Future<List<ApplicationFeedback>> getAllFeedback();
  Future<ApplicationFeedback?> getFeedbackForApplication(String applicationId);

  // Saved searches
  Future<List<SavedSearch>> loadSavedSearches();
  Future<void> saveSavedSearch(SavedSearch search);
  Future<void> updateSavedSearch(SavedSearch search);
  Future<void> deleteSavedSearch(String searchId);

  // Employer notification utilities
  Future<String> sendEmployerNotificationTestEmail(String employerId);

  // Seeker notification utilities (temporary pre-launch testing)
  Future<String> sendSeekerNotificationTestEmail();
}
