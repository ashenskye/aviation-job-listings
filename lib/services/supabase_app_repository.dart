import '../models/employer_profile.dart';
import '../models/employer_profiles_data.dart';
import '../models/job_listing.dart';
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
  Future<JobLoadResult> loadJobs({
    required String backendUrl,
    required List<JobListing> fallbackJobs,
    required JobListing testingJob,
  }) async {
    if (!SupabaseBootstrap.isConfigured || _currentUserId == null) {
      return localFallback.loadJobs(
        backendUrl: backendUrl,
        fallbackJobs: fallbackJobs,
        testingJob: testingJob,
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

      final nonTestJobs = jobs.where((job) => job.id != testingJob.id).toList();
      return JobLoadResult(jobs: [testingJob, ...nonTestJobs]);
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
    final inserted = await _client
        .from('job_listings')
        .upsert(payload)
        .select()
        .single();

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

    final payload = _toJobListingRow(job)..remove('id');
    final updatedRows = await _client
        .from('job_listings')
        .update(payload)
        .eq('id', job.id)
        .eq('employer_id', employerId)
        .select();

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
      'description': job.description,
      'faa_certificates': job.faaCertificates,
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
      'status': 'active',
    };
  }

  Map<String, dynamic> _fromJobListingRow(Map<String, dynamic> row) {
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
      'description': row['description'],
      'faaCertificates': List<String>.from(
        (row['faa_certificates'] as List?) ?? const [],
      ),
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
      'website': profile.website,
      'contact_name': profile.contactName,
      'contact_email': profile.contactEmail,
      'contact_phone': profile.contactPhone,
      'company_description': profile.companyDescription,
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
      'website': row['website'],
      'contactName': row['contact_name'],
      'contactEmail': row['contact_email'],
      'contactPhone': row['contact_phone'],
      'companyDescription': row['company_description'],
    };
  }
}
