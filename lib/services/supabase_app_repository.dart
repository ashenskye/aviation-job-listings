import '../models/application.dart';
import '../models/application_feedback.dart';
import '../models/employer_profile.dart';
import '../models/employer_profiles_data.dart';
import '../models/job_listing.dart';
import '../models/job_listing_report.dart';
import '../models/job_listing_template.dart';
import '../models/job_load_result.dart';
import '../models/job_seeker_profile.dart';
import '../repositories/app_repository.dart';
import 'local_app_repository.dart';
import 'supabase_bootstrap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAppRepository implements AppRepository {
  SupabaseAppRepository({required this.localFallback});

  final LocalAppRepository localFallback;

  SupabaseClient get _client => Supabase.instance.client;

  String? get _currentUserId => _client.auth.currentUser?.id;

  bool _isMissingRequiredRatingsColumnError(PostgrestException error) {
    final combined = [error.message, error.details, error.hint]
        .whereType<String>()
        .join(' ')
        .toLowerCase();
    return combined.contains('required_ratings') &&
        (combined.contains('column') || combined.contains('schema cache'));
  }

  @override
  Future<Set<String>> loadFavoriteIds() async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      return localFallback.loadFavoriteIds();
    }

    final rows = await _client
        .from('saved_jobs')
        .select('job_listing_id')
        .eq('user_id', userId);

    return rows
        .map((row) => row['job_listing_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  @override
  Future<void> saveFavoriteIds(Set<String> favoriteIds) async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      await localFallback.saveFavoriteIds(favoriteIds);
      return;
    }

    await _client.from('saved_jobs').delete().eq('user_id', userId);

    if (favoriteIds.isEmpty) {
      return;
    }

    final payload = favoriteIds
        .map((jobId) => {'user_id': userId, 'job_listing_id': jobId})
        .toList();

    await _client.from('saved_jobs').insert(payload);
  }

  @override
  Future<JobSeekerProfile> loadJobSeekerProfile() async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      return localFallback.loadJobSeekerProfile();
    }

    final row = await _client
        .from('job_seeker_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) {
      return const JobSeekerProfile();
    }

    return JobSeekerProfile.fromJson(_fromJobSeekerRow(row));
  }

  @override
  Future<void> saveJobSeekerProfile(JobSeekerProfile profile) async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      await localFallback.saveJobSeekerProfile(profile);
      return;
    }

    await _client.from('job_seeker_profiles').upsert({
      'user_id': userId,
      ..._toJobSeekerRow(profile),
    });
  }

  @override
  Future<EmployerProfilesData> loadEmployerProfiles() async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      return localFallback.loadEmployerProfiles();
    }

    final profileRows = await _client
        .from('employer_profiles')
        .select()
        .eq('owner_user_id', userId);

    final preferenceRow = await _client
        .from('user_preferences')
        .select('selected_employer_profile_id')
        .eq('user_id', userId)
        .maybeSingle();

    final profiles = profileRows
        .map((row) => EmployerProfile.fromJson(_fromEmployerRow(row)))
        .toList();

    final currentEmployerId = preferenceRow?['selected_employer_profile_id']
        ?.toString();

    return EmployerProfilesData(
      profiles: profiles,
      currentEmployerId: currentEmployerId,
    );
  }

  @override
  Future<void> saveEmployerProfiles(EmployerProfilesData data) async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      await localFallback.saveEmployerProfiles(data);
      return;
    }

    for (final profile in data.profiles) {
      await _client.from('employer_profiles').upsert({
        'id': profile.id,
        'owner_user_id': userId,
        ..._toEmployerRow(profile),
      });
    }

    await _client.from('user_preferences').upsert({
      'user_id': userId,
      'selected_employer_profile_id': data.currentEmployerId,
    });
  }

  @override
  Future<List<JobListingTemplate>> loadJobTemplates() async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      return localFallback.loadJobTemplates();
    }

    try {
      final rows = await _client
          .from('job_listing_templates')
          .select()
          .eq('owner_user_id', userId)
          .order('updated_at', ascending: false);
      return rows
          .map((row) => JobListingTemplate.fromJson(_fromTemplateRow(row)))
          .toList();
    } catch (_) {
      return localFallback.loadJobTemplates();
    }
  }

  @override
  Future<void> saveJobTemplates(List<JobListingTemplate> templates) async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      await localFallback.saveJobTemplates(templates);
      return;
    }

    try {
      await _client
          .from('job_listing_templates')
          .delete()
          .eq('owner_user_id', userId);

      if (templates.isNotEmpty) {
        final payload = templates
            .map((template) => _toTemplateRow(template, ownerUserId: userId))
            .toList();
        await _client.from('job_listing_templates').insert(payload);
      }
    } catch (_) {
      await localFallback.saveJobTemplates(templates);
    }
  }

  @override
  Future<JobLoadResult> loadJobs({
    required String backendUrl,
    required List<JobListing> fallbackJobs,
  }) async {
    if (!SupabaseBootstrap.isConfigured || _currentUserId == null) {
      return localFallback.loadJobs(
        backendUrl: backendUrl,
        fallbackJobs: fallbackJobs,
      );
    }

    try {
      final rows = await _client
          .from('job_listings')
          .select()
          .eq('status', 'active')
          .order('created_at', ascending: false);

      final jobs = rows
          .map((row) => JobListing.fromJson(_fromJobListingRow(row)))
          .toList();
      return JobLoadResult(jobs: jobs);
    } catch (_) {
      return JobLoadResult(
        jobs: fallbackJobs,
        warningMessage: 'Could not load Supabase jobs. Showing local data.',
      );
    }
  }

  @override
  Future<JobListing> createJob(JobListing job) async {
    if (!SupabaseBootstrap.isConfigured || _currentUserId == null) {
      return localFallback.createJob(job);
    }

    // RLS on job_listings requires employer_id to reference an employer_profiles
    // row owned by the current user.  Upsert the linked employer profile first
    // so the existence check passes even on first write.
    final employerId = job.employerId;
    if (employerId != null) {
      await _ensureEmployerNotBanned(employerId);
      final existingEmployer = await _client
          .from('employer_profiles')
          .select('id')
          .eq('id', employerId)
          .eq('owner_user_id', _currentUserId!)
          .maybeSingle();

      if (existingEmployer == null) {
        throw Exception(
          'Employer profile "$employerId" has not been saved to the server yet. '
          'Save your company profile first, then create a job listing.',
        );
      }
    } else {
      throw Exception(
        'A job listing must be linked to a company profile. '
        'Switch to Employer mode, create a company profile, then post a job.',
      );
    }

    final payload = _toJobListingRow(job);
    dynamic inserted;
    try {
      inserted = await _client.from('job_listings').upsert(payload).select().single();
    } on PostgrestException catch (error) {
      if (!_isMissingRequiredRatingsColumnError(error)) {
        rethrow;
      }
      final fallbackPayload = Map<String, dynamic>.from(payload)
        ..remove('required_ratings');
      inserted = await _client
          .from('job_listings')
          .upsert(fallbackPayload)
          .select()
          .single();
    }

    return JobListing.fromJson(_fromJobListingRow(inserted));
  }

  @override
  Future<JobListing> updateJob(JobListing job) async {
    if (!SupabaseBootstrap.isConfigured || _currentUserId == null) {
      return localFallback.updateJob(job);
    }

    final employerId = job.employerId;
    if (employerId == null || employerId.isEmpty) {
      throw Exception('Only employer job listings can be updated.');
    }

    await _ensureEmployerNotBanned(employerId);

    final payload = _toJobListingRow(job)..remove('id');
    List<dynamic> updatedRows;
    try {
      updatedRows = await _client
          .from('job_listings')
          .update(payload)
          .eq('id', job.id)
          .eq('employer_id', employerId)
          .select();
    } on PostgrestException catch (error) {
      if (!_isMissingRequiredRatingsColumnError(error)) {
        rethrow;
      }
      final fallbackPayload = Map<String, dynamic>.from(payload)
        ..remove('required_ratings');
      updatedRows = await _client
          .from('job_listings')
          .update(fallbackPayload)
          .eq('id', job.id)
          .eq('employer_id', employerId)
          .select();
    }

    if (updatedRows.isEmpty) {
      throw Exception(
        'Job listing could not be updated. It may belong to another company or no longer exist.',
      );
    }

    return JobListing.fromJson(_fromJobListingRow(updatedRows.first));
  }

  @override
  Future<void> deleteJob(JobListing job) async {
    if (!SupabaseBootstrap.isConfigured || _currentUserId == null) {
      await localFallback.deleteJob(job);
      return;
    }

    final employerId = job.employerId;
    if (employerId == null || employerId.isEmpty) {
      throw Exception('Only employer job listings can be deleted.');
    }

    await _client.from('saved_jobs').delete().eq('job_listing_id', job.id);

    final deletedRows = await _client
        .from('job_listings')
        .delete()
        .eq('id', job.id)
        .eq('employer_id', employerId)
        .select('id');

    if (deletedRows.isEmpty) {
      throw Exception(
        'Job listing could not be deleted. It may already be gone or belong to a different company.',
      );
    }
  }

  @override
  Future<void> saveApplication(Application app) async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      await localFallback.saveApplication(app);
      return;
    }

    try {
      await _ensureCurrentJobSeekerNotBanned();
      await _client.from('job_applications').upsert({
        'id': app.id,
        'job_listing_id': app.jobId,
        'employer_id': app.employerId,
        'applicant_user_id': userId,
        'status': app.status,
        'match_percentage': app.matchPercentage,
        'data': app.toJson(),
      });
    } catch (_) {
      await localFallback.saveApplication(app);
    }
  }

  @override
  Future<List<Application>> getApplicationsBySeeker(String seekerId) async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      return localFallback.getApplicationsBySeeker(seekerId);
    }

    try {
      final rows = await _client
          .from('job_applications')
          .select()
          .eq('applicant_user_id', userId);
      return rows.map((row) => _fromApplicationRow(row)).toList();
    } catch (_) {
      return localFallback.getApplicationsBySeeker(seekerId);
    }
  }

  @override
  Future<List<Application>> loadApplicationsForEmployer(
    String employerId,
  ) async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      return localFallback.loadApplicationsForEmployer(employerId);
    }

    try {
      final rows = await _client
          .from('job_applications')
          .select()
          .eq('employer_id', employerId);
      return rows.map((row) => _fromApplicationRow(row)).toList();
    } catch (_) {
      return localFallback.loadApplicationsForEmployer(employerId);
    }
  }

  @override
  Future<void> updateApplicationStatus(
    String applicationId,
    String status,
  ) async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      await localFallback.updateApplicationStatus(applicationId, status);
      return;
    }

    try {
      final existingRow = await _client
          .from('job_applications')
          .select()
          .eq('id', applicationId)
          .maybeSingle();

      if (existingRow == null) {
        throw StateError('Application not found: $applicationId');
      }

      final updatedAt = DateTime.now().toIso8601String();
      final existingData = Map<String, dynamic>.from(
        (existingRow['data'] as Map?) ?? const {},
      );
      existingData['status'] = Application.normalizeStatus(status);
      existingData['updated_at'] = updatedAt;

      await _client
          .from('job_applications')
          .update({
            'status': Application.normalizeStatus(status),
            'data': existingData,
            'updated_at': updatedAt,
          })
          .eq('id', applicationId);
    } catch (_) {
      await localFallback.updateApplicationStatus(applicationId, status);
    }
  }

  @override
  Future<void> updateApplicationArchived(
    String applicationId,
    bool isArchived,
  ) async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      await localFallback.updateApplicationArchived(applicationId, isArchived);
      return;
    }

    try {
      final existingRow = await _client
          .from('job_applications')
          .select()
          .eq('id', applicationId)
          .maybeSingle();

      if (existingRow == null) {
        throw StateError('Application not found: $applicationId');
      }

      final updatedAt = DateTime.now().toIso8601String();
      final existingData = Map<String, dynamic>.from(
        (existingRow['data'] as Map?) ?? const {},
      );
      existingData['is_archived'] = isArchived;
      existingData['updated_at'] = updatedAt;

      await _client
          .from('job_applications')
          .update({'data': existingData, 'updated_at': updatedAt})
          .eq('id', applicationId);
    } catch (_) {
      await localFallback.updateApplicationArchived(applicationId, isArchived);
    }
  }

  @override
  Future<void> deleteApplication(String applicationId) async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      await localFallback.deleteApplication(applicationId);
      return;
    }

    try {
      await _client.from('job_applications').delete().eq('id', applicationId);
    } catch (_) {
      await localFallback.deleteApplication(applicationId);
    }
  }

  @override
  Future<void> deleteApplications(List<String> applicationIds) async {
    if (applicationIds.isEmpty) return;
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      await localFallback.deleteApplications(applicationIds);
      return;
    }

    try {
      await _client
          .from('job_applications')
          .delete()
          .inFilter('id', applicationIds);
    } catch (_) {
      await localFallback.deleteApplications(applicationIds);
    }
  }

  @override
  Future<bool> hasApplied(String seekerId, String jobId) async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      return localFallback.hasApplied(seekerId, jobId);
    }

    try {
      final rows = await _client
          .from('job_applications')
          .select('id')
          .eq('applicant_user_id', userId)
          .eq('job_listing_id', jobId)
          .limit(1);
      return rows.isNotEmpty;
    } catch (_) {
      return localFallback.hasApplied(seekerId, jobId);
    }
  }

  @override
  Future<Application?> getLatestApplicationForJob(
    String seekerId,
    String jobId,
  ) async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      return localFallback.getLatestApplicationForJob(seekerId, jobId);
    }

    try {
      final rows = await _client
          .from('job_applications')
          .select()
          .eq('applicant_user_id', userId)
          .eq('job_listing_id', jobId)
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) {
        return null;
      }
      return _fromApplicationRow(rows.first);
    } catch (_) {
      return localFallback.getLatestApplicationForJob(seekerId, jobId);
    }
  }

  @override
  Future<void> reportJobListing(JobListingReport report) async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      await localFallback.reportJobListing(report);
      return;
    }

    try {
      await _client.from('job_listing_reports').insert(report.toJson());
    } catch (_) {
      await localFallback.reportJobListing(report);
    }
  }

  @override
  Future<FeedbackSaveDestination> saveFeedback(
    ApplicationFeedback feedback,
  ) async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      return localFallback.saveFeedback(feedback);
    }

    try {
      await _client.from('application_feedback').upsert({
        'id': feedback.id,
        'application_id': feedback.applicationId,
        'message': feedback.message,
        'feedback_type': feedback.feedbackType,
        'sent_by_employer': feedback.sentByEmployer,
        'sent_at': feedback.sentAt.toIso8601String(),
        'is_auto_generated': feedback.isAutoGenerated,
      }, onConflict: 'application_id');
      return FeedbackSaveDestination.remote;
    } catch (_) {
      return localFallback.saveFeedback(feedback);
    }
  }

  @override
  Future<List<ApplicationFeedback>> getAllFeedback() async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      return localFallback.getAllFeedback();
    }

    try {
      final rows = await _client.from('application_feedback').select();
      return rows
          .map(
            (row) =>
                ApplicationFeedback.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();
    } catch (_) {
      return localFallback.getAllFeedback();
    }
  }

  @override
  Future<ApplicationFeedback?> getFeedbackForApplication(
    String applicationId,
  ) async {
    final userId = _currentUserId;
    if (!SupabaseBootstrap.isConfigured || userId == null) {
      return localFallback.getFeedbackForApplication(applicationId);
    }

    try {
      final row = await _client
          .from('application_feedback')
          .select()
          .eq('application_id', applicationId)
          .maybeSingle();
      if (row == null) {
        return null;
      }
      return ApplicationFeedback.fromJson(Map<String, dynamic>.from(row));
    } catch (_) {
      return localFallback.getFeedbackForApplication(applicationId);
    }
  }

  Application _fromApplicationRow(Map<String, dynamic> row) {
    final data = Map<String, dynamic>.from((row['data'] as Map?) ?? const {});
    data['id'] = row['id'] ?? data['id'];
    data['job_listing_id'] = row['job_listing_id'] ?? data['job_listing_id'];
    data['employer_id'] = row['employer_id'] ?? data['employer_id'];
    data['status'] = row['status'] ?? data['status'];
    data['matchPercentage'] =
        row['match_percentage'] ?? data['matchPercentage'];
    data['updated_at'] = row['updated_at'] ?? data['updated_at'];
    data['applied_at'] = row['created_at'] ?? data['applied_at'];
    return Application.fromJson(data);
  }

  Map<String, dynamic> _toJobListingRow(JobListing job) {
    return {
      'id': job.id,
      'employer_id': job.employerId,
      'title': job.title,
      'company': job.company,
      'location': job.location,
      'employment_type': job.type,
      'crew_role': job.crewRole,
      'crew_position': job.crewPosition,
      'faa_rules': job.faaRules,
      'airframe_scope': job.airframeScope,
      'part135_sub_type': job.part135SubType,
      'description': job.description,
      'faa_certificates': job.faaCertificates,
      'required_ratings': job.requiredRatings,
      'type_ratings_required': job.typeRatingsRequired,
      'flight_experience': job.flightExperience,
      'flight_hours': job.flightHours,
      'preferred_flight_hours': job.preferredFlightHours,
      'instructor_hours': job.instructorHours,
      'preferred_instructor_hours': job.preferredInstructorHours,
      'specialty_experience': job.specialtyExperience,
      'specialty_hours': job.specialtyHours,
      'preferred_specialty_hours': job.preferredSpecialtyHours,
      'aircraft_flown': job.aircraftFlown,
      'salary_range': job.salaryRange,
      'minimum_hours': job.minimumHours,
      'benefits': job.benefits,
      'deadline_date': job.deadlineDate?.toIso8601String(),
      'auto_reject_threshold': job.autoRejectThreshold,
      'reapply_window_days': job.reapplyWindowDays,
      'is_external': job.isExternal,
      'external_apply_url': job.externalApplyUrl,
      'contact_name': job.contactName,
      'contact_email': job.contactEmail,
      'company_phone': job.companyPhone,
      'company_url': job.companyUrl,
      'status': 'active',
    };
  }

  Map<String, dynamic> _fromJobListingRow(Map<String, dynamic> row) {
    final requiredRatings = List<String>.from(
      (row['required_ratings'] as List?) ??
          (row['requiredRatings'] as List?) ??
          const [],
    );
    return {
      'id': row['id'],
      'employerId': row['employer_id'],
      'title': row['title'],
      'company': row['company'],
      'location': row['location'],
      'type': row['employment_type'],
      'crewRole': row['crew_role'],
      'crewPosition': row['crew_position'],
      'faaRules': List<String>.from((row['faa_rules'] as List?) ?? const []),
      'airframeScope': row['airframe_scope'],
      'part135SubType': row['part135_sub_type']?.toString(),
      'description': row['description'],
      'faaCertificates': List<String>.from(
        (row['faa_certificates'] as List?) ?? const [],
      ),
      'requiredRatings': requiredRatings,
      'typeRatingsRequired': List<String>.from(
        (row['type_ratings_required'] as List?) ?? const [],
      ),
      'flightExperience': List<String>.from(
        (row['flight_experience'] as List?) ?? const [],
      ),
      'flightHours': Map<String, dynamic>.from(
        (row['flight_hours'] as Map?) ?? const {},
      ),
      'preferredFlightHours': List<String>.from(
        (row['preferred_flight_hours'] as List?) ?? const [],
      ),
      'instructorHours': Map<String, dynamic>.from(
        (row['instructor_hours'] as Map?) ?? const {},
      ),
      'preferredInstructorHours': List<String>.from(
        (row['preferred_instructor_hours'] as List?) ?? const [],
      ),
      'specialtyExperience': List<String>.from(
        (row['specialty_experience'] as List?) ?? const [],
      ),
      'specialtyHours': Map<String, dynamic>.from(
        (row['specialty_hours'] as Map?) ?? const {},
      ),
      'preferredSpecialtyHours': List<String>.from(
        (row['preferred_specialty_hours'] as List?) ?? const [],
      ),
      'aircraftFlown': List<String>.from(
        (row['aircraft_flown'] as List?) ?? const [],
      ),
      'salaryRange': row['salary_range'],
      'minimumHours': row['minimum_hours'],
      'benefits': List<String>.from((row['benefits'] as List?) ?? const []),
      'deadlineDate': row['deadline_date'],
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
      'autoRejectThreshold':
          (row['auto_reject_threshold'] as num?)?.toInt() ?? 0,
      'reapplyWindowDays': (row['reapply_window_days'] as num?)?.toInt() ?? 30,
      'isExternal': (row['is_external'] as bool?) ?? false,
      'externalApplyUrl': row['external_apply_url'],
      'contactName': row['contact_name'],
      'contactEmail': row['contact_email'],
      'companyPhone': row['company_phone'],
      'companyUrl': row['company_url'],
    };
  }

  Map<String, dynamic> _toJobSeekerRow(JobSeekerProfile profile) {
    return {
      'full_name': profile.fullName,
      'email': profile.email,
      'phone': profile.phone,
      'city': profile.city,
      'state_or_province': profile.stateOrProvince,
      'country': profile.country,
      'airframe_scope': profile.airframeScope,
      'faa_certificates': profile.faaCertificates,
      'type_ratings': profile.typeRatings,
      'flight_hours': profile.flightHours,
      'flight_hours_types': profile.flightHoursTypes,
      'specialty_flight_hours': profile.specialtyFlightHours,
      'specialty_flight_hours_map': profile.specialtyFlightHoursMap,
      'aircraft_flown': profile.aircraftFlown,
      'total_flight_hours': profile.totalFlightHours,
    };
  }

  Map<String, dynamic> _fromJobSeekerRow(Map<String, dynamic> row) {
    return {
      'fullName': row['full_name'],
      'email': row['email'],
      'phone': row['phone'],
      'city': row['city'],
      'stateOrProvince': row['state_or_province'],
      'country': row['country'],
      'airframeScope': row['airframe_scope'],
      'faaCertificates': List<String>.from(
        (row['faa_certificates'] as List?) ?? const [],
      ),
      'typeRatings': List<String>.from(
        (row['type_ratings'] as List?) ?? const [],
      ),
      'flightHours': Map<String, dynamic>.from(
        (row['flight_hours'] as Map?) ?? const {},
      ),
      'flightHoursTypes': List<String>.from(
        (row['flight_hours_types'] as List?) ?? const [],
      ),
      'specialtyFlightHours': List<String>.from(
        (row['specialty_flight_hours'] as List?) ?? const [],
      ),
      'specialtyFlightHoursMap': Map<String, dynamic>.from(
        (row['specialty_flight_hours_map'] as Map?) ?? const {},
      ),
      'aircraftFlown': List<String>.from(
        (row['aircraft_flown'] as List?) ?? const [],
      ),
      'totalFlightHours': row['total_flight_hours'] ?? 0,
    };
  }

  Map<String, dynamic> _toEmployerRow(EmployerProfile profile) {
    return {
      'company_name': profile.companyName,
      'headquarters_address_line1': profile.headquartersAddressLine1,
      'headquarters_address_line2': profile.headquartersAddressLine2,
      'headquarters_city': profile.headquartersCity,
      'headquarters_state': profile.headquartersState,
      'headquarters_postal_code': profile.headquartersPostalCode,
      'headquarters_country': profile.headquartersCountry,
      'company_banner_url': profile.companyBannerUrl,
      'company_logo_url': profile.companyLogoUrl,
      'website': profile.website,
      'contact_name': profile.contactName,
      'contact_email': profile.contactEmail,
      'contact_phone': profile.contactPhone,
      'company_description': profile.companyDescription,
      'company_benefits': profile.companyBenefits,
    };
  }

  Map<String, dynamic> _fromEmployerRow(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'companyName': row['company_name'],
      'headquartersAddressLine1': row['headquarters_address_line1'],
      'headquartersAddressLine2': row['headquarters_address_line2'],
      'headquartersCity': row['headquarters_city'],
      'headquartersState': row['headquarters_state'],
      'headquartersPostalCode': row['headquarters_postal_code'],
      'headquartersCountry': row['headquarters_country'],
      'companyBannerUrl': row['company_banner_url'],
      'companyLogoUrl': row['company_logo_url'],
      'website': row['website'],
      'contactName': row['contact_name'],
      'contactEmail': row['contact_email'],
      'contactPhone': row['contact_phone'],
      'companyDescription': row['company_description'],
      'companyBenefits': List<String>.from(
        (row['company_benefits'] as List?) ?? const [],
      ),
    };
  }

  Map<String, dynamic> _toTemplateRow(
    JobListingTemplate template, {
    required String ownerUserId,
  }) {
    return {
      'id': template.id,
      'owner_user_id': ownerUserId,
      'employer_id': template.employerId,
      'template_name': template.name,
      'listing': template.listing.toJson(),
    };
  }

  Map<String, dynamic> _fromTemplateRow(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'employerId': row['employer_id'],
      'name': row['template_name'],
      'listing': Map<String, dynamic>.from(
        (row['listing'] as Map?) ?? const {},
      ),
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
    };
  }

  Future<void> _ensureEmployerNotBanned(String employerId) async {
    final row = await _client
        .from('employer_moderation')
        .select('is_banned, ban_reason')
        .eq('employer_id', employerId)
        .maybeSingle();

    if ((row?['is_banned'] as bool?) == true) {
      final reason = row?['ban_reason']?.toString().trim() ?? '';
      throw Exception(
        reason.isEmpty
            ? 'This employer profile has been banned from posting new listings.'
            : 'This employer profile has been banned from posting new listings. Reason: $reason',
      );
    }
  }

  Future<void> _ensureCurrentJobSeekerNotBanned() async {
    final userId = _currentUserId;
    if (userId == null) {
      return;
    }

    final row = await _client
        .from('job_seeker_moderation')
        .select('is_banned, ban_reason')
        .eq('user_id', userId)
        .maybeSingle();

    if ((row?['is_banned'] as bool?) == true) {
      final reason = row?['ban_reason']?.toString().trim() ?? '';
      throw Exception(
        reason.isEmpty
            ? 'This job seeker account has been banned from applying.'
            : 'This job seeker account has been banned from applying. Reason: $reason',
      );
    }
  }
}
