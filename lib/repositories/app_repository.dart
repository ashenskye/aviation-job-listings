import '../models/employer_profiles_data.dart';
import '../models/job_listing.dart';
import '../models/job_listing_template.dart';
import '../models/job_load_result.dart';
import '../models/job_seeker_profile.dart';

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
}
