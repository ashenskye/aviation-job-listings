import 'package:aviation_job_listings/models/application.dart';
import 'package:aviation_job_listings/models/application_feedback.dart';
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
  final List<Application> _applications = <Application>[];
  final List<ApplicationFeedback> _feedback = <ApplicationFeedback>[];

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

  @override
  Future<void> saveApplication(Application app) async {
    final index = _applications.indexWhere((a) => a.id == app.id);
    if (index >= 0) {
      _applications[index] = app;
    } else {
      _applications.add(app);
    }
  }

  @override
  Future<List<Application>> getApplicationsBySeeker(String seekerId) async {
    return _applications
        .where((app) => app.jobSeekerId == seekerId)
        .toList();
  }

  @override
  Future<List<Application>> loadApplicationsForEmployer(String employerId) async {
    return _applications.where((app) => app.employerId == employerId).toList();
  }

  @override
  Future<void> updateApplicationStatus(String applicationId, String status) async {
    final index = _applications.indexWhere((app) => app.id == applicationId);
    if (index < 0) {
      return;
    }

    _applications[index] = _applications[index].copyWith(
      status: status,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<bool> hasApplied(String seekerId, String jobId) async {
    return _applications.any(
      (app) => app.jobSeekerId == seekerId && app.jobId == jobId,
    );
  }

  @override
  Future<Application?> getLatestApplicationForJob(
    String seekerId,
    String jobId,
  ) async {
    final matching = _applications
        .where((app) => app.jobSeekerId == seekerId && app.jobId == jobId)
        .toList()
      ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
    return matching.isEmpty ? null : matching.first;
  }

  @override
  Future<FeedbackSaveDestination> saveFeedback(
    ApplicationFeedback feedback,
  ) async {
    final index = _feedback.indexWhere(
      (f) => f.applicationId == feedback.applicationId,
    );
    if (index >= 0) {
      _feedback[index] = feedback;
    } else {
      _feedback.add(feedback);
    }
    return FeedbackSaveDestination.local;
  }

  @override
  Future<List<ApplicationFeedback>> getAllFeedback() async {
    return List<ApplicationFeedback>.from(_feedback);
  }

  @override
  Future<ApplicationFeedback?> getFeedbackForApplication(
    String applicationId,
  ) async {
    try {
      return _feedback.firstWhere((f) => f.applicationId == applicationId);
    } catch (_) {
      return null;
    }
  }
}
