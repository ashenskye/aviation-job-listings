import 'package:aviation_job_listings/models/employer_profiles_data.dart';
import 'package:aviation_job_listings/models/job_listing.dart';
import 'package:aviation_job_listings/models/job_listing_template.dart';
import 'package:aviation_job_listings/models/job_load_result.dart';
import 'package:aviation_job_listings/models/job_seeker_profile.dart';
import 'package:aviation_job_listings/repositories/app_repository.dart';

class FakeAppRepository implements AppRepository {
  final Set<String> _favoriteIds = <String>{};
  JobSeekerProfile _profile = const JobSeekerProfile();
  EmployerProfilesData _employerData = const EmployerProfilesData.empty();
  final List<JobListing> _jobs = <JobListing>[];
  final List<JobListingTemplate> _templates = <JobListingTemplate>[];

  @override
  Future<Set<String>> loadFavoriteIds() async => _favoriteIds;

  @override
  Future<void> saveFavoriteIds(Set<String> favoriteIds) async {
    _favoriteIds
      ..clear()
      ..addAll(favoriteIds);
  }

  @override
  Future<JobSeekerProfile> loadJobSeekerProfile() async => _profile;

  @override
  Future<void> saveJobSeekerProfile(JobSeekerProfile profile) async {
    _profile = profile;
  }

  @override
  Future<EmployerProfilesData> loadEmployerProfiles() async => _employerData;

  @override
  Future<void> saveEmployerProfiles(EmployerProfilesData data) async {
    _employerData = data;
  }

  @override
  Future<List<JobListingTemplate>> loadJobTemplates() async =>
      List<JobListingTemplate>.from(_templates);

  @override
  Future<void> saveJobTemplates(List<JobListingTemplate> templates) async {
    _templates
      ..clear()
      ..addAll(templates);
  }

  @override
  Future<JobLoadResult> loadJobs({
    required String backendUrl,
    required List<JobListing> fallbackJobs,
  }) async {
    return JobLoadResult(jobs: List<JobListing>.from(_jobs));
  }

  @override
  Future<JobListing> createJob(JobListing job) async {
    _jobs.add(job);
    return job;
  }

  @override
  Future<JobListing> updateJob(JobListing job) async {
    final index = _jobs.indexWhere((item) => item.id == job.id);
    if (index >= 0) {
      _jobs[index] = job;
    }
    return job;
  }

  @override
  Future<void> deleteJob(JobListing job) async {
    _jobs.removeWhere((item) => item.id == job.id);
  }
}
