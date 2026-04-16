import 'dart:math' as math;
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/application.dart';
import 'models/application_feedback.dart';
import 'models/aviation_certificate_utils.dart';
import 'models/employer_profile.dart';
import 'models/employer_profiles_data.dart';
import 'models/job_listing.dart';
import 'models/job_listing_template.dart';
import 'models/job_seeker_profile.dart';
import 'repositories/app_repository.dart';
import 'screens/sign_in_screen.dart';
import 'services/app_repository_factory.dart';
import 'services/supabase_bootstrap.dart';
import 'services/web_image_file_picker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseBootstrap.initializeIfConfigured();

  final repository = AppRepositoryFactory.create();
  runApp(MyApp(repository: repository));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.repository});

  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aviation Job Listings',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: SupabaseBootstrap.isConfigured
          ? _AuthGate(repository: repository)
          : MyHomePage(title: 'Aviation Job Listings', repository: repository),
    );
  }
}

ProfileType _profileTypeFromMetadata(Object? value) {
  if (value?.toString() == 'employer') {
    return ProfileType.employer;
  }
  return ProfileType.jobSeeker;
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.repository});

  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;
        if (session != null) {
          final initialType = _profileTypeFromMetadata(
            session.user.userMetadata?['profile_type'],
          );
          return MyHomePage(
            title: 'Aviation Job Listings',
            repository: repository,
            initialProfileType: initialType,
          );
        }
        return const SignInScreen();
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.repository,
    this.initialProfileType,
  });

  final String title;
  final AppRepository repository;
  final ProfileType? initialProfileType;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum ProfileType { employer, jobSeeker }

String _formatHoursRequirementLabel(String name, int hours, bool isPreferred) {
  final parts = <String>[name];

  if (hours > 0) {
    parts.add('$hours hrs');
  }

  parts.add(isPreferred ? 'Preferred' : 'Required');
  return parts.join(' - ');
}

String _formatHoursRequirementMissing(String label, String name, int hours) {
  if (hours > 0) {
    return '$label: $name ($hours hrs)';
  }

  return '$label: $name';
}

String _formatYmd(DateTime date) {
  return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
}

int? _parsePositiveInt(String value) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null || parsed <= 0) {
    return null;
  }
  return parsed;
}

String _phoneDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

String _formatPhoneNumber(String value) {
  final digits = _phoneDigits(value);
  if (digits.isEmpty) {
    return '';
  }

  if (digits.length <= 3) {
    return '($digits';
  }

  if (digits.length <= 6) {
    return '(${digits.substring(0, 3)}) ${digits.substring(3)}';
  }

  final localEnd = math.min(10, digits.length);
  final base =
      '(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6, localEnd)}';

  if (digits.length > 10) {
    return '$base x${digits.substring(10)}';
  }

  return base;
}

int _phoneCursorOffset(String formatted, int digitCount) {
  if (digitCount <= 0) {
    return 0;
  }

  var seen = 0;
  for (var i = 0; i < formatted.length; i++) {
    final char = formatted[i];
    if (RegExp(r'\d').hasMatch(char)) {
      seen++;
      if (seen >= digitCount) {
        return i + 1;
      }
    }
  }

  return formatted.length;
}

class _PhoneNumberTextInputFormatter extends TextInputFormatter {
  const _PhoneNumberTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = _formatPhoneNumber(newValue.text);
    final baseOffset = newValue.selection.baseOffset;
    final clampedOffset = math.max(
      0,
      math.min(baseOffset, newValue.text.length),
    );
    final digitsBeforeCursor = _phoneDigits(
      newValue.text.substring(0, clampedOffset),
    ).length;
    final selectionOffset = _phoneCursorOffset(formatted, digitsBeforeCursor);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: selectionOffset),
      composing: TextRange.empty,
    );
  }
}

bool _shouldShowUpdatedDate({DateTime? createdAt, DateTime? updatedAt}) {
  if (updatedAt == null) {
    return false;
  }
  if (createdAt == null) {
    return true;
  }
  return updatedAt.toUtc().isAfter(createdAt.toUtc());
}

List<String> _buildTimelineLabels({
  DateTime? createdAt,
  DateTime? updatedAt,
  bool includeUnavailable = false,
}) {
  final labels = <String>[];

  if (createdAt != null) {
    labels.add('Posted: ${_formatYmd(createdAt.toLocal())}');
  } else if (includeUnavailable) {
    labels.add('Posted: Unavailable');
  }

  if (_shouldShowUpdatedDate(createdAt: createdAt, updatedAt: updatedAt)) {
    labels.add('Last Updated: ${_formatYmd(updatedAt!.toLocal())}');
  } else if (includeUnavailable && updatedAt == null) {
    labels.add('Last Updated: Unavailable');
  }

  return labels;
}

class _MatchResult {
  final bool isFullMatch;
  final int matchedCount;
  final int totalCount;
  final List<String> missingRequirements;

  const _MatchResult({
    required this.isFullMatch,
    required this.matchedCount,
    required this.totalCount,
    required this.missingRequirements,
  });

  int get matchPercentage =>
      totalCount == 0 ? 100 : ((matchedCount * 100) ~/ totalCount);
}

_MatchResult _evaluateJobMatchForProfile({
  required JobListing job,
  required JobSeekerProfile profile,
  bool includeCertPrefix = true,
}) {
  final missingRequirements = <String>[];
  var matchedCount = 0;
  var totalCount = 0;
  final profileCertificates = <String>{
    for (final cert in profile.faaCertificates)
      ...expandedCertificateQualifications(cert),
  };

  for (final cert in job.faaCertificates) {
    totalCount++;
    if (profileCertificates.contains(normalizeCertificateName(cert))) {
      matchedCount++;
    } else {
      final certificateLabel = canonicalCertificateLabel(cert);
      missingRequirements.add(
        includeCertPrefix ? 'Cert: $certificateLabel' : certificateLabel,
      );
    }
  }

  for (final requirement in job.flightHoursByType.entries) {
    final isPreferred = job.preferredFlightHours.contains(requirement.key);
    if (isPreferred) {
      continue;
    }

    totalCount++;
    final profileHours = profile.flightHours[requirement.key] ?? 0;
    final hasRequirement =
        profile.flightHoursTypes.contains(requirement.key) &&
        profileHours >= requirement.value;

    if (hasRequirement) {
      matchedCount++;
    } else {
      missingRequirements.add(
        _formatHoursRequirementMissing(
          'Flight Hours',
          requirement.key,
          requirement.value,
        ),
      );
    }
  }

  for (final requirement in job.instructorHoursByType.entries) {
    final isPreferred = job.preferredInstructorHours.contains(requirement.key);
    if (isPreferred) {
      continue;
    }

    totalCount++;
    final profileHours = profile.flightHours[requirement.key] ?? 0;
    final hasRequirement =
        profile.flightHoursTypes.contains(requirement.key) &&
        profileHours >= requirement.value;

    if (hasRequirement) {
      matchedCount++;
    } else {
      missingRequirements.add(
        _formatHoursRequirementMissing(
          'Instructor Hours',
          requirement.key,
          requirement.value,
        ),
      );
    }
  }

  for (final requirement in job.specialtyHoursByType.entries) {
    final isPreferred = job.preferredSpecialtyHours.contains(requirement.key);
    if (isPreferred) {
      continue;
    }

    totalCount++;
    final profileHours = profile.specialtyFlightHoursMap[requirement.key] ?? 0;
    final hasRequirement =
        profile.specialtyFlightHours.contains(requirement.key) &&
        profileHours >= requirement.value;

    if (hasRequirement) {
      matchedCount++;
    } else {
      missingRequirements.add(
        _formatHoursRequirementMissing(
          'Specialty Hours',
          requirement.key,
          requirement.value,
        ),
      );
    }
  }

  if (totalCount == 0) {
    totalCount = 1;
    matchedCount = 1;
  }

  return _MatchResult(
    isFullMatch: missingRequirements.isEmpty,
    matchedCount: matchedCount,
    totalCount: totalCount,
    missingRequirements: missingRequirements,
  );
}

class _MyHomePageState extends State<MyHomePage> {
  static const String _cookieConsentAcceptedKey = 'web_cookie_consent_accepted';

  // ============================================================================
  // CONFIGURATION: Static Options for Aviation Categories
  // (Edit these sections to add/remove/customize aviation options)
  // ============================================================================

  // --- FAA CERTIFICATES & RATINGS ---
  static const List<String> _availableFaaCertificates = [
    'Airline Transport Pilot (ATP)',
    'Commercial Pilot (CPL)',
    'Instrument Rating (IFR)',
    'Private Pilot (PPL)',
    'Airframe & Powerplant (A&P)',
    'Inspection Authorization (IA)',
    'Dispatcher (DSP)',
  ];

  static const List<String> _availableInstructorCertificates = [
    'Flight Instructor (CFI)',
    'Instrument Instructor (CFII)',
    'Multi-Engine Instructor (MEI)',
  ];

  // --- FAA OPERATIONAL RULES/SCOPE ---
  static const List<String> _availableFaaRules = [
    'Part 121',
    'Part 135',
    'Part 91',
  ];

  static const List<String> _availableEmployerFlightHours = [
    'Total Time',
    'PIC Jet',
    'SIC Jet',
    'PIC Turbine',
    'SIC Turbine',
    'PIC',
    'SIC',
    'Multi-engine',
  ];

  static const List<String> _availableInstructorHours = [
    'Total Instructor Hours',
    'Instrument (CFII)',
    'Multi-Engine (MEI)',
  ];

  static const List<String> _availableJobTypes = [
    'Full-Time',
    'Part-Time',
    'Seasonal',
    'Rotations',
    'Contract',
  ];

  static const List<String> _availableRatingSelections = [
    'Multi-Engine Land',
    'Single-Engine Land',
    'Multi-Engine Sea',
    'Single-Engine Sea',
    'Tailwheel Endorsement',
    'Rotorcraft',
    'Gyroplane',
    'Glider',
    'Lighter-than-Air',
  ];

  static const List<String> _availablePayRateMetrics = [
    'Flight Hour',
    'Hourly Pay for Duty Time',
    'Daily Rate',
    'Weekly Salary',
    'Monthly Salary',
    'Annual Salary',
    'Shift',
    'Contract Completion',
  ];

  static const List<String> _usStateOptions = [
    'Alabama',
    'Alaska',
    'Arizona',
    'Arkansas',
    'California',
    'Colorado',
    'Connecticut',
    'Delaware',
    'District of Columbia',
    'Florida',
    'Georgia',
    'Hawaii',
    'Idaho',
    'Illinois',
    'Indiana',
    'Iowa',
    'Kansas',
    'Kentucky',
    'Louisiana',
    'Maine',
    'Maryland',
    'Massachusetts',
    'Michigan',
    'Minnesota',
    'Mississippi',
    'Missouri',
    'Montana',
    'Nebraska',
    'Nevada',
    'New Hampshire',
    'New Jersey',
    'New Mexico',
    'New York',
    'North Carolina',
    'North Dakota',
    'Ohio',
    'Oklahoma',
    'Oregon',
    'Pennsylvania',
    'Rhode Island',
    'South Carolina',
    'South Dakota',
    'Tennessee',
    'Texas',
    'Utah',
    'Vermont',
    'Virginia',
    'Washington',
    'West Virginia',
    'Wisconsin',
    'Wyoming',
  ];

  static const List<String> _canadaProvinceOptions = [
    'Alberta',
    'British Columbia',
    'Manitoba',
    'New Brunswick',
    'Newfoundland and Labrador',
    'Northwest Territories',
    'Nova Scotia',
    'Nunavut',
    'Ontario',
    'Prince Edward Island',
    'Quebec',
    'Saskatchewan',
    'Yukon',
  ];

  static const List<String> _countryOptions = ['USA', 'Canada'];

  static const List<String> _stateProvinceOptions = [
    ..._usStateOptions,
    ..._canadaProvinceOptions,
  ];

  static const List<String> _companyBenefitOptions = [
    'Health Insurance',
    '401K',
    'Relocation Reinbursement',
    'Sign-On Bonus',
    'Longevity Bonus',
    'Flight Benefits',
    'Paid Vacation',
    'Paid Sick Leave',
    'Maternity Leave',
  ];

  static const Map<String, String> _stateProvinceAbbreviations = {
    'Alabama': 'AL',
    'Alaska': 'AK',
    'Arizona': 'AZ',
    'Arkansas': 'AR',
    'California': 'CA',
    'Colorado': 'CO',
    'Connecticut': 'CT',
    'Delaware': 'DE',
    'District of Columbia': 'DC',
    'Florida': 'FL',
    'Georgia': 'GA',
    'Hawaii': 'HI',
    'Idaho': 'ID',
    'Illinois': 'IL',
    'Indiana': 'IN',
    'Iowa': 'IA',
    'Kansas': 'KS',
    'Kentucky': 'KY',
    'Louisiana': 'LA',
    'Maine': 'ME',
    'Maryland': 'MD',
    'Massachusetts': 'MA',
    'Michigan': 'MI',
    'Minnesota': 'MN',
    'Mississippi': 'MS',
    'Missouri': 'MO',
    'Montana': 'MT',
    'Nebraska': 'NE',
    'Nevada': 'NV',
    'New Hampshire': 'NH',
    'New Jersey': 'NJ',
    'New Mexico': 'NM',
    'New York': 'NY',
    'North Carolina': 'NC',
    'North Dakota': 'ND',
    'Ohio': 'OH',
    'Oklahoma': 'OK',
    'Oregon': 'OR',
    'Pennsylvania': 'PA',
    'Rhode Island': 'RI',
    'South Carolina': 'SC',
    'South Dakota': 'SD',
    'Tennessee': 'TN',
    'Texas': 'TX',
    'Utah': 'UT',
    'Vermont': 'VT',
    'Virginia': 'VA',
    'Washington': 'WA',
    'West Virginia': 'WV',
    'Wisconsin': 'WI',
    'Wyoming': 'WY',
    'Alberta': 'AB',
    'British Columbia': 'BC',
    'Manitoba': 'MB',
    'New Brunswick': 'NB',
    'Newfoundland and Labrador': 'NL',
    'Northwest Territories': 'NT',
    'Nova Scotia': 'NS',
    'Nunavut': 'NU',
    'Ontario': 'ON',
    'Prince Edward Island': 'PE',
    'Quebec': 'QC',
    'Saskatchewan': 'SK',
    'Yukon': 'YT',
  };

  // --- SPECIALTY EXPERIENCE (Future: Consider adding to Job Seeker profile) ---
  static const List<String> _availableSpecialtyExperience = [
    'Fire Fighting',
    'Aerobatic',
    'Floatplane',
    'Tailwheel',
    'Off Airport',
    'Banner Towing',
    'Low Altitude',
    'Aerial Survey',
  ];

  // ============================================================================
  // UI CONTROLLERS: Text input fields for forms
  // ============================================================================

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _createTitleController = TextEditingController();
  final FocusNode _createTitleFocusNode = FocusNode();
  final TextEditingController _createCompanyController =
      TextEditingController();
  final TextEditingController _createLocationController =
      TextEditingController();
  final TextEditingController _createTypeController = TextEditingController();
  final TextEditingController _createStartingPayController =
      TextEditingController();
  final TextEditingController _createPayForExperienceController =
      TextEditingController();
  final TextEditingController _createDescriptionController =
      TextEditingController();
  final TextEditingController _createTypeRatingsController =
      TextEditingController();
  final TextEditingController _createAircraftController =
      TextEditingController();
  final TextEditingController _createReapplyWindowDaysController =
      TextEditingController(text: '30');
  final TextEditingController _profileFullNameController =
      TextEditingController();
  final TextEditingController _profileEmailController = TextEditingController();
  final TextEditingController _profilePhoneController = TextEditingController();
  final TextEditingController _profileCityController = TextEditingController();
  final TextEditingController _profileStateController = TextEditingController();
  final TextEditingController _profileCountryController =
      TextEditingController();
  final TextEditingController _profileTotalFlightHoursController =
      TextEditingController();
  final TextEditingController _profileTypeRatingsController =
      TextEditingController();
  final TextEditingController _profileAircraftController =
      TextEditingController();

  // ============================================================================
  // APP STATE: Backend, navigation, UI state
  // ============================================================================

  static const String _backendUrl =
      'https://run.mocky.io/v3/876c9fba-a9dc-4a1b-bb4e-900aeb264bb5';
  static const int _pageSize = 5;

  late final AppRepository _appRepository;
  // Initialised in initState from widget.initialProfileType.
  late ProfileType _profileType;
  // Tracks whether the Employer Profile tab is in edit mode.
  bool _employerProfileEditing = false;
  String _query = '';
  int _page = 1;
  bool _loading = true;
  String? _loadingError;
  bool _showCookieConsentBanner = false;
  bool _uploadingEmployerLogoImage = false;
  bool _uploadingEmployerBannerImage = false;

  // ============================================================================
  // JOB LISTING STATE: Data models and data persistence
  // ============================================================================

  late List<JobListing> _allJobs;
  List<JobListingTemplate> _jobTemplates = const [];
  final Set<String> _favoriteIds = {};

  // ============================================================================
  // APPLICATION STATE: Job seeker applications
  // ============================================================================

  static const String _localJobSeekerId = 'local_seeker';
  static const int _maxReapplyWindowDays = 365;

  List<Application> _myApplications = const [];
  List<Application> _employerApplications = const [];
  List<ApplicationFeedback> _allFeedback = const [];
  String _selectedEmployerApplicationFilter = 'all';
  String _selectedEmployerApplicationSort = 'newest';
  String _selectedMatchFilter = 'all';
  Map<String, bool> _applicationsByJobId = {};

  bool _hasApplied(String jobId) => _applicationsByJobId[jobId] ?? false;

  String _generateApplicationId() =>
      DateTime.now().millisecondsSinceEpoch.toString();

  String _generateFeedbackId() =>
      'fb_${DateTime.now().millisecondsSinceEpoch}';

  ApplicationFeedback? _getFeedbackForApplication(String applicationId) {
    try {
      return _allFeedback.firstWhere((f) => f.applicationId == applicationId);
    } catch (_) {
      return null;
    }
  }

  // ============================================================================
  // JOB CREATION FORM STATE: User selections for creating new job listings
  // ============================================================================

  bool _useCompanyLocationForJob = true;
  String _selectedCrewRole = 'Single Pilot';
  String _selectedCrewPosition = 'Captain';
  final List<String> _selectedFaaRules = [];
  final List<String> _selectedFaaCertificates = [];
  final Map<String, int> _selectedFlightHours = {};
  final Set<String> _preferredFlightHours = {};
  final Map<String, int> _selectedInstructorHours = {};
  final Set<String> _preferredInstructorHours = {};
  final Map<String, int> _selectedSpecialtyHours = {};
  final Set<String> _preferredSpecialtyHours = {};
  DateTime? _createDeadlineDate;
  bool _createOpenListing = true;
  final Set<String> _selectedEmployerBenefits = {};
  int _createJobStep = 0;
  String? _selectedCreatePositionOption;
  String? _selectedCreatePayRateMetric;
  String? _selectedTemplateId;
  String? _editingTemplateId;
  bool _createOpenedFromTemplate = false;
  String? _expandedCreateRequirementsSection = 'Certificates and Ratings';

  // Application Preferences
  bool _createAutoRejectEnabled = false;
  int _createAutoRejectThreshold = 65;
  int _createReapplyWindowDays = 30;

  // ============================================================================
  // JOB SEEKER PROFILE STATE: User profile data for matching
  // ============================================================================

  late JobSeekerProfile _jobSeekerProfile;

  // ============================================================================
  // EMPLOYER PROFILE STATE: Employer company data and multi-employer support
  // ============================================================================

  late EmployerProfile _currentEmployer;
  late List<EmployerProfile> _employerProfiles;

  // UI CONTROLLERS: Employer profile form
  final TextEditingController _employerCompanyNameController =
      TextEditingController();
  final TextEditingController _employerAddressLine1Controller =
      TextEditingController();
  final TextEditingController _employerAddressLine2Controller =
      TextEditingController();
  final TextEditingController _employerCityController = TextEditingController();
  final TextEditingController _employerStateController =
      TextEditingController();
  final TextEditingController _employerPostalCodeController =
      TextEditingController();
  final TextEditingController _employerCountryController =
      TextEditingController();
  final TextEditingController _employerBannerUrlController =
      TextEditingController();
  final TextEditingController _employerLogoUrlController =
      TextEditingController();
  final TextEditingController _employerWebsiteController =
      TextEditingController();
  final TextEditingController _employerContactNameController =
      TextEditingController();
  final TextEditingController _employerContactEmailController =
      TextEditingController();
  final TextEditingController _employerContactPhoneController =
      TextEditingController();
  final TextEditingController _employerDescriptionController =
      TextEditingController();

  // ============================================================================
  // LIFECYCLE & INITIALIZATION
  // ============================================================================

  @override
  void initState() {
    super.initState();
    _appRepository = widget.repository;
    _profileType = widget.initialProfileType ?? ProfileType.jobSeeker;
    _allJobs = const [];
    _jobSeekerProfile = const JobSeekerProfile();
    _employerProfiles = [];
    _currentEmployer = const EmployerProfile(
      id: 'default',
      companyName: 'My Company',
    );
    _loadFavorites();
    _loadJobSeekerProfile();
    _loadEmployerProfiles();
    _loadJobTemplates();
    _loadMyApplications();
    _loadEmployerApplications();
    _loadAllFeedback();
    _loadCookieConsentPreference();
    _fetchJobs();
  }

  Future<void> _loadCookieConsentPreference() async {
    if (!kIsWeb) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    final accepted = preferences.getBool(_cookieConsentAcceptedKey) ?? false;
    if (!mounted) {
      return;
    }

    setState(() {
      _showCookieConsentBanner = !accepted;
    });
  }

  Future<void> _acceptCookieConsent() async {
    if (!kIsWeb) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_cookieConsentAcceptedKey, true);
    if (!mounted) {
      return;
    }

    setState(() {
      _showCookieConsentBanner = false;
    });
  }

  Widget _buildCookieConsentBanner() {
    return Material(
      elevation: 8,
      color: Colors.blueGrey.shade900,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'This website uses cookies and similar technologies to improve functionality, analyze traffic, and personalize your experience. By continuing to use this site, you agree to our use of cookies.',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _acceptCookieConsent,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueGrey.shade900,
                ),
                child: const Text('Accept'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadFavorites() async {
    final stored = await _appRepository.loadFavoriteIds();
    if (!mounted) {
      return;
    }

    setState(() {
      _favoriteIds.clear();
      _favoriteIds.addAll(stored);
    });
  }

  Future<void> _saveFavorites() async {
    await _appRepository.saveFavoriteIds(_favoriteIds);
  }

  Future<void> _loadJobSeekerProfile() async {
    final loadedProfile = await _appRepository.loadJobSeekerProfile();
    final hydratedProfile = loadedProfile.copyWith(
      email: _resolvedJobSeekerEmail(loadedProfile),
      faaCertificates: _canonicalizeCertificates(loadedProfile.faaCertificates),
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _jobSeekerProfile = hydratedProfile;
    });
    _syncJobSeekerProfileControllers(hydratedProfile);
  }

  Future<void> _saveJobSeekerProfile() async {
    final persistedProfile = _jobSeekerProfile.copyWith(
      email: _resolvedJobSeekerEmail(_jobSeekerProfile),
      faaCertificates: _canonicalizeCertificates(
        _jobSeekerProfile.faaCertificates,
      ),
    );
    _jobSeekerProfile = persistedProfile;
    await _appRepository.saveJobSeekerProfile(persistedProfile);
  }

  String _signedInJobSeekerEmail() {
    if (!SupabaseBootstrap.isConfigured) {
      return '';
    }
    return Supabase.instance.client.auth.currentUser?.email?.trim() ?? '';
  }

  String _resolvedJobSeekerEmail(JobSeekerProfile profile) {
    final signedInEmail = _signedInJobSeekerEmail();
    if (signedInEmail.isNotEmpty) {
      return signedInEmail;
    }
    return profile.email.trim();
  }

  String _canonicalizeCertificateLabel(String cert) {
    return canonicalCertificateLabel(cert);
  }

  List<String> _canonicalizeCertificates(Iterable<String> certs) {
    return certs.map(_canonicalizeCertificateLabel).toSet().toList();
  }

  JobListing _canonicalizeJobListing(JobListing job) {
    return JobListing(
      id: job.id,
      title: job.title,
      company: job.company,
      location: job.location,
      type: job.type,
      crewRole: job.crewRole,
      crewPosition: job.crewPosition,
      faaRules: List<String>.from(job.faaRules),
      description: job.description,
      faaCertificates: _canonicalizeCertificates(job.faaCertificates),
      typeRatingsRequired: List<String>.from(job.typeRatingsRequired),
      flightExperience: List<String>.from(job.flightExperience),
      flightHours: Map<String, int>.from(job.flightHours),
      preferredFlightHours: List<String>.from(job.preferredFlightHours),
      instructorHours: Map<String, int>.from(job.instructorHours),
      preferredInstructorHours: List<String>.from(job.preferredInstructorHours),
      specialtyExperience: List<String>.from(job.specialtyExperience),
      specialtyHours: Map<String, int>.from(job.specialtyHours),
      preferredSpecialtyHours: List<String>.from(job.preferredSpecialtyHours),
      aircraftFlown: List<String>.from(job.aircraftFlown),
      salaryRange: job.salaryRange,
      minimumHours: job.minimumHours,
      benefits: List<String>.from(job.benefits),
      deadlineDate: job.deadlineDate,
      createdAt: job.createdAt,
      updatedAt: job.updatedAt,
      employerId: job.employerId,
    );
  }

  void _syncJobSeekerProfileControllers(JobSeekerProfile profile) {
    _profileFullNameController.text = profile.fullName;
    _profileEmailController.text = _resolvedJobSeekerEmail(profile);
    _profilePhoneController.text = _formatPhoneNumber(profile.phone);
    _profileCityController.text = profile.city;
    _profileStateController.text = profile.stateOrProvince;
    _profileCountryController.text = profile.country;
    _profileTotalFlightHoursController.text = profile.totalFlightHours > 0
        ? profile.totalFlightHours.toString()
        : '';
    _profileTypeRatingsController.text = profile.typeRatings.join(', ');
    _profileAircraftController.text = profile.aircraftFlown.join(', ');
  }

  Widget _buildProfileSummaryRow(String label, String value) {
    final hasValue = value.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              hasValue ? value : 'Not provided',
              style: TextStyle(
                fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
                color: hasValue ? null : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _summaryValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Not provided' : trimmed;
  }

  Widget _buildInlineInfoItem(IconData icon, String text) {
    final hasValue = text.trim().isNotEmpty;
    final displayText = hasValue ? text.trim() : 'Not provided';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.blueGrey.shade700),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            displayText,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
              color: hasValue ? Colors.blueGrey.shade900 : Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWebsiteSummaryRow(String url) {
    if (url.isEmpty) {
      return _buildProfileSummaryRow('Website', '');
    }

    final normalized =
        url.startsWith('http://') || url.startsWith('https://')
        ? url
        : 'https://$url';
    final uri = Uri.tryParse(normalized);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              'Website',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: uri == null
                  ? null
                  : () => launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      ),
              child: Text(
                url,
                style: const TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.blue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyLogoPreview(String logoUrl, {double size = 82}) {
    final normalized = _normalizeExternalUrl(logoUrl);
    final hasLogo = normalized.isNotEmpty;
    final logoBytes = _decodeDataImageUri(normalized);
    final isDataUri = logoBytes != null;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.grey.shade100,
      ),
      child: ClipOval(
        child: hasLogo
            ? (isDataUri
                  ? Image.memory(
                      logoBytes,
                      fit: BoxFit.cover,
                      errorBuilder: (context, _, _) => Icon(
                        Icons.business,
                        size: size * 0.45,
                        color: Colors.blueGrey.shade500,
                      ),
                    )
                  : Image.network(
                      normalized,
                      fit: BoxFit.cover,
                      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                      errorBuilder: (context, _, _) => Icon(
                        Icons.business,
                        size: size * 0.45,
                        color: Colors.blueGrey.shade500,
                      ),
                    ))
            : Icon(
                Icons.business,
                size: size * 0.45,
                color: Colors.blueGrey.shade500,
              ),
      ),
    );
  }

  Uint8List? _decodeDataImageUri(String value) {
    final trimmed = value.trim();
    if (!trimmed.toLowerCase().startsWith('data:image/')) {
      return null;
    }

    final commaIndex = trimmed.indexOf(',');
    if (commaIndex <= 0) {
      return null;
    }

    final metadata = trimmed.substring(0, commaIndex).toLowerCase();
    if (!metadata.contains(';base64')) {
      return null;
    }

    final encoded = trimmed.substring(commaIndex + 1);
    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  String _imageMimeTypeFromExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      default:
        return 'image/png';
    }
  }

  Future<String?> _uploadEmployerImageToBackend({
    required PlatformFile file,
    required String imageType,
  }) async {
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final extension = (file.extension ?? 'png').toLowerCase();
    final mime = _imageMimeTypeFromExtension(extension);

    if (!SupabaseBootstrap.isConfigured) {
      return 'data:$mime;base64,${base64Encode(bytes)}';
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      return null;
    }

    final sanitizedEmployerId = _currentEmployer.id.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    final objectPath =
        '$userId/$sanitizedEmployerId/$imageType/${DateTime.now().millisecondsSinceEpoch}.$extension';

    final bucket = Supabase.instance.client.storage.from('company-assets');
    await bucket.uploadBinary(
      objectPath,
      bytes,
      fileOptions: FileOptions(contentType: mime, upsert: false),
    );
    return bucket.getPublicUrl(objectPath);
  }

  String? _companyAssetObjectPathFromUrl(String imageUrl) {
    final normalized = _normalizeExternalUrl(imageUrl);
    if (normalized.isEmpty || normalized.startsWith('data:image/')) {
      return null;
    }

    Uri uri;
    try {
      uri = Uri.parse(normalized);
    } catch (_) {
      return null;
    }

    final segments = uri.pathSegments;
    if (segments.isEmpty) {
      return null;
    }

    final publicIndex = segments.indexOf('public');
    if (publicIndex < 0 || publicIndex + 1 >= segments.length) {
      return null;
    }
    if (segments[publicIndex + 1] != 'company-assets') {
      return null;
    }

    final objectSegments = segments.sublist(publicIndex + 2);
    if (objectSegments.isEmpty) {
      return null;
    }

    return objectSegments.map(Uri.decodeComponent).join('/');
  }

  Future<void> _deleteEmployerImageFromBackend(String imageUrl) async {
    if (!SupabaseBootstrap.isConfigured) {
      return;
    }

    final objectPath = _companyAssetObjectPathFromUrl(imageUrl);
    if (objectPath == null || objectPath.isEmpty) {
      return;
    }

    try {
      await Supabase.instance.client.storage.from('company-assets').remove([
        objectPath,
      ]);
    } catch (_) {
      // Best effort cleanup only.
    }
  }

  Future<void> _cleanupReplacedEmployerImages({
    required EmployerProfile previous,
    required EmployerProfile updated,
  }) async {
    final previousLogo = _normalizeExternalUrl(previous.companyLogoUrl);
    final updatedLogo = _normalizeExternalUrl(updated.companyLogoUrl);
    if (previousLogo.isNotEmpty && previousLogo != updatedLogo) {
      await _deleteEmployerImageFromBackend(previousLogo);
    }

    final previousBanner = _normalizeExternalUrl(previous.companyBannerUrl);
    final updatedBanner = _normalizeExternalUrl(updated.companyBannerUrl);
    if (previousBanner.isNotEmpty && previousBanner != updatedBanner) {
      await _deleteEmployerImageFromBackend(previousBanner);
    }
  }

  Future<PlatformFile?> _pickEmployerImageFile() async {
    if (kIsWeb) {
      final webImage = await pickWebImageFile();
      if (webImage == null) {
        return null;
      }
      return PlatformFile(
        name: webImage.name,
        size: webImage.bytes.length,
        bytes: webImage.bytes,
      );
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    return result.files.first;
  }

  Future<void> _pickEmployerLogoImageFile() async {
    if (_uploadingEmployerLogoImage) {
      return;
    }

    if (!_employerProfileEditing) {
      _startEditingEmployerProfile();
    }

    setState(() {
      _uploadingEmployerLogoImage = true;
    });

    try {
      final file = await _pickEmployerImageFile();
      if (!mounted || file == null) {
        return;
      }
      final uploadedUrl = await _uploadEmployerImageToBackend(
        file: file,
        imageType: 'logo',
      );
      if (!mounted || uploadedUrl == null || uploadedUrl.isEmpty) {
        return;
      }
      setState(() {
        _employerLogoUrlController.text = uploadedUrl;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logo image ready. Save changes to apply.'),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload logo image: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploadingEmployerLogoImage = false;
        });
      }
    }
  }

  Future<void> _pickEmployerBannerImageFile() async {
    if (_uploadingEmployerBannerImage) {
      return;
    }

    if (!_employerProfileEditing) {
      _startEditingEmployerProfile();
    }

    setState(() {
      _uploadingEmployerBannerImage = true;
    });

    try {
      final file = await _pickEmployerImageFile();
      if (!mounted || file == null) {
        return;
      }
      final uploadedUrl = await _uploadEmployerImageToBackend(
        file: file,
        imageType: 'banner',
      );
      if (!mounted || uploadedUrl == null || uploadedUrl.isEmpty) {
        return;
      }
      setState(() {
        _employerBannerUrlController.text = uploadedUrl;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Banner image ready. Save changes to apply.'),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload banner image: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploadingEmployerBannerImage = false;
        });
      }
    }
  }

  void _removeEmployerLogoImage() {
    if (!_employerProfileEditing || _uploadingEmployerLogoImage) {
      return;
    }

    setState(() {
      _employerLogoUrlController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logo removed. Save changes to apply.')),
    );
  }

  void _removeEmployerBannerImage() {
    if (!_employerProfileEditing || _uploadingEmployerBannerImage) {
      return;
    }

    setState(() {
      _employerBannerUrlController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Banner removed. Save changes to apply.')),
    );
  }

  Widget _buildCompanyBannerPreview(String bannerUrl, {double height = 120}) {
    final normalized = _normalizeExternalUrl(bannerUrl);
    final hasBanner = normalized.isNotEmpty;
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.blueGrey.shade50,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: hasBanner
            ? Image.network(
                normalized,
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                errorBuilder: (context, _, _) => Center(
                  child: Icon(
                    Icons.image_outlined,
                    size: 34,
                    color: Colors.blueGrey.shade500,
                  ),
                ),
              )
            : Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 34,
                  color: Colors.blueGrey.shade500,
                ),
              ),
      ),
    );
  }

  String _normalizeExternalUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    if (trimmed.toLowerCase().startsWith('data:image/')) {
      return trimmed;
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    return 'https://$trimmed';
  }

  EmployerProfile _normalizeEmployerImageUrls(EmployerProfile profile) {
    final normalizedBannerUrl = _normalizeExternalUrl(profile.companyBannerUrl);
    final normalizedLogoUrl = _normalizeExternalUrl(profile.companyLogoUrl);
    if (normalizedBannerUrl == profile.companyBannerUrl &&
        normalizedLogoUrl == profile.companyLogoUrl) {
      return profile;
    }

    return EmployerProfile(
      id: profile.id,
      companyName: profile.companyName,
      headquartersAddressLine1: profile.headquartersAddressLine1,
      headquartersAddressLine2: profile.headquartersAddressLine2,
      headquartersCity: profile.headquartersCity,
      headquartersState: profile.headquartersState,
      headquartersPostalCode: profile.headquartersPostalCode,
      headquartersCountry: profile.headquartersCountry,
      companyBannerUrl: normalizedBannerUrl,
      companyLogoUrl: normalizedLogoUrl,
      website: profile.website,
      contactName: profile.contactName,
      contactEmail: profile.contactEmail,
      contactPhone: profile.contactPhone,
      companyDescription: profile.companyDescription,
      companyBenefits: List<String>.from(profile.companyBenefits),
    );
  }

  Future<void> _openLocationInMaps(String locationQuery) async {
    final trimmed = locationQuery.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': trimmed,
    });
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open map for this location.')),
      );
    }
  }

  Widget _buildSummaryCountBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.blueGrey.shade700,
        ),
      ),
    );
  }

  Widget _buildSummarySectionCard({
    required String title,
    required Widget child,
    String? subtitle,
    IconData? icon,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Icon(icon, size: 18, color: Colors.blueGrey.shade700),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Future<void> _openEditPersonalInformation() async {
    final firstNameController = TextEditingController(
      text: _jobSeekerProfile.firstName,
    );
    final lastNameController = TextEditingController(
      text: _jobSeekerProfile.lastName,
    );
    final accountEmail = _resolvedJobSeekerEmail(_jobSeekerProfile);
    final phoneController = TextEditingController(
      text: _formatPhoneNumber(_jobSeekerProfile.phone),
    );
    final cityController = TextEditingController(text: _jobSeekerProfile.city);
    final stateController = TextEditingController(
      text: _jobSeekerProfile.stateOrProvince,
    );
    var selectedCountry =
        _normalizeCountryValue(_jobSeekerProfile.country) ?? 'USA';
    final countryController = TextEditingController(text: selectedCountry);

    final updatedProfile = await Navigator.of(context).push<JobSeekerProfile>(
      MaterialPageRoute(
        builder: (pageContext) {
          return StatefulBuilder(
            builder: (pageContext, setPageState) {
              Widget buildStateField() {
                return Autocomplete<String>(
                  key: ValueKey('personal-edit-state-$selectedCountry'),
                  initialValue: TextEditingValue(text: stateController.text),
                  optionsBuilder: (textEditingValue) {
                    final scopedOptions = _stateProvinceOptionsForCountry(
                      selectedCountry,
                    );
                    final query = textEditingValue.text.trim().toLowerCase();
                    if (query.isEmpty) {
                      return scopedOptions;
                    }

                    final exactAbbreviationMatches = _stateProvinceAbbreviations
                        .entries
                        .where(
                          (entry) =>
                              entry.value.toLowerCase() == query &&
                              scopedOptions.contains(entry.key),
                        )
                        .map((entry) => entry.key)
                        .toList();
                    if (exactAbbreviationMatches.isNotEmpty) {
                      return exactAbbreviationMatches;
                    }

                    return scopedOptions.where((option) {
                      final optionLower = option.toLowerCase();
                      final abbreviation =
                          (_stateProvinceAbbreviations[option] ?? '')
                              .toLowerCase();
                      final words = optionLower.split(RegExp(r'[\s-]+'));

                      return optionLower.startsWith(query) ||
                          words.any((word) => word.startsWith(query)) ||
                          abbreviation.startsWith(query);
                    });
                  },
                  onSelected: (selection) {
                    setPageState(() {
                      stateController.text = selection;
                    });
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    final optionList = options.toList(growable: false);
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 240,
                            minWidth: 280,
                          ),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: optionList.length,
                            itemBuilder: (context, index) {
                              final option = optionList[index];
                              return ListTile(
                                dense: true,
                                title: Text(_stateProvinceLabel(option)),
                                onTap: () => onSelected(option),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                  fieldViewBuilder:
                      (
                        context,
                        textEditingController,
                        focusNode,
                        onFieldSubmitted,
                      ) {
                        if (textEditingController.text !=
                            stateController.text) {
                          textEditingController.value = TextEditingValue(
                            text: stateController.text,
                            selection: TextSelection.collapsed(
                              offset: stateController.text.length,
                            ),
                          );
                        }
                        return TextField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          decoration: const InputDecoration(
                            labelText: 'State / Province',
                          ),
                          onChanged: (value) {
                            setPageState(() {
                              stateController.text = value.trim();
                            });
                          },
                        );
                      },
                );
              }

              void saveProfile() {
                final firstName = firstNameController.text.trim();
                final lastName = lastNameController.text.trim();
                final updated = _jobSeekerProfile.copyWith(
                  firstName: firstName,
                  lastName: lastName,
                  fullName: JobSeekerProfile.combineName(firstName, lastName),
                  email: accountEmail,
                  phone: _formatPhoneNumber(phoneController.text.trim()),
                  city: cityController.text.trim(),
                  stateOrProvince: stateController.text.trim(),
                  country: countryController.text.trim(),
                );
                Navigator.of(pageContext).pop(updated);
              }

              bool hasPersonalChanges() {
                return firstNameController.text.trim() !=
                    _jobSeekerProfile.firstName ||
                  lastNameController.text.trim() !=
                    _jobSeekerProfile.lastName ||
                    _phoneDigits(phoneController.text) !=
                        _phoneDigits(_jobSeekerProfile.phone) ||
                    cityController.text.trim() != _jobSeekerProfile.city ||
                    stateController.text.trim() !=
                        _jobSeekerProfile.stateOrProvince ||
                    countryController.text.trim() != _jobSeekerProfile.country;
              }

              final canSave = hasPersonalChanges();

              return Scaffold(
                appBar: AppBar(title: const Text('Edit Personal Information')),
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummarySectionCard(
                          title: 'Contact Information',
                          subtitle: 'Basic details used for applications.',
                          icon: Icons.person_outline,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: firstNameController,
                                      onChanged: (_) => setPageState(() {}),
                                      decoration: const InputDecoration(
                                        labelText: 'First Name',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: lastNameController,
                                      onChanged: (_) => setPageState(() {}),
                                      decoration: const InputDecoration(
                                        labelText: 'Last Name',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  helperText:
                                      'Uses the email from your signed-in account',
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    accountEmail.isEmpty
                                        ? 'Not available'
                                        : accountEmail,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: phoneController,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  _PhoneNumberTextInputFormatter(),
                                ],
                                onChanged: (_) => setPageState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'Phone',
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildSummarySectionCard(
                          title: 'Location',
                          subtitle:
                              'Keep your city, state/province, and country current.',
                          icon: Icons.place_outlined,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: cityController,
                                      onChanged: (_) => setPageState(() {}),
                                      decoration: const InputDecoration(
                                        labelText: 'City',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: buildStateField()),
                                ],
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: selectedCountry,
                                decoration: const InputDecoration(
                                  labelText: 'Country',
                                ),
                                items: _countryOptions
                                    .map(
                                      (country) => DropdownMenuItem(
                                        value: country,
                                        child: Text(country),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setPageState(() {
                                    selectedCountry = value;
                                    countryController.text = value;
                                    final allowed =
                                        _stateProvinceOptionsForCountry(value);
                                    if (!allowed.contains(
                                      stateController.text,
                                    )) {
                                      stateController.clear();
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
                bottomNavigationBar: SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    decoration: BoxDecoration(
                      color: Theme.of(pageContext).scaffoldBackgroundColor,
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(pageContext).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: canSave ? saveProfile : null,
                            child: const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );

    firstNameController.dispose();
    lastNameController.dispose();
    phoneController.dispose();
    cityController.dispose();
    stateController.dispose();
    countryController.dispose();

    if (updatedProfile == null || !mounted) {
      return;
    }

    setState(() {
      _jobSeekerProfile = updatedProfile;
    });
    _syncJobSeekerProfileControllers(updatedProfile);
    await _saveJobSeekerProfile();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Personal information saved.')),
    );
  }

  List<String> _splitCommaSeparatedValues(String value) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  List<String> _selectedJobSeekerRatings(JobSeekerProfile profile) {
    const allRatings = [
      'Multi-Engine Land',
      'Single-Engine Land',
      'Multi-Engine Sea',
      'Single-Engine Sea',
      'Tailwheel Endorsement',
      'Rotorcraft',
      'Gyroplane',
      'Glider',
      'Lighter-than-Air',
    ];
    return allRatings
        .where((rating) => profile.faaCertificates.contains(rating))
        .toList();
  }

  List<String> _selectedJobSeekerCertificates(JobSeekerProfile profile) {
    final hasAtp = profile.faaCertificates.contains(
      'Airline Transport Pilot (ATP)',
    );
    final hasCpl = profile.faaCertificates.contains('Commercial Pilot (CPL)');

    final visibleCertificates = _availableFaaCertificates.where((cert) {
      if (hasAtp) {
        return cert != 'Commercial Pilot (CPL)' &&
            cert != 'Instrument Rating (IFR)' &&
            cert != 'Private Pilot (PPL)';
      }
      if (hasCpl) {
        return cert != 'Private Pilot (PPL)';
      }
      return true;
    });

    return visibleCertificates
        .where((cert) => profile.faaCertificates.contains(cert))
        .toList();
  }

  List<String> _hoursSummaryItems({
    required List<String> options,
    required List<String> selectedTypes,
    required Map<String, int> hours,
  }) {
    return options.where((option) => selectedTypes.contains(option)).map((
      option,
    ) {
      final value = hours[option] ?? 0;
      return value > 0 ? '$option: $value' : option;
    }).toList();
  }

  Widget _buildChipSummaryCard({
    required String title,
    required List<String> items,
    String emptyText = 'None added',
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _buildSummaryCountBadge(items.length),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(
              emptyText,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade600,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items
                  .map(
                    (item) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.blueGrey.shade100),
                      ),
                      child: Text(item),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  String _previewSelectionSummary({
    required List<String> items,
    required String emptyLabel,
    int maxItems = 2,
  }) {
    if (items.isEmpty) {
      return emptyLabel;
    }

    final uniqueItems = items.toSet().toList();
    if (uniqueItems.length <= maxItems) {
      return uniqueItems.join(', ');
    }

    final preview = uniqueItems.take(maxItems).join(', ');
    final remaining = uniqueItems.length - maxItems;
    return '$preview +$remaining more';
  }

  String _hoursRequirementSummary() {
    final flightCount = _selectedFlightHours.length;
    final instructorCount = _selectedInstructorHours.length;
    final specialtyCount = _selectedSpecialtyHours.length;
    final totalCount = flightCount + instructorCount + specialtyCount;

    if (totalCount == 0) {
      return 'Add only the hour categories required for the job.';
    }

    final segments = <String>[];
    if (flightCount > 0) {
      segments.add('Flight $flightCount');
    }
    if (instructorCount > 0) {
      segments.add('Instructor $instructorCount');
    }
    if (specialtyCount > 0) {
      segments.add('Specialty $specialtyCount');
    }

    final totalHours = [
      ..._selectedFlightHours.values,
      ..._selectedInstructorHours.values,
      ..._selectedSpecialtyHours.values,
    ].fold<int>(0, (sum, value) => sum + value);

    if (totalHours > 0) {
      segments.add('${totalHours.toString()} min hrs');
    }

    return segments.join(' • ');
  }

  Widget _buildCreateStepPill({
    required int step,
    required String title,
    required bool isActive,
    required bool isComplete,
  }) {
    final backgroundColor = isActive
        ? Colors.blueGrey.shade700
        : isComplete
        ? Colors.blueGrey.shade100
        : Colors.grey.shade100;
    final foregroundColor = isActive
        ? Colors.white
        : isComplete
        ? Colors.blueGrey.shade800
        : Colors.grey.shade700;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? Colors.blueGrey.shade700 : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive ? Colors.white24 : Colors.white,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${step + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.white : foregroundColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateStepHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildCreateStepPill(
              step: 0,
              title: 'Basics',
              isActive: _createJobStep == 0,
              isComplete: _createJobStep > 0,
            ),
            const SizedBox(width: 10),
            _buildCreateStepPill(
              step: 1,
              title: 'Qualifications',
              isActive: _createJobStep == 1,
              isComplete: false,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _createJobStep == 0
              ? 'Step 1 of 2: enter the core job details first.'
              : 'Step 2 of 2: set certificates, hours, and other qualifications.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
      ],
    );
  }

  Widget _buildCreateBasicsStep() {
    if (_profileType == ProfileType.employer &&
        _createCompanyController.text != _currentEmployer.companyName) {
      _createCompanyController.text = _currentEmployer.companyName;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _createTitleController,
          focusNode: _createTitleFocusNode,
          decoration: const InputDecoration(labelText: 'Title *'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _createCompanyController,
          readOnly: true,
          enableInteractiveSelection: false,
          decoration: const InputDecoration(
            labelText: 'Company',
            helperText: 'Auto-filled from your active employer profile',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Job Location',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              RadioGroup<bool>(
                groupValue: _useCompanyLocationForJob,
                onChanged: (value) {
                  setState(() {
                    _useCompanyLocationForJob = value ?? true;
                  });
                },
                child: const Column(
                  children: [
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Same as Company'),
                      value: true,
                    ),
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Custom'),
                      value: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (_useCompanyLocationForJob)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 18,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _buildCompanyLocationString(),
                          style: const TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                TextField(
                  controller: _createLocationController,
                  decoration: const InputDecoration(
                    hintText: 'Enter job location',
                    isDense: true,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const ValueKey('create-employment-type'),
          initialValue: _availableJobTypes.contains(_createTypeController.text)
              ? _createTypeController.text
              : null,
          hint: const Text('Select Employment Type'),
          decoration: const InputDecoration(labelText: 'Employment Type'),
          items: _availableJobTypes
              .map(
                (type) =>
                    DropdownMenuItem<String>(value: type, child: Text(type)),
              )
              .toList(),
          onChanged: (value) {
            setState(() {
              _createTypeController.text = value ?? '';
            });
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const ValueKey('create-position-selection'),
          initialValue: _selectedCreatePositionOption,
          hint: const Text('Select Position'),
          decoration: const InputDecoration(labelText: 'Position Selection *'),
          items: const [
            DropdownMenuItem(
              value: 'Single Pilot',
              child: Text('Single Pilot'),
            ),
            DropdownMenuItem(
              value: 'Crew Member: Captain',
              child: Text('Crew Member: Captain'),
            ),
            DropdownMenuItem(
              value: 'Crew Member: Co-Pilot',
              child: Text('Crew Member: Co-Pilot'),
            ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }

            setState(() {
              _selectedCreatePositionOption = value;
              if (value == 'Single Pilot') {
                _selectedCrewRole = 'Single Pilot';
                _selectedCrewPosition = 'Captain';
              } else if (value == 'Crew Member: Co-Pilot') {
                _selectedCrewRole = 'Crew';
                _selectedCrewPosition = 'Co-Pilot';
              } else {
                _selectedCrewRole = 'Crew';
                _selectedCrewPosition = 'Captain';
              }
            });
          },
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Salary Range',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('create-starting-pay'),
                      controller: _createStartingPayController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Starting Pay *',
                        prefixText: r'$',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('create-pay-for-experience'),
                      controller: _createPayForExperienceController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Top End Starting Pay (Optional)',
                        prefixText: r'$',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const ValueKey('create-pay-rate-metric'),
                initialValue: _selectedCreatePayRateMetric,
                hint: const Text('Select pay metric'),
                decoration: const InputDecoration(
                  labelText: 'Pay Metric *',
                  isDense: true,
                ),
                items: _availablePayRateMetrics
                    .map(
                      (metric) => DropdownMenuItem<String>(
                        value: metric,
                        child: Text(metric),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCreatePayRateMetric = value;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('create-description'),
          controller: _createDescriptionController,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Description *'),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Application Timeline',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              RadioGroup<bool>(
                groupValue: _createOpenListing,
                onChanged: (value) {
                  setState(() {
                    _createOpenListing = value ?? true;
                    if (_createOpenListing) {
                      _createDeadlineDate = null;
                    }
                  });
                },
                child: const Column(
                  children: [
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Open Listing (No Deadline)'),
                      value: true,
                    ),
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Set Application Deadline'),
                      value: false,
                    ),
                  ],
                ),
              ),
              if (!_createOpenListing)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final initialDate =
                          _createDeadlineDate ??
                          DateTime.now().add(const Duration(days: 30));
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: initialDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (pickedDate == null || !mounted) {
                        return;
                      }
                      setState(() {
                        _createDeadlineDate = pickedDate;
                      });
                    },
                    icon: const Icon(Icons.event),
                    label: Text(
                      _createDeadlineDate == null
                          ? 'Choose deadline date'
                          : 'Application Deadline: ${_formatYmd(_createDeadlineDate!)}',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpandableRequirementSection({
    required String sectionKey,
    required String title,
    required String summary,
    required Widget child,
    int? count,
    bool initiallyExpanded = false,
  }) {
    final useAccordion = MediaQuery.sizeOf(context).width < 700;
    final isExpanded = useAccordion
        ? _expandedCreateRequirementsSection == sectionKey
        : initiallyExpanded;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('create-section-$sectionKey-$isExpanded'),
          initiallyExpanded: isExpanded,
          maintainState: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          onExpansionChanged: (expanded) {
            if (!useAccordion) {
              return;
            }
            setState(() {
              _expandedCreateRequirementsSection = expanded ? sectionKey : null;
            });
          },
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (count != null) _buildSummaryCountBadge(count),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(summary),
          ),
          children: [child],
        ),
      ),
    );
  }

  List<String> _applyFaaCertificateHierarchy(List<String> certs) {
    final updated = List<String>.from(certs);
    final hasAtp = updated.contains('Airline Transport Pilot (ATP)');
    final hasCpl = updated.contains('Commercial Pilot (CPL)');

    if (hasAtp) {
      updated.removeWhere(
        (cert) =>
            cert == 'Commercial Pilot (CPL)' ||
            cert == 'Instrument Rating (IFR)' ||
            cert == 'Private Pilot (PPL)',
      );
    } else if (hasCpl) {
      updated.remove('Private Pilot (PPL)');
    }

    return updated;
  }

  bool _sameStringSet(
    Iterable<String> left,
    Iterable<String> right, {
    bool trim = false,
  }) {
    final leftSet = (trim ? left.map((item) => item.trim()) : left).toSet();
    final rightSet = (trim ? right.map((item) => item.trim()) : right).toSet();
    return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
  }

  bool _sameIntMap(Map<String, int> left, Map<String, int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  Widget _buildCheckboxCard({
    required Iterable<String> options,
    required bool Function(String option) isSelected,
    required void Function(String option, bool selected) onChanged,
    EdgeInsetsGeometry margin = const EdgeInsets.symmetric(vertical: 4),
    EdgeInsetsGeometry padding = const EdgeInsets.all(10),
    bool dense = false,
    EdgeInsetsGeometry? contentPadding,
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: options.map((option) {
          return CheckboxListTile(
            dense: dense,
            contentPadding: contentPadding,
            title: Text(option),
            value: isSelected(option),
            onChanged: (bool? selected) {
              onChanged(option, selected == true);
            },
          );
        }).toList(),
      ),
    );
  }

  Future<void> _openEditQualifications() async {
    var draftProfile = _jobSeekerProfile;
    String? expandedQualificationsSection = 'Certificates';
    final typeRatingsController = TextEditingController(
      text: draftProfile.typeRatings.join(', '),
    );
    final aircraftController = TextEditingController(
      text: draftProfile.aircraftFlown.join(', '),
    );

    final updatedProfile = await Navigator.of(context).push<JobSeekerProfile>(
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, setPageState) {
            const landRatings = ['Multi-Engine Land', 'Single-Engine Land'];
            const seaRatings = ['Multi-Engine Sea', 'Single-Engine Sea'];
            const tailwheelRating = ['Tailwheel Endorsement'];
            const rotorRatings = ['Rotorcraft', 'Gyroplane'];
            const otherRatings = ['Glider', 'Lighter-than-Air'];

            final hasAtp = draftProfile.faaCertificates.contains(
              'Airline Transport Pilot (ATP)',
            );
            final hasCpl = draftProfile.faaCertificates.contains(
              'Commercial Pilot (CPL)',
            );
            final visibleFaaCertificates = _availableFaaCertificates.where((
              cert,
            ) {
              if (hasAtp) {
                return cert != 'Commercial Pilot (CPL)' &&
                    cert != 'Instrument Rating (IFR)' &&
                    cert != 'Private Pilot (PPL)';
              }
              if (hasCpl) {
                return cert != 'Private Pilot (PPL)';
              }
              return true;
            }).toList();

            Widget ratingGroup(List<String> group) => _buildCheckboxCard(
              options: group,
              isSelected: (rating) =>
                  draftProfile.faaCertificates.contains(rating),
              onChanged: (rating, selected) {
                setPageState(() {
                  final newCerts = List<String>.from(
                    draftProfile.faaCertificates,
                  );
                  if (selected) {
                    newCerts.add(rating);
                  } else {
                    newCerts.remove(rating);
                  }
                  draftProfile = draftProfile.copyWith(
                    faaCertificates: newCerts,
                  );
                });
              },
            );

            Widget hoursSection({
              required String title,
              required List<String> options,
              required String keyPrefix,
            }) {
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ...options.map((exp) {
                      final isSelected = draftProfile.flightHoursTypes.contains(
                        exp,
                      );
                      final experienceHours =
                          draftProfile.flightHours[exp] ?? 0;
                      return Column(
                        children: [
                          CheckboxListTile(
                            title: Text(exp),
                            value: isSelected,
                            onChanged: (bool? value) {
                              setPageState(() {
                                final newExp = List<String>.from(
                                  draftProfile.flightHoursTypes,
                                );
                                final newHours = Map<String, int>.from(
                                  draftProfile.flightHours,
                                );
                                if (value == true) {
                                  newExp.add(exp);
                                } else {
                                  newExp.remove(exp);
                                  newHours.remove(exp);
                                }
                                draftProfile = draftProfile.copyWith(
                                  flightHours: newHours,
                                  flightHoursTypes: newExp,
                                );
                              });
                            },
                          ),
                          if (isSelected)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 16,
                                right: 16,
                                bottom: 8,
                              ),
                              child: TextFormField(
                                key: ValueKey('$keyPrefix-$exp'),
                                keyboardType: TextInputType.number,
                                initialValue: experienceHours > 0
                                    ? experienceHours.toString()
                                    : '',
                                decoration: InputDecoration(
                                  labelText: 'Hours for $exp',
                                  hintText: '0',
                                  isDense: true,
                                ),
                                onChanged: (value) {
                                  final hours = int.tryParse(value) ?? 0;
                                  setPageState(() {
                                    final newHours = Map<String, int>.from(
                                      draftProfile.flightHours,
                                    );
                                    newHours[exp] = hours;
                                    draftProfile = draftProfile.copyWith(
                                      flightHours: newHours,
                                    );
                                  });
                                },
                              ),
                            ),
                        ],
                      );
                    }),
                  ],
                ),
              );
            }

            Widget specialtyHoursSection() {
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: _availableSpecialtyExperience.map((exp) {
                    final isSelected = draftProfile.specialtyFlightHours
                        .contains(exp);
                    final specialtyHours =
                        draftProfile.specialtyFlightHoursMap[exp] ?? 0;
                    return Column(
                      children: [
                        CheckboxListTile(
                          title: Text(exp),
                          value: isSelected,
                          onChanged: (bool? value) {
                            setPageState(() {
                              final newExp = List<String>.from(
                                draftProfile.specialtyFlightHours,
                              );
                              final newHours = Map<String, int>.from(
                                draftProfile.specialtyFlightHoursMap,
                              );
                              if (value == true) {
                                newExp.add(exp);
                              } else {
                                newExp.remove(exp);
                                newHours.remove(exp);
                              }
                              draftProfile = draftProfile.copyWith(
                                specialtyFlightHours: newExp,
                                specialtyFlightHoursMap: newHours,
                              );
                            });
                          },
                        ),
                        if (isSelected)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 16,
                              right: 16,
                              bottom: 8,
                            ),
                            child: TextFormField(
                              key: ValueKey('specialty-hours-$exp'),
                              keyboardType: TextInputType.number,
                              initialValue: specialtyHours > 0
                                  ? specialtyHours.toString()
                                  : '',
                              decoration: InputDecoration(
                                labelText: 'Hours for $exp',
                                hintText: '0',
                                isDense: true,
                              ),
                              onChanged: (value) {
                                final hours = int.tryParse(value) ?? 0;
                                setPageState(() {
                                  final newHours = Map<String, int>.from(
                                    draftProfile.specialtyFlightHoursMap,
                                  );
                                  newHours[exp] = hours;
                                  draftProfile = draftProfile.copyWith(
                                    specialtyFlightHoursMap: newHours,
                                  );
                                });
                              },
                            ),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              );
            }

            final useAccordion = MediaQuery.sizeOf(pageContext).width < 700;

            Widget qualificationSection({
              required String sectionKey,
              required String title,
              required String subtitle,
              required IconData icon,
              required Widget child,
            }) {
              if (!useAccordion) {
                return _buildSummarySectionCard(
                  title: title,
                  subtitle: subtitle,
                  icon: icon,
                  child: child,
                );
              }

              final isExpanded = expandedQualificationsSection == sectionKey;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Theme(
                  data: Theme.of(
                    pageContext,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    key: ValueKey('job-seeker-section-$sectionKey-$isExpanded'),
                    initiallyExpanded: isExpanded,
                    maintainState: true,
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    onExpansionChanged: (expanded) {
                      setPageState(() {
                        expandedQualificationsSection = expanded
                            ? sectionKey
                            : null;
                      });
                    },
                    title: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(subtitle),
                    ),
                    children: [child],
                  ),
                ),
              );
            }

            void saveProfile() {
              Navigator.of(pageContext).pop(draftProfile);
            }

            bool hasQualificationsChanges() {
              return !_sameStringSet(
                    draftProfile.faaCertificates,
                    _jobSeekerProfile.faaCertificates,
                  ) ||
                  !_sameStringSet(
                    draftProfile.typeRatings,
                    _jobSeekerProfile.typeRatings,
                  ) ||
                  !_sameStringSet(
                    draftProfile.flightHoursTypes,
                    _jobSeekerProfile.flightHoursTypes,
                  ) ||
                  !_sameIntMap(
                    draftProfile.flightHours,
                    _jobSeekerProfile.flightHours,
                  ) ||
                  !_sameStringSet(
                    draftProfile.specialtyFlightHours,
                    _jobSeekerProfile.specialtyFlightHours,
                  ) ||
                  !_sameIntMap(
                    draftProfile.specialtyFlightHoursMap,
                    _jobSeekerProfile.specialtyFlightHoursMap,
                  ) ||
                  !_sameStringSet(
                    draftProfile.aircraftFlown,
                    _jobSeekerProfile.aircraftFlown,
                  );
            }

            final canSave = hasQualificationsChanges();

            return Scaffold(
              appBar: AppBar(title: const Text('Edit Qualifications')),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      qualificationSection(
                        sectionKey: 'Certificates',
                        title: 'Certificates',
                        subtitle:
                            'Select FAA and instructor credentials you hold.',
                        icon: Icons.badge_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'FAA Certificates',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            _buildCheckboxCard(
                              options: visibleFaaCertificates,
                              isSelected: (cert) =>
                                  draftProfile.faaCertificates.contains(cert),
                              onChanged: (cert, selected) {
                                setPageState(() {
                                  final newCerts = List<String>.from(
                                    draftProfile.faaCertificates,
                                  );
                                  if (selected) {
                                    newCerts.add(cert);
                                  } else {
                                    newCerts.remove(cert);
                                  }
                                  draftProfile = draftProfile.copyWith(
                                    faaCertificates:
                                        _applyFaaCertificateHierarchy(newCerts),
                                  );
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Instructor Certificates',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            _buildCheckboxCard(
                              options: _availableInstructorCertificates,
                              isSelected: (cert) =>
                                  draftProfile.faaCertificates.contains(cert),
                              onChanged: (cert, selected) {
                                setPageState(() {
                                  final newCerts = List<String>.from(
                                    draftProfile.faaCertificates,
                                  );
                                  if (selected) {
                                    newCerts.add(cert);
                                  } else {
                                    newCerts.remove(cert);
                                  }
                                  draftProfile = draftProfile.copyWith(
                                    faaCertificates: newCerts,
                                  );
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      qualificationSection(
                        sectionKey: 'Ratings',
                        title: 'Ratings',
                        subtitle: 'Add airframe/rating details for matching.',
                        icon: Icons.tune_outlined,
                        child: Column(
                          children: [
                            ratingGroup(landRatings),
                            ratingGroup(seaRatings),
                            ratingGroup(tailwheelRating),
                            ratingGroup(rotorRatings),
                            ratingGroup(otherRatings),
                          ],
                        ),
                      ),
                      qualificationSection(
                        sectionKey: 'HoursAndSpecialty',
                        title: 'Hours and Specialty Experience',
                        subtitle:
                            'Select categories and add your logged hours.',
                        icon: Icons.schedule_outlined,
                        child: Column(
                          children: [
                            hoursSection(
                              title: 'Flight Hours',
                              options: _availableEmployerFlightHours,
                              keyPrefix: 'flight-experience-hours',
                            ),
                            const SizedBox(height: 10),
                            hoursSection(
                              title: 'Instructor Hours',
                              options: _availableInstructorHours,
                              keyPrefix: 'instructor-hours',
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Specialty Flight Hours',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            specialtyHoursSection(),
                          ],
                        ),
                      ),
                      qualificationSection(
                        sectionKey: 'Aircraft',
                        title: 'Aircraft (Coming Soon)',
                        subtitle: 'Aircraft you have flown (comma-separated).',
                        icon: Icons.flight_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: aircraftController,
                              decoration: const InputDecoration(
                                labelText: 'Aircraft you have flown',
                                hintText: 'Cessna 172, Boeing 737',
                                helperText: 'Comma-separated list',
                              ),
                              onChanged: (value) {
                                setPageState(() {
                                  draftProfile = draftProfile.copyWith(
                                    aircraftFlown: _splitCommaSeparatedValues(
                                      value,
                                    ),
                                  );
                                });
                              },
                            ),
                            if (draftProfile.aircraftFlown.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: draftProfile.aircraftFlown
                                    .map(
                                      (aircraft) => Chip(label: Text(aircraft)),
                                    )
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      qualificationSection(
                        sectionKey: 'TypeRatings',
                        title: 'Type Ratings (Coming Soon)',
                        subtitle: 'Comma-separated aircraft type ratings.',
                        icon: Icons.confirmation_number_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: typeRatingsController,
                              decoration: const InputDecoration(
                                labelText: 'Type ratings you hold',
                                hintText: 'Boeing 737, Embraer E-175',
                                helperText: 'Comma-separated list',
                              ),
                              onChanged: (value) {
                                setPageState(() {
                                  draftProfile = draftProfile.copyWith(
                                    typeRatings: _splitCommaSeparatedValues(
                                      value,
                                    ),
                                  );
                                });
                              },
                            ),
                            if (draftProfile.typeRatings.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: draftProfile.typeRatings
                                    .map((rating) => Chip(label: Text(rating)))
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              bottomNavigationBar: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  decoration: BoxDecoration(
                    color: Theme.of(pageContext).scaffoldBackgroundColor,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(pageContext).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: canSave ? saveProfile : null,
                          child: const Text('Save Changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    typeRatingsController.dispose();
    aircraftController.dispose();

    if (updatedProfile == null || !mounted) {
      return;
    }

    setState(() {
      _jobSeekerProfile = updatedProfile;
    });
    _syncJobSeekerProfileControllers(updatedProfile);
    await _saveJobSeekerProfile();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Qualifications saved.')));
  }

  Future<void> _loadEmployerProfiles() async {
    final data = await _appRepository.loadEmployerProfiles();
    if (!mounted) {
      return;
    }

    final normalizedProfiles = data.profiles
        .map(_normalizeEmployerImageUrls)
        .toList();

    setState(() {
      _employerProfiles = normalizedProfiles;
      if (_employerProfiles.isNotEmpty) {
        _currentEmployer = _employerProfiles.firstWhere(
          (profile) => profile.id == data.currentEmployerId,
          orElse: () => _employerProfiles.first,
        );
      }
      // Pre-fill the create-form company field from the loaded profile.
      _createCompanyController.text = _currentEmployer.companyName;
    });
    _loadEmployerApplications();
  }

  Future<void> _saveEmployerProfiles() async {
    await _appRepository.saveEmployerProfiles(
      EmployerProfilesData(
        profiles: _employerProfiles,
        currentEmployerId: _currentEmployer.id,
      ),
    );
  }

  Future<void> _loadJobTemplates() async {
    final templates = await _appRepository.loadJobTemplates();
    if (!mounted) {
      return;
    }

    setState(() {
      _jobTemplates = templates;
      if (_selectedTemplateId != null &&
          !_jobTemplates.any(
            (template) => template.id == _selectedTemplateId,
          )) {
        _selectedTemplateId = null;
      }
      if (_editingTemplateId != null &&
          !_jobTemplates.any((template) => template.id == _editingTemplateId)) {
        _editingTemplateId = null;
      }
    });
  }

  Future<void> _saveJobTemplates() async {
    await _appRepository.saveJobTemplates(_jobTemplates);
  }

  void _switchEmployer(EmployerProfile employer) {
    final normalizedEmployer = _normalizeEmployerImageUrls(employer);
    setState(() {
      _currentEmployer = normalizedEmployer;
      _employerProfileEditing = false;
      _selectedTemplateId = null;
      _editingTemplateId = null;
      // Keep the create-form company field in sync when switching employer.
      _createCompanyController.text = normalizedEmployer.companyName;
    });
    _loadEmployerApplications();
    _saveEmployerProfiles();
  }

  void _updateEmployer(EmployerProfile updated) {
    setState(() {
      final index = _employerProfiles.indexWhere((p) => p.id == updated.id);
      if (index >= 0) {
        _employerProfiles[index] = updated;
      }
      if (_currentEmployer.id == updated.id) {
        _currentEmployer = updated;
      }
      _employerProfileEditing = false;
      // Keep the create-form company field in sync after saving.
      _createCompanyController.text = updated.companyName;
    });
    _saveEmployerProfiles();
  }

  // Copies the current employer values into the edit controllers and enters
  // edit mode for the Company Profile tab.
  void _startEditingEmployerProfile() {
    _employerCompanyNameController.text = _currentEmployer.companyName;
    _employerAddressLine1Controller.text =
        _currentEmployer.headquartersAddressLine1;
    _employerAddressLine2Controller.text =
        _currentEmployer.headquartersAddressLine2;
    _employerCityController.text = _currentEmployer.headquartersCity;
    _employerStateController.text = _currentEmployer.headquartersState;
    _employerPostalCodeController.text =
        _currentEmployer.headquartersPostalCode;
    _employerCountryController.text = _currentEmployer.headquartersCountry;
    _employerBannerUrlController.text = _currentEmployer.companyBannerUrl;
    _employerLogoUrlController.text = _currentEmployer.companyLogoUrl;
    _employerWebsiteController.text = _currentEmployer.website;
    _employerContactNameController.text = _currentEmployer.contactName;
    _employerContactEmailController.text = _currentEmployer.contactEmail;
    _employerContactPhoneController.text = _formatPhoneNumber(
      _currentEmployer.contactPhone,
    );
    _employerDescriptionController.text = _currentEmployer.companyDescription;
    _selectedEmployerBenefits
      ..clear()
      ..addAll(_currentEmployer.companyBenefits);
    setState(() => _employerProfileEditing = true);
  }

  _MatchResult _evaluateJobMatch(JobListing job) {
    return _evaluateJobMatchForProfile(
      job: job,
      profile: _jobSeekerProfile,
      includeCertPrefix: true,
    );
  }

  Future<void> _fetchJobs() async {
    setState(() {
      _loading = true;
      _loadingError = null;
    });

    final result = await _appRepository.loadJobs(
      backendUrl: _backendUrl,
      fallbackJobs: _fallbackJobs,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _allJobs = result.jobs.map(_canonicalizeJobListing).toList();
      _loadingError = result.warningMessage;
      _page = 1;
      _loading = false;
    });
  }

  List<JobListing> get _fallbackJobs => [
    JobListing(
      id: '1',
      title: 'Commercial Pilot',
      company: 'SkyHigh Airlines',
      location: 'Dallas, TX',
      type: 'Full-Time',
      crewRole: 'Crew',
      crewPosition: 'Captain',
      faaRules: ['Part 121'],
      description:
          'Operate commercial aircraft for passenger and cargo flights. Responsible for pre-flight planning, safe operation, and passenger safety.',
      faaCertificates: ['Commercial Pilot', 'Instrument Rating'],
      typeRatingsRequired: const ['Boeing 737'],
      flightExperience: ['PIC Jet', 'PIC Turbine'],
      flightHours: const {'PIC Jet': 900, 'PIC Turbine': 1100},
      preferredFlightHours: const ['SIC Jet'],
      specialtyExperience: ['Low Altitude'],
      specialtyHours: const {'Low Altitude': 75},
      aircraftFlown: ['Cessna "Caravan" 208', 'Piper Cherokee'],
      salaryRange: '\$75K - \$120K',
      benefits: ['Health Insurance', '401k', 'Dental', 'Vision'],
      deadlineDate: DateTime.now().add(const Duration(days: 30)),
    ),
    JobListing(
      id: '2',
      title: 'Aviation Maintenance Technician',
      company: 'AeroTech Services',
      location: 'Atlanta, GA',
      type: 'Full-Time',
      crewRole: 'Single Pilot',
      crewPosition: null,
      faaRules: ['Part 91'],
      description:
          'Perform maintenance, repair, and inspection of aircraft systems. Ensure airworthiness and compliance with FAA regulations.',
      faaCertificates: ['Airframe & Powerplant (A&P)'],
      typeRatingsRequired: const [],
      flightExperience: [],
      flightHours: const {},
      preferredFlightHours: const [],
      specialtyExperience: const [],
      specialtyHours: const {},
      aircraftFlown: ['Cessna 172', 'Beechcraft Bonanza'],
      salaryRange: '\$50K - \$75K',
      benefits: ['Health Insurance', 'Dental', 'Paid Time Off'],
      deadlineDate: DateTime.now().add(const Duration(days: 45)),
    ),
    JobListing(
      id: '3',
      title: 'Flight Instructor',
      company: 'Freedom Aviation Academy',
      location: 'Phoenix, AZ',
      type: 'Part-Time',
      crewRole: 'Single Pilot',
      crewPosition: null,
      faaRules: ['Part 91'],
      description:
          'Teach student pilots fundamental flying skills, safety procedures, and FAA knowledge. Conduct flight training in various aircraft.',
      faaCertificates: ['Commercial Pilot', 'Flight Instructor'],
      typeRatingsRequired: const [],
      flightExperience: ['PIC', 'Instruction', 'Multi-engine'],
      flightHours: const {'PIC': 500, 'Instruction': 250, 'Multi-engine': 150},
      preferredFlightHours: const ['SIC'],
      specialtyExperience: ['Tailwheel'],
      specialtyHours: const {'Tailwheel': 50},
      aircraftFlown: ['Cessna 172', 'PA-18 "Super Cub"', 'Piper Cherokee'],
      salaryRange: '\$35K - \$55K',
      benefits: ['Flexible Schedule', 'Flight Discounts'],
      deadlineDate: DateTime.now().add(const Duration(days: 20)),
    ),
    JobListing(
      id: '4',
      title: 'Aircraft Dispatcher',
      company: 'Global Air Logistics',
      location: 'Chicago, IL',
      type: 'Full-Time',
      crewRole: 'Crew',
      crewPosition: 'Co-Pilot',
      faaRules: ['Part 121'],
      description:
          'Coordinate flight operations, weather analysis, and flight planning. Ensure safe and efficient aircraft dispatch.',
      faaCertificates: [],
      typeRatingsRequired: const ['Embraer E-175'],
      flightExperience: ['SIC Jet', 'SIC Turbine'],
      flightHours: const {'SIC Jet': 700, 'SIC Turbine': 500},
      preferredFlightHours: const ['PIC'],
      specialtyExperience: ['Aerial Survey'],
      specialtyHours: const {'Aerial Survey': 80},
      aircraftFlown: ['Cessna "Caravan" 208'],
      salaryRange: '\$60K - \$90K',
      benefits: ['Health Insurance', '401k', 'Relocation Assistance'],
      deadlineDate: DateTime.now().add(const Duration(days: 35)),
    ),
    JobListing(
      id: '5',
      title: 'Aviation Safety Inspector',
      company: 'FAA Regional Office',
      location: 'Los Angeles, CA',
      type: 'Full-Time',
      crewRole: 'Single Pilot',
      crewPosition: null,
      faaRules: ['Part 91'],
      description:
          'Inspect aircraft, maintenance facilities, and operations for compliance with federal aviation regulations.',
      faaCertificates: [
        'Airframe & Powerplant (A&P)',
        'Inspection Authorization (IA)',
      ],
      typeRatingsRequired: const [],
      flightExperience: ['PIC', 'Multi-engine'],
      flightHours: const {'PIC': 1200, 'Multi-engine': 400},
      specialtyExperience: ['Low Altitude', 'Off Airport'],
      specialtyHours: const {'Low Altitude': 100, 'Off Airport': 40},
      aircraftFlown: ['Cessna 172', 'Beechcraft Bonanza', 'Cirrus SR22'],
      salaryRange: '\$70K - \$95K',
      benefits: ['Federal Health Insurance', 'Pension', 'Generous PTO'],
      deadlineDate: DateTime.now().add(const Duration(days: 25)),
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _createTitleController.dispose();
    _createTitleFocusNode.dispose();
    _createCompanyController.dispose();
    _createLocationController.dispose();
    _createTypeController.dispose();
    _createStartingPayController.dispose();
    _createPayForExperienceController.dispose();
    _createDescriptionController.dispose();
    _createTypeRatingsController.dispose();
    _createAircraftController.dispose();
    _createReapplyWindowDaysController.dispose();
    _profileFullNameController.dispose();
    _profileEmailController.dispose();
    _profilePhoneController.dispose();
    _profileCityController.dispose();
    _profileStateController.dispose();
    _profileCountryController.dispose();
    _profileTotalFlightHoursController.dispose();
    _profileTypeRatingsController.dispose();
    _profileAircraftController.dispose();
    _employerCompanyNameController.dispose();
    _employerAddressLine1Controller.dispose();
    _employerAddressLine2Controller.dispose();
    _employerCityController.dispose();
    _employerStateController.dispose();
    _employerPostalCodeController.dispose();
    _employerCountryController.dispose();
    _employerBannerUrlController.dispose();
    _employerLogoUrlController.dispose();
    _employerWebsiteController.dispose();
    _employerContactNameController.dispose();
    _employerContactEmailController.dispose();
    _employerContactPhoneController.dispose();
    _employerDescriptionController.dispose();
    super.dispose();
  }

  List<JobListing> get _visibleJobs {
    if (_profileType != ProfileType.employer) {
      return _allJobs;
    }

    return _allJobs
        .where((job) => job.employerId == _currentEmployer.id)
        .toList();
  }

  List<JobListingTemplate> get _currentEmployerTemplates => _jobTemplates
      .where((template) => template.employerId == _currentEmployer.id)
      .toList();

  JobListingTemplate? get _selectedTemplate {
    final templateId = _selectedTemplateId;
    if (templateId == null || templateId.isEmpty) {
      return null;
    }

    for (final template in _currentEmployerTemplates) {
      if (template.id == templateId) {
        return template;
      }
    }
    return null;
  }

  JobListingTemplate? get _editingTemplate {
    final templateId = _editingTemplateId;
    if (templateId == null || templateId.isEmpty) {
      return null;
    }

    for (final template in _currentEmployerTemplates) {
      if (template.id == templateId) {
        return template;
      }
    }
    return null;
  }

  List<String> _sortedLowerTrimmed(Iterable<String> values) {
    final normalized = values
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    normalized.sort();
    return normalized;
  }

  List<String> _sortedMapEntries(Map<String, int> values) {
    final entries = values.entries
        .map((entry) => '${entry.key.trim().toLowerCase()}:${entry.value}')
        .toList();
    entries.sort();
    return entries;
  }

  String _jobSignature(JobListing job) {
    final values = <String>[
      job.employerId?.trim().toLowerCase() ?? '',
      job.title.trim().toLowerCase(),
      job.location.trim().toLowerCase(),
      job.type.trim().toLowerCase(),
      job.crewRole.trim().toLowerCase(),
      job.crewPosition?.trim().toLowerCase() ?? '',
      job.description.trim().toLowerCase(),
      job.salaryRange?.trim().toLowerCase() ?? '',
      job.deadlineDate?.toIso8601String() ?? '',
      _sortedLowerTrimmed(job.faaRules).join('|'),
      _sortedLowerTrimmed(job.faaCertificates).join('|'),
      _sortedLowerTrimmed(job.typeRatingsRequired).join('|'),
      _sortedMapEntries(job.flightHours).join('|'),
      _sortedLowerTrimmed(job.preferredFlightHours).join('|'),
      _sortedMapEntries(job.instructorHours).join('|'),
      _sortedLowerTrimmed(job.preferredInstructorHours).join('|'),
      _sortedMapEntries(job.specialtyHours).join('|'),
      _sortedLowerTrimmed(job.preferredSpecialtyHours).join('|'),
      _sortedLowerTrimmed(job.aircraftFlown).join('|'),
    ];

    return values.join('||');
  }

  JobListing _buildCreateDraftJob({required String id}) {
    final company = _profileType == ProfileType.employer
        ? _currentEmployer.companyName.trim()
        : _createCompanyController.text.trim();
    final location = _useCompanyLocationForJob
        ? _buildCompanyLocationString()
        : _createLocationController.text.trim();
    final typeRatingsRequired = _createTypeRatingsController.text
        .split(',')
        .map((rating) => rating.trim())
        .where((rating) => rating.isNotEmpty)
        .toSet()
        .toList();

    return JobListing(
      id: id,
      title: _createTitleController.text.trim(),
      company: company,
      location: location,
      type: _createTypeController.text.trim().isNotEmpty
          ? _createTypeController.text.trim()
          : 'Full-Time',
      crewRole: _selectedCrewRole,
      crewPosition: _selectedCrewRole == 'Crew' ? _selectedCrewPosition : null,
      description: _createDescriptionController.text.trim(),
      faaCertificates: List<String>.from(_selectedFaaCertificates),
      typeRatingsRequired: typeRatingsRequired,
      faaRules: _selectedFaaRules.isNotEmpty ? [_selectedFaaRules.first] : [],
      flightExperience: [
        ..._selectedFlightHours.keys,
        ..._selectedInstructorHours.keys,
      ],
      flightHours: Map<String, int>.from(_selectedFlightHours),
      preferredFlightHours: _preferredFlightHours.toList(),
      instructorHours: Map<String, int>.from(_selectedInstructorHours),
      preferredInstructorHours: _preferredInstructorHours.toList(),
      specialtyExperience: _selectedSpecialtyHours.keys.toList(),
      specialtyHours: Map<String, int>.from(_selectedSpecialtyHours),
      preferredSpecialtyHours: _preferredSpecialtyHours.toList(),
      aircraftFlown: _createAircraftController.text
          .split(',')
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty)
          .toSet()
          .toList(),
      salaryRange: _buildCreateSalaryRange(),
      deadlineDate: _createOpenListing ? null : _createDeadlineDate,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      employerId: _profileType == ProfileType.employer
          ? _currentEmployer.id
          : null,
      autoRejectThreshold:
          _createAutoRejectEnabled ? _createAutoRejectThreshold : 0,
      reapplyWindowDays: _createReapplyWindowDays,
    );
  }

  void _applyListingToCreateForm(JobListing job) {
    final companyLocation = _buildCompanyLocationString();

    setState(() {
      _createTitleController.text = job.title;
      _createCompanyController.text = _currentEmployer.companyName;
      _createLocationController.text = job.location;
      _useCompanyLocationForJob =
          companyLocation.isNotEmpty &&
          companyLocation.toLowerCase() == job.location.trim().toLowerCase();
      _createTypeController.text = job.type;
      _createDescriptionController.text = job.description;
      _createTypeRatingsController.text = job.typeRatingsRequired.join(', ');
      _createAircraftController.text = job.aircraftFlown.join(', ');

      _selectedCreatePositionOption = job.crewRole.toLowerCase() == 'crew'
          ? (job.crewPosition == 'Co-Pilot'
                ? 'Crew Member: Co-Pilot'
                : 'Crew Member: Captain')
          : 'Single Pilot';
      _selectedCrewRole = job.crewRole.toLowerCase() == 'crew'
          ? 'Crew'
          : 'Single Pilot';
      _selectedCrewPosition = job.crewPosition == 'Co-Pilot'
          ? 'Co-Pilot'
          : 'Captain';

      _selectedFaaRules
        ..clear()
        ..addAll(job.faaRules.take(1));
      _selectedFaaCertificates
        ..clear()
        ..addAll(job.faaCertificates);
      _selectedFlightHours
        ..clear()
        ..addAll(job.flightHoursByType);
      _preferredFlightHours
        ..clear()
        ..addAll(job.preferredFlightHours);
      _selectedInstructorHours
        ..clear()
        ..addAll(job.instructorHoursByType);
      _preferredInstructorHours
        ..clear()
        ..addAll(job.preferredInstructorHours);
      _selectedSpecialtyHours
        ..clear()
        ..addAll(job.specialtyHoursByType);
      _preferredSpecialtyHours
        ..clear()
        ..addAll(job.preferredSpecialtyHours);

      _createOpenListing = job.deadlineDate == null;
      _createDeadlineDate = job.deadlineDate;

      _createAutoRejectEnabled = job.autoRejectThreshold > 0;
      _createAutoRejectThreshold =
          job.autoRejectThreshold > 0 ? job.autoRejectThreshold : 65;
      _createReapplyWindowDays = job.reapplyWindowDays;
      _createReapplyWindowDaysController.text =
          job.reapplyWindowDays.toString();

      final salary = job.salaryRange?.trim() ?? '';
      _createStartingPayController.clear();
      _createPayForExperienceController.clear();
      _selectedCreatePayRateMetric = null;
      if (salary.isNotEmpty) {
        final metricMatch = RegExp(r'\s*/\s*(.+)$').firstMatch(salary);
        var amountPortion = salary;
        if (metricMatch != null) {
          final metric = metricMatch.group(1)?.trim();
          if (metric != null && _availablePayRateMetrics.contains(metric)) {
            _selectedCreatePayRateMetric = metric;
          }
          amountPortion = salary.substring(0, metricMatch.start).trim();
        }
        final ranges = amountPortion.split('-');
        final startDigits = ranges.first.replaceAll(RegExp(r'\D'), '');
        _createStartingPayController.text = startDigits;
        if (ranges.length > 1) {
          _createPayForExperienceController.text = ranges[1].replaceAll(
            RegExp(r'\D'),
            '',
          );
        }
      }

      _createJobStep = 0;
      _expandedCreateRequirementsSection = 'Certificates and Ratings';
    });
  }

  void _openCreateFromTemplate(
    JobListingTemplate template,
    BuildContext tabContext, {
    bool linkTemplate = true,
  }) {
    _applyListingToCreateForm(template.listing);
    setState(() {
      _selectedTemplateId = linkTemplate ? template.id : null;
      _createOpenedFromTemplate = true;
    });
    DefaultTabController.of(tabContext).animateTo(2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _createTitleFocusNode.requestFocus();
    });
  }

  void _openTemplateEditor(JobListingTemplate template) {
    _applyListingToCreateForm(template.listing);
    setState(() {
      _selectedTemplateId = template.id;
      _editingTemplateId = template.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _createTitleFocusNode.requestFocus();
    });
  }

  Future<void> _openTemplateSummary(
    JobListingTemplate template,
    BuildContext tabContext,
  ) async {
    final listing = template.listing;
    final updatedAt = template.updatedAt ?? template.createdAt;
    final updatedLabel = updatedAt == null
        ? null
        : _formatYmd(updatedAt.toLocal());
    final compensation = listing.salaryRange?.trim() ?? '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(template.name),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${listing.title} • ${listing.location}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text('Job Type: ${listing.type}'),
                Text('Role: ${listing.crewRole} • ${listing.crewPosition}'),
                if (compensation.isNotEmpty)
                  Text('Compensation: $compensation'),
                if (updatedLabel != null) Text('Last Updated: $updatedLabel'),
                if (listing.faaRules.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'FAA Rule',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: listing.faaRules
                        .map((rule) => Chip(label: Text(rule)))
                        .toList(),
                  ),
                ],
                if (listing.faaCertificates.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Certificates',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: listing.faaCertificates
                        .map((cert) => Chip(label: Text(cert)))
                        .toList(),
                  ),
                ],
                if (listing.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Description',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(listing.description.trim()),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _openTemplateEditor(template);
            },
            child: const Text('Edit'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _openCreateFromTemplate(
                template,
                tabContext,
                linkTemplate: false,
              );
            },
            child: const Text('Use Template'),
          ),
        ],
      ),
    );
  }

  void _closeTemplateEditor() {
    setState(() {
      _editingTemplateId = null;
    });
    _clearCreateForm();
  }

  void _cancelCreateListingFlow(BuildContext tabContext) {
    final destinationTab = _createOpenedFromTemplate ? 3 : 1;
    _clearCreateForm();
    DefaultTabController.of(tabContext).animateTo(destinationTab);
  }

  Future<void> _updateSelectedTemplateFromCurrentForm() async {
    final selected = _selectedTemplate;
    if (selected == null) {
      return;
    }
    if (!_validateCreateBasics() || !_validateCreateQualifications()) {
      return;
    }

    final updatedTemplate = JobListingTemplate(
      id: selected.id,
      employerId: selected.employerId,
      name: selected.name,
      listing: _buildCreateDraftJob(id: selected.listing.id),
      createdAt: selected.createdAt,
      updatedAt: DateTime.now(),
    );

    setState(() {
      _jobTemplates = _jobTemplates
          .map(
            (template) =>
                template.id == updatedTemplate.id ? updatedTemplate : template,
          )
          .toList();
    });
    await _saveJobTemplates();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Updated template "${selected.name}".')),
    );
  }

  Future<String?> _promptTemplateName({
    required String title,
    required String initialName,
    String confirmLabel = 'Save',
  }) async {
    final controller = TextEditingController(text: initialName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Template Name *'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) {
                return;
              }
              Navigator.of(dialogContext).pop(true);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    final name = controller.text.trim();
    controller.dispose();
    if (!mounted || confirmed != true || name.isEmpty) {
      return null;
    }
    return name;
  }

  Future<void> _renameTemplate(JobListingTemplate template) async {
    final updatedName = await _promptTemplateName(
      title: 'Edit Template',
      initialName: template.name,
    );
    if (updatedName == null) {
      return;
    }

    setState(() {
      _jobTemplates = _jobTemplates
          .map(
            (item) => item.id == template.id
                ? JobListingTemplate(
                    id: item.id,
                    employerId: item.employerId,
                    name: updatedName,
                    listing: item.listing,
                    createdAt: item.createdAt,
                    updatedAt: DateTime.now(),
                  )
                : item,
          )
          .toList();
    });
    await _saveJobTemplates();
  }

  Future<void> _saveJobAsTemplate(
    JobListing job, {
    bool promptForName = true,
  }) async {
    var templateName = '${job.title} Template';

    if (promptForName) {
      final selectedName = await _promptTemplateName(
        title: 'Save Job as Template',
        initialName: templateName,
      );
      if (selectedName == null) {
        return;
      }
      templateName = selectedName;
    }

    final template = _buildTemplateFromJob(job: job, name: templateName);

    setState(() {
      _jobTemplates = [template, ..._jobTemplates];
      _selectedTemplateId = template.id;
    });
    await _saveJobTemplates();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Saved template "$templateName".')));
  }

  JobListingTemplate _buildTemplateFromJob({
    required JobListing job,
    required String name,
  }) {
    final now = DateTime.now();
    final templateId = now.microsecondsSinceEpoch.toString();
    return JobListingTemplate(
      id: templateId,
      employerId: _currentEmployer.id,
      name: name,
      listing: JobListing(
        id: 'template-$templateId',
        title: job.title,
        company: _currentEmployer.companyName,
        location: job.location,
        type: job.type,
        crewRole: job.crewRole,
        crewPosition: job.crewPosition,
        faaRules: List<String>.from(job.faaRules),
        description: job.description,
        faaCertificates: List<String>.from(job.faaCertificates),
        typeRatingsRequired: List<String>.from(job.typeRatingsRequired),
        flightExperience: List<String>.from(job.flightExperience),
        flightHours: Map<String, int>.from(job.flightHours),
        preferredFlightHours: List<String>.from(job.preferredFlightHours),
        instructorHours: Map<String, int>.from(job.instructorHours),
        preferredInstructorHours: List<String>.from(
          job.preferredInstructorHours,
        ),
        specialtyExperience: List<String>.from(job.specialtyExperience),
        specialtyHours: Map<String, int>.from(job.specialtyHours),
        preferredSpecialtyHours: List<String>.from(job.preferredSpecialtyHours),
        aircraftFlown: List<String>.from(job.aircraftFlown),
        salaryRange: job.salaryRange,
        minimumHours: job.minimumHours,
        benefits: List<String>.from(job.benefits),
        deadlineDate: job.deadlineDate,
        createdAt: now,
        updatedAt: now,
        employerId: _currentEmployer.id,
      ),
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> _deleteTemplate(JobListingTemplate template) async {
    setState(() {
      _jobTemplates = _jobTemplates.where((t) => t.id != template.id).toList();
      if (_selectedTemplateId == template.id) {
        _selectedTemplateId = null;
      }
      if (_editingTemplateId == template.id) {
        _editingTemplateId = null;
      }
    });
    await _saveJobTemplates();
  }

  JobListing? _findDuplicateEmployerListing(JobListing candidate) {
    if (candidate.employerId == null || candidate.employerId!.isEmpty) {
      return null;
    }

    final candidateSignature = _jobSignature(candidate);
    for (final existing in _allJobs) {
      if (existing.employerId != candidate.employerId) {
        continue;
      }
      if (_jobSignature(existing) == candidateSignature) {
        return existing;
      }
    }
    return null;
  }

  List<JobListing> get _filteredJobs {
    final visibleJobs = _visibleJobs;

    if (_query.isEmpty) return visibleJobs;

    final q = _query.toLowerCase();
    return visibleJobs.where((job) {
      return job.title.toLowerCase().contains(q) ||
          job.company.toLowerCase().contains(q) ||
          job.location.toLowerCase().contains(q) ||
          job.type.toLowerCase().contains(q) ||
          job.description.toLowerCase().contains(q);
    }).toList();
  }

  List<JobListing> get _pagedJobs {
    final filtered = _filteredJobs;
    final start = (_page - 1) * _pageSize;
    if (start >= filtered.length) return [];

    final end = (start + _pageSize).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }

  void _changePage(int delta) {
    final maxPages = (_filteredJobs.length / _pageSize).ceil().clamp(1, 999);
    setState(() {
      _page = (_page + delta).clamp(1, maxPages);
    });
  }

  void _toggleFavorite(JobListing job) {
    setState(() {
      if (_favoriteIds.contains(job.id)) {
        _favoriteIds.remove(job.id);
      } else {
        _favoriteIds.add(job.id);
      }
    });
    _saveFavorites();
  }

  bool _jobMatchesEmployerProfile(JobListing job, EmployerProfile profile) {
    final employerId = job.employerId?.trim();
    if (employerId != null && employerId.isNotEmpty) {
      return employerId == profile.id;
    }

    return job.company.trim().toLowerCase() ==
        profile.companyName.trim().toLowerCase();
  }

  EmployerProfile? _findEmployerProfileForJob(JobListing job) {
    for (final profile in _employerProfiles) {
      if (_jobMatchesEmployerProfile(job, profile)) {
        return profile;
      }
    }
    return null;
  }

  int _countOpenRolesForJob(JobListing job) {
    final profile = _findEmployerProfileForJob(job);
    return _allJobs.where((listedJob) {
      if (profile != null) {
        return _jobMatchesEmployerProfile(listedJob, profile);
      }

      return listedJob.company.trim().toLowerCase() ==
          job.company.trim().toLowerCase();
    }).length;
  }

  void _seeAllListingsForCompany(JobListing job) {
    final companyQuery = job.company.trim();
    final targetTabIndex = _profileType == ProfileType.employer ? 1 : 0;

    if (_profileType == ProfileType.jobSeeker) {
      _searchController.text = companyQuery;
    }

    setState(() {
      if (_profileType == ProfileType.jobSeeker) {
        _query = companyQuery;
      }
      _page = 1;
    });

    DefaultTabController.maybeOf(context)?.animateTo(targetTabIndex);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openDetails(JobListing job) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobDetailsPage(
          job: job,
          isFavorite: _favoriteIds.contains(job.id),
          onFavorite: () => _toggleFavorite(job),
          onApply: _hasApplied(job.id) ? null : () => _handleApplyTap(job),
          onShare: () => _shareJobListing(job),
          companyProfile: _findEmployerProfileForJob(job),
          openRoleCount: _countOpenRolesForJob(job),
          onSeeAllListings: () => _seeAllListingsForCompany(job),
          hasApplied: _hasApplied(job.id),
          matchPercentage: _profileType == ProfileType.jobSeeker
              ? _evaluateJobMatch(job).matchPercentage
              : null,
          profile: _profileType == ProfileType.jobSeeker
              ? _jobSeekerProfile
              : null,
        ),
      ),
    );
  }

  Future<void> _loadMyApplications() async {
    final apps = await _appRepository.getApplicationsBySeeker(
      _localJobSeekerId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _myApplications = apps;
      _applicationsByJobId = {for (final app in apps) app.jobId: true};
    });
  }

  Future<void> _loadEmployerApplications() async {
    final apps = await _appRepository.loadApplicationsForEmployer(
      _currentEmployer.id,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _employerApplications = apps;
    });
  }

  Future<void> _loadAllFeedback() async {
    final feedback = await _appRepository.getAllFeedback();
    if (!mounted) {
      return;
    }
    setState(() {
      _allFeedback = feedback;
    });
  }

  Future<void> _applyToJob(JobListing job, {String? coverLetter}) async {
    if (_hasApplied(job.id)) {
      // Check reapply window
      final existing = await _appRepository.getLatestApplicationForJob(
        _localJobSeekerId,
        job.id,
      );
      if (existing != null) {
        final appliedLocal = existing.appliedAt.toLocal();
        final nowLocal = DateTime.now();
        final daysSince = nowLocal.difference(appliedLocal).inDays;
        if (daysSince < job.reapplyWindowDays) {
          final appliedDateStr = _formatYmd(appliedLocal);
          final canReapplyDate = appliedLocal.add(
            Duration(days: job.reapplyWindowDays),
          );
          final canReapplyStr = _formatYmd(canReapplyDate);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'You applied to this job on $appliedDateStr. '
                'You can apply again after $canReapplyStr.',
              ),
            ),
          );
          return;
        }
        // Window has passed — allow re-application (fall through)
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You already applied to this job.')),
        );
        return;
      }
    }

    try {
      final match = _evaluateJobMatch(job);
      final applicantName = JobSeekerProfile.combineName(
        _jobSeekerProfile.firstName,
        _jobSeekerProfile.lastName,
      ).isNotEmpty
          ? JobSeekerProfile.combineName(
              _jobSeekerProfile.firstName,
              _jobSeekerProfile.lastName,
            )
          : _jobSeekerProfile.fullName.trim();

      // Determine initial status (auto-reject if below threshold)
      final autoRejected =
          job.autoRejectThreshold > 0 &&
          match.matchPercentage < job.autoRejectThreshold;
      final initialStatus = autoRejected ? 'rejected' : 'applied';

      final application = Application(
        id: _generateApplicationId(),
        jobSeekerId: _localJobSeekerId,
        jobId: job.id,
        employerId: job.employerId ?? '',
        applicantName: applicantName,
        applicantEmail: _jobSeekerProfile.email.trim(),
        applicantPhone: _jobSeekerProfile.phone.trim(),
        applicantCity: _jobSeekerProfile.city.trim(),
        applicantStateOrProvince: _jobSeekerProfile.stateOrProvince.trim(),
        applicantCountry: _jobSeekerProfile.country.trim(),
        applicantTotalFlightHours: _jobSeekerProfile.totalFlightHours,
        applicantFaaCertificates: List<String>.from(
          _jobSeekerProfile.faaCertificates,
        ),
        applicantTypeRatings: List<String>.from(_jobSeekerProfile.typeRatings),
        applicantAircraftFlown: List<String>.from(
          _jobSeekerProfile.aircraftFlown,
        ),
        status: initialStatus,
        matchPercentage: match.matchPercentage,
        coverLetter: coverLetter ?? '',
        appliedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _appRepository.saveApplication(application);

      // Create auto-reject feedback if applicable
      if (autoRejected) {
        final autoFeedback = ApplicationFeedback(
          id: _generateFeedbackId(),
          applicationId: application.id,
          message:
              'Your application was reviewed and does not meet our minimum '
              'match threshold of ${job.autoRejectThreshold}%.',
          feedbackType: ApplicationFeedback.feedbackTypeNotFit,
          sentByEmployer: true,
          sentAt: DateTime.now(),
          isAutoGenerated: true,
        );
        await _appRepository.saveFeedback(autoFeedback);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _myApplications = [..._myApplications, application];
        _applicationsByJobId = {..._applicationsByJobId, job.id: true};
      });
      _loadEmployerApplications();
      _loadAllFeedback();

      if (autoRejected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Application submitted, but marked as not meeting requirements.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Applied! Employer will see your profile.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error applying: $e')),
      );
    }
  }

  void _handleApplyTap(JobListing job) {
    final match = _evaluateJobMatch(job);
    if (match.matchPercentage >= 90) {
      _applyToJob(job);
    } else {
      _showQuickApplyDialog(job, match);
    }
  }

  Future<void> _updateApplicationStatus(
    Application application,
    String nextStatus,
  ) async {
    try {
      await _appRepository.updateApplicationStatus(application.id, nextStatus);
      if (!mounted) {
        return;
      }

      final updated = application.copyWith(
        status: nextStatus,
        updatedAt: DateTime.now(),
      );

      setState(() {
        _employerApplications = _employerApplications
            .map((app) => app.id == updated.id ? updated : app)
            .toList();
      });
      _loadMyApplications();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Application status updated.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update application: $e')),
      );
    }
  }

  String _applicantLocation(Application app) {
    final parts = [
      app.applicantCity.trim(),
      app.applicantStateOrProvince.trim(),
      app.applicantCountry.trim(),
    ].where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? 'Not provided' : parts.join(' • ');
  }

  Future<void> _sendApplicationFeedback(
    String applicationId,
    String feedbackType,
    String message,
  ) async {
    try {
      final feedback = ApplicationFeedback(
        id: _generateFeedbackId(),
        applicationId: applicationId,
        message: message,
        feedbackType: feedbackType,
        sentByEmployer: true,
        sentAt: DateTime.now(),
      );

      await _appRepository.saveFeedback(feedback);

      // Update application status
      Application? application;
      try {
        application = _employerApplications.firstWhere(
          (app) => app.id == applicationId,
        );
      } catch (_) {
        try {
          application = _myApplications.firstWhere(
            (app) => app.id == applicationId,
          );
        } catch (_) {
          application = null;
        }
      }
      if (application == null) {
        throw StateError('Application not found: $applicationId');
      }
      final nextStatus = feedbackType == ApplicationFeedback.feedbackTypeInterested
          ? Application.statusInterested
          : Application.statusRejected;
      await _appRepository.updateApplicationStatus(applicationId, nextStatus);

      if (!mounted) return;

      final updated = application.copyWith(
        status: nextStatus,
        updatedAt: DateTime.now(),
      );
      setState(() {
        _employerApplications = _employerApplications
            .map((app) => app.id == updated.id ? updated : app)
            .toList();
      });
      await _loadMyApplications();
      await _loadAllFeedback();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feedback sent to applicant.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending feedback: $e')),
      );
    }
  }

  Widget _buildApplicantDetailsList({
    required String title,
    required List<String> values,
    required String emptyText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (values.isEmpty)
          Text(
            emptyText,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: values.map((value) => Chip(label: Text(value))).toList(),
          ),
      ],
    );
  }

  Future<void> _openApplicantDetails(Application app, JobListing job) async {
    final existingFeedback = _getFeedbackForApplication(app.id);
    final customMessageController = TextEditingController();
    String? selectedFeedbackType;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Applicant Details'),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    app.applicantName.trim().isNotEmpty
                        ? app.applicantName
                        : app.jobSeekerId,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Applied for: ${job.title}'),
                  const SizedBox(height: 4),
                  Text('Match: ${app.matchPercentage}%'),
                  const SizedBox(height: 4),
                  Text('Location: ${_applicantLocation(app)}'),
                  const SizedBox(height: 10),
                  Text(
                    'Email: ${app.applicantEmail.trim().isNotEmpty ? app.applicantEmail : 'Not provided'}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Phone: ${app.applicantPhone.trim().isNotEmpty ? app.applicantPhone : 'Not provided'}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total Flight Hours: ${app.applicantTotalFlightHours}',
                  ),
                  const SizedBox(height: 12),
                  _buildApplicantDetailsList(
                    title: 'FAA Certificates',
                    values: app.applicantFaaCertificates,
                    emptyText: 'No certificates provided.',
                  ),
                  const SizedBox(height: 12),
                  _buildApplicantDetailsList(
                    title: 'Type Ratings',
                    values: app.applicantTypeRatings,
                    emptyText: 'No type ratings provided.',
                  ),
                  const SizedBox(height: 12),
                  _buildApplicantDetailsList(
                    title: 'Aircraft Experience',
                    values: app.applicantAircraftFlown,
                    emptyText: 'No aircraft experience provided.',
                  ),
                  if (app.coverLetter.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Cover Letter',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(app.coverLetter.trim()),
                  ],
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  // Previous feedback display
                  if (existingFeedback != null) ...[
                    const Text(
                      'Previous Feedback Sent',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        border: Border.all(color: Colors.blueGrey.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            existingFeedback.message,
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sent ${_formatYmd(existingFeedback.sentAt.toLocal())}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Feedback form
                  const Text(
                    'Send Feedback',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Interested'),
                        selected: selectedFeedbackType ==
                            ApplicationFeedback.feedbackTypeInterested,
                        selectedColor: Colors.green.shade100,
                        onSelected: (_) {
                          setDialogState(() {
                            selectedFeedbackType =
                                ApplicationFeedback.feedbackTypeInterested;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Not a Fit'),
                        selected: selectedFeedbackType ==
                            ApplicationFeedback.feedbackTypeNotFit,
                        selectedColor: Colors.red.shade100,
                        onSelected: (_) {
                          setDialogState(() {
                            selectedFeedbackType =
                                ApplicationFeedback.feedbackTypeNotFit;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Custom'),
                        selected: selectedFeedbackType ==
                            ApplicationFeedback.feedbackTypeCustom,
                        selectedColor: Colors.blue.shade100,
                        onSelected: (_) {
                          setDialogState(() {
                            selectedFeedbackType =
                                ApplicationFeedback.feedbackTypeCustom;
                          });
                        },
                      ),
                    ],
                  ),
                  if (selectedFeedbackType ==
                      ApplicationFeedback.feedbackTypeCustom) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: customMessageController,
                      decoration: const InputDecoration(
                        labelText: 'Custom message',
                        border: OutlineInputBorder(),
                        hintText: 'Enter your feedback message...',
                      ),
                      maxLines: 3,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            if (selectedFeedbackType != null)
              FilledButton(
                onPressed: () async {
                  final type = selectedFeedbackType!;
                  final message = type ==
                          ApplicationFeedback.feedbackTypeInterested
                      ? 'We are interested in your application and would like to move forward.'
                      : type == ApplicationFeedback.feedbackTypeNotFit
                      ? 'Thank you for your interest. Unfortunately, you are not a fit for this role at this time.'
                      : customMessageController.text.trim();

                  if (type == ApplicationFeedback.feedbackTypeCustom &&
                      message.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a custom message.'),
                      ),
                    );
                    return;
                  }

                  Navigator.of(dialogContext).pop();
                  await _sendApplicationFeedback(app.id, type, message);
                },
                child: const Text('Send Feedback'),
              ),
          ],
        ),
      ),
    );

    customMessageController.dispose();
  }

  Future<void> _showQuickApplyDialog(
    JobListing job,
    _MatchResult match,
  ) async {
    final coverLetterController = TextEditingController();
    final matchLabel = match.matchPercentage >= 70
        ? '${match.matchPercentage}% Good Match'
        : '${match.matchPercentage}% Stretch Match';
    final bodyText = match.missingRequirements.isEmpty
        ? 'Add an optional cover letter.'
        : 'Missing: ${match.missingRequirements.take(3).join(', ')}'
            '${match.missingRequirements.length > 3 ? '...' : ''}.';
    final submitted = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(match.matchPercentage >= 70 ? 'Quick Apply' : 'Apply Anyway'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(matchLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(bodyText),
            const SizedBox(height: 16),
            TextField(
              controller: coverLetterController,
              decoration: const InputDecoration(
                labelText: 'Cover letter (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(coverLetterController.text),
            child: const Text('Submit Application'),
          ),
        ],
      ),
    );

    coverLetterController.dispose();

    if (!mounted || submitted == null) {
      return;
    }

    await _applyToJob(job, coverLetter: submitted);
  }

  Future<void> _shareJobListing(JobListing job) async {
    final details = StringBuffer()
      ..writeln('Aviation Job Listing')
      ..writeln('Title: ${job.title}')
      ..writeln('Company: ${job.company}')
      ..writeln('Location: ${job.location}')
      ..writeln('Type: ${job.type}')
      ..writeln('Description: ${job.description}');

    await Clipboard.setData(ClipboardData(text: details.toString()));
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Listing details copied to clipboard.')),
    );
  }

  Future<bool> _confirmDeleteJob(JobListing job) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete job listing?'),
        content: Text(
          'Delete "${job.title}" for ${job.company}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    return shouldDelete ?? false;
  }

  Future<void> _removeJob(JobListing job) async {
    final shouldDelete = await _confirmDeleteJob(job);
    if (!shouldDelete) {
      return;
    }

    final wasFavorite = _favoriteIds.contains(job.id);

    try {
      await _appRepository.deleteJob(job);
      if (!mounted) {
        return;
      }

      setState(() {
        _allJobs.removeWhere((item) => item.id == job.id);
        _favoriteIds.remove(job.id);
        final maxPages = (_filteredJobs.length / _pageSize).ceil().clamp(
          1,
          999,
        );
        _page = _page.clamp(1, maxPages);
      });

      if (wasFavorite) {
        await _saveFavorites();
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted job listing "${job.title}".')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete job listing: $e')),
      );
    }
  }

  Future<void> _editJob(JobListing job) async {
    final titleController = TextEditingController(text: job.title);
    final locationController = TextEditingController(text: job.location);
    String? selectedEmploymentType = _availableJobTypes.contains(job.type)
        ? job.type
        : null;
    String? selectedPositionOption = job.crewRole.toLowerCase() == 'crew'
        ? (job.crewPosition == 'Co-Pilot'
              ? 'Crew Member: Co-Pilot'
              : 'Crew Member: Captain')
        : 'Single Pilot';
    final descriptionController = TextEditingController(text: job.description);
    final startingPayController = TextEditingController();
    final topEndStartingPayController = TextEditingController();
    String? selectedPayMetric;
    final typeRatingsController = TextEditingController(
      text: job.typeRatingsRequired.join(', '),
    );
    final aircraftController = TextEditingController(
      text: job.aircraftFlown.join(', '),
    );
    final selectedFaaCertificates = <String>{
      ..._canonicalizeCertificates(job.faaCertificates),
    };
    String? selectedFaaRule = job.faaRules.isNotEmpty
        ? job.faaRules.first
        : null;
    String selectedCrewRole = job.crewRole.toLowerCase() == 'crew'
        ? 'Crew'
        : 'Single Pilot';
    String selectedCrewPosition = job.crewPosition == 'Co-Pilot'
        ? 'Co-Pilot'
        : 'Captain';
    bool isOpenListing = job.deadlineDate == null;
    DateTime? selectedDeadlineDate = job.deadlineDate;

    String extractNumericValue(String value) {
      return value.replaceAll(RegExp(r'\D'), '');
    }

    String? buildEditedSalaryRange() {
      final startingPayValue = _parsePositiveInt(startingPayController.text);
      if (startingPayValue == null) {
        return null;
      }

      final topEndPayValue = _parsePositiveInt(
        topEndStartingPayController.text,
      );
      final metric = selectedPayMetric;
      final metricSuffix = metric == null || metric.isEmpty ? '' : ' / $metric';

      final startLabel = '\$${startingPayValue.toString()}';

      if (topEndPayValue != null) {
        final topEndLabel = '\$${topEndPayValue.toString()}';
        return '$startLabel - $topEndLabel$metricSuffix';
      }

      return '$startLabel$metricSuffix';
    }

    void hydrateSalaryEditors(String? salaryRange) {
      if (salaryRange == null || salaryRange.trim().isEmpty) {
        return;
      }

      final raw = salaryRange.trim();
      final metricMatch = RegExp(r'\s*(?:/|per)\s+(.+)$').firstMatch(raw);
      var amountPortion = raw;

      if (metricMatch != null) {
        final parsedMetric = metricMatch.group(1)?.trim();
        if (parsedMetric != null) {
          const legacyMetricMap = {
            'Weekly Rate': 'Weekly Salary',
            'Monthly Rate': 'Monthly Salary',
          };
          final normalizedMetric =
              legacyMetricMap[parsedMetric] ?? parsedMetric;
          if (_availablePayRateMetrics.contains(normalizedMetric)) {
            selectedPayMetric = normalizedMetric;
          }
        }
        amountPortion = raw.substring(0, metricMatch.start).trim();
      }

      if (amountPortion.contains('-')) {
        final parts = amountPortion.split('-');
        startingPayController.text = extractNumericValue(parts.first.trim());
        if (parts.length > 1) {
          topEndStartingPayController.text = extractNumericValue(
            parts[1].trim(),
          );
        }
      } else {
        startingPayController.text = extractNumericValue(amountPortion);
      }
    }

    hydrateSalaryEditors(job.salaryRange);

    List<String> mergedOptions(
      List<String> defaults,
      Iterable<String> current,
    ) {
      final merged = <String>[...defaults];
      for (final option in current) {
        if (!merged.contains(option)) {
          merged.add(option);
        }
      }
      return merged;
    }

    final flightOptions = mergedOptions(
      _availableEmployerFlightHours,
      job.flightHoursByType.keys,
    );
    final instructorOptions = mergedOptions(
      _availableInstructorHours,
      job.instructorHoursByType.keys,
    );
    final specialtyOptions = mergedOptions(
      _availableSpecialtyExperience,
      job.specialtyHoursByType.keys,
    );

    final selectedFlightHours = <String>{...job.flightHoursByType.keys};
    final preferredFlightHours = <String>{...job.preferredFlightHours};
    final selectedInstructorHours = <String>{...job.instructorHoursByType.keys};
    final preferredInstructorHours = <String>{...job.preferredInstructorHours};
    final selectedSpecialtyHours = <String>{...job.specialtyHoursByType.keys};
    final preferredSpecialtyHours = <String>{...job.preferredSpecialtyHours};

    final flightHourControllers = {
      for (final option in flightOptions)
        option: TextEditingController(
          text: (job.flightHoursByType[option] ?? 0) > 0
              ? (job.flightHoursByType[option] ?? 0).toString()
              : '',
        ),
    };
    final instructorHourControllers = {
      for (final option in instructorOptions)
        option: TextEditingController(
          text: (job.instructorHoursByType[option] ?? 0) > 0
              ? (job.instructorHoursByType[option] ?? 0).toString()
              : '',
        ),
    };
    final specialtyHourControllers = {
      for (final option in specialtyOptions)
        option: TextEditingController(
          text: (job.specialtyHoursByType[option] ?? 0) > 0
              ? (job.specialtyHoursByType[option] ?? 0).toString()
              : '',
        ),
    };

    final lockedCompanyName = _currentEmployer.companyName.trim().isNotEmpty
        ? _currentEmployer.companyName.trim()
        : job.company;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    bool hasDraftChanges(JobListing draft) {
      return draft.title != job.title ||
          draft.company != job.company ||
          draft.location != job.location ||
          draft.type != job.type ||
          draft.crewRole != job.crewRole ||
          draft.crewPosition != job.crewPosition ||
          draft.description != job.description ||
          !_sameStringSet(draft.faaRules, job.faaRules, trim: true) ||
          !_sameStringSet(
            draft.faaCertificates,
            job.faaCertificates,
            trim: true,
          ) ||
          !_sameStringSet(
            draft.typeRatingsRequired,
            job.typeRatingsRequired,
            trim: true,
          ) ||
          !_sameIntMap(draft.flightHours, job.flightHours) ||
          !_sameStringSet(
            draft.preferredFlightHours,
            job.preferredFlightHours,
            trim: true,
          ) ||
          !_sameIntMap(draft.instructorHours, job.instructorHours) ||
          !_sameStringSet(
            draft.preferredInstructorHours,
            job.preferredInstructorHours,
            trim: true,
          ) ||
          !_sameIntMap(draft.specialtyHours, job.specialtyHours) ||
          !_sameStringSet(
            draft.preferredSpecialtyHours,
            job.preferredSpecialtyHours,
            trim: true,
          ) ||
          !_sameStringSet(draft.aircraftFlown, job.aircraftFlown, trim: true) ||
          draft.salaryRange != job.salaryRange ||
          draft.deadlineDate != job.deadlineDate;
    }

    JobListing? buildEditedDraft({bool showValidationFeedback = true}) {
      final title = titleController.text.trim();
      final location = locationController.text.trim();

      final missingRequirements = <String>[];
      if (title.isEmpty) {
        missingRequirements.add('Title');
      }
      if (location.isEmpty) {
        missingRequirements.add('Location');
      }
      if (selectedEmploymentType == null || selectedEmploymentType!.isEmpty) {
        missingRequirements.add('Employment Type');
      }
      if (selectedPositionOption == null || selectedPositionOption!.isEmpty) {
        missingRequirements.add('Position Selection');
      }
      if (descriptionController.text.trim().isEmpty) {
        missingRequirements.add('Description');
      }
      if (startingPayController.text.trim().isEmpty) {
        missingRequirements.add('Starting Pay');
      }
      if (startingPayController.text.trim().isNotEmpty &&
          _parsePositiveInt(startingPayController.text) == null) {
        missingRequirements.add('Starting Pay must be a positive integer');
      }
      if (topEndStartingPayController.text.trim().isNotEmpty &&
          _parsePositiveInt(topEndStartingPayController.text) == null) {
        missingRequirements.add(
          'Top End Starting Pay must be a positive integer',
        );
      }
      if (selectedPayMetric == null || selectedPayMetric!.isEmpty) {
        missingRequirements.add('Pay Metric');
      }
      if (!isOpenListing && selectedDeadlineDate == null) {
        missingRequirements.add('Application Deadline');
      }
      if (selectedFaaRule == null || selectedFaaRule!.isEmpty) {
        missingRequirements.add('FAA Operational Scope');
      }

      final hasCertificateSelection = selectedFaaCertificates.any(
        _availableFaaCertificates.contains,
      );
      final hasRatingSelection = selectedFaaCertificates.any(
        _availableRatingSelections.contains,
      );
      if (!hasCertificateSelection) {
        missingRequirements.add('At Least One Certificate Selection Required');
      }
      if (!hasRatingSelection) {
        missingRequirements.add('At Least One Rating Selection Required');
      }

      final hasAnyHoursSelection =
          selectedFlightHours.isNotEmpty ||
          selectedInstructorHours.isNotEmpty ||
          selectedSpecialtyHours.isNotEmpty;
      if (!hasAnyHoursSelection) {
        missingRequirements.add('Enter At Least One Minimum Hours Requirement');
      }

      bool hasMissingHoursValues(
        Set<String> selected,
        Map<String, TextEditingController> controllers,
      ) {
        for (final option in selected) {
          final value =
              int.tryParse(controllers[option]?.text.trim() ?? '0') ?? 0;
          if (value <= 0) {
            return true;
          }
        }
        return false;
      }

      final missingHoursValue =
          hasMissingHoursValues(selectedFlightHours, flightHourControllers) ||
          hasMissingHoursValues(
            selectedInstructorHours,
            instructorHourControllers,
          ) ||
          hasMissingHoursValues(
            selectedSpecialtyHours,
            specialtyHourControllers,
          );

      if (hasAnyHoursSelection && missingHoursValue) {
        missingRequirements.add(
          'Each selected Hours Requirement must include a numeric value greater than 0',
        );
      }

      final hasRequiredFlightHour = selectedFlightHours.any(
        (name) => !preferredFlightHours.contains(name),
      );
      final hasRequiredInstructorHour = selectedInstructorHours.any(
        (name) => !preferredInstructorHours.contains(name),
      );
      final hasRequiredSpecialtyHour = selectedSpecialtyHours.any(
        (name) => !preferredSpecialtyHours.contains(name),
      );
      final hasRequiredHoursSelection =
          hasRequiredFlightHour ||
          hasRequiredInstructorHour ||
          hasRequiredSpecialtyHour;

      if (hasAnyHoursSelection && !hasRequiredHoursSelection) {
        missingRequirements.add(
          'At Least One Hours Requirement must be marked as Required',
        );
      }

      if (missingRequirements.isNotEmpty) {
        if (showValidationFeedback) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Missing: ${missingRequirements.join(', ')}'),
            ),
          );
        }
        return null;
      }

      Map<String, int> collectSelectedHours(
        Set<String> selected,
        Map<String, TextEditingController> controllers,
      ) {
        return {
          for (final option in selected)
            option: int.tryParse(controllers[option]?.text.trim() ?? '0') ?? 0,
        };
      }

      final parsedTypeRatings = typeRatingsController.text
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toSet()
          .toList();

      final parsedAircraft = aircraftController.text
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toSet()
          .toList();

      final flightHours = collectSelectedHours(
        selectedFlightHours,
        flightHourControllers,
      );
      final instructorHours = collectSelectedHours(
        selectedInstructorHours,
        instructorHourControllers,
      );
      final specialtyHours = collectSelectedHours(
        selectedSpecialtyHours,
        specialtyHourControllers,
      );

      return JobListing(
        id: job.id,
        title: title,
        company: lockedCompanyName,
        location: location,
        type: selectedEmploymentType!,
        crewRole: selectedCrewRole,
        crewPosition: selectedCrewRole == 'Crew' ? selectedCrewPosition : null,
        faaRules: selectedFaaRule == null ? [] : [selectedFaaRule!],
        description: descriptionController.text.trim(),
        faaCertificates: selectedFaaCertificates.toList(),
        typeRatingsRequired: parsedTypeRatings,
        flightExperience: [...flightHours.keys, ...instructorHours.keys],
        flightHours: flightHours,
        preferredFlightHours: preferredFlightHours
            .where(flightHours.containsKey)
            .toList(),
        instructorHours: instructorHours,
        preferredInstructorHours: preferredInstructorHours
            .where(instructorHours.containsKey)
            .toList(),
        specialtyExperience: specialtyHours.keys.toList(),
        specialtyHours: specialtyHours,
        preferredSpecialtyHours: preferredSpecialtyHours
            .where(specialtyHours.containsKey)
            .toList(),
        aircraftFlown: parsedAircraft,
        salaryRange: buildEditedSalaryRange(),
        minimumHours: job.minimumHours,
        benefits: List<String>.from(job.benefits),
        deadlineDate: isOpenListing ? null : selectedDeadlineDate,
        createdAt: job.createdAt,
        updatedAt: DateTime.now(),
        employerId: job.employerId,
      );
    }

    Widget buildEditForm(void Function(VoidCallback fn) setModalState) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: titleController,
            onChanged: (_) => setModalState(() {}),
            decoration: const InputDecoration(labelText: 'Job Title *'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: lockedCompanyName,
            readOnly: true,
            decoration: const InputDecoration(labelText: 'Company'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: locationController,
            onChanged: (_) => setModalState(() {}),
            decoration: const InputDecoration(labelText: 'Location *'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: selectedEmploymentType,
            hint: const Text('Select Employment Type'),
            decoration: const InputDecoration(labelText: 'Employment Type *'),
            items: _availableJobTypes
                .map(
                  (type) =>
                      DropdownMenuItem<String>(value: type, child: Text(type)),
                )
                .toList(),
            onChanged: (value) {
              setModalState(() => selectedEmploymentType = value);
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: selectedPositionOption,
            hint: const Text('Select Position'),
            decoration: const InputDecoration(
              labelText: 'Position Selection *',
            ),
            items: const [
              DropdownMenuItem(
                value: 'Single Pilot',
                child: Text('Single Pilot'),
              ),
              DropdownMenuItem(
                value: 'Crew Member: Captain',
                child: Text('Crew Member: Captain'),
              ),
              DropdownMenuItem(
                value: 'Crew Member: Co-Pilot',
                child: Text('Crew Member: Co-Pilot'),
              ),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setModalState(() {
                selectedPositionOption = value;
                if (value == 'Single Pilot') {
                  selectedCrewRole = 'Single Pilot';
                  selectedCrewPosition = 'Captain';
                } else if (value == 'Crew Member: Co-Pilot') {
                  selectedCrewRole = 'Crew';
                  selectedCrewPosition = 'Co-Pilot';
                } else {
                  selectedCrewRole = 'Crew';
                  selectedCrewPosition = 'Captain';
                }
              });
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: descriptionController,
            maxLines: 4,
            onChanged: (_) => setModalState(() {}),
            decoration: const InputDecoration(labelText: 'Description *'),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Application Timeline',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                RadioGroup<bool>(
                  groupValue: isOpenListing,
                  onChanged: (value) {
                    setModalState(() {
                      isOpenListing = value ?? true;
                      if (isOpenListing) {
                        selectedDeadlineDate = null;
                      }
                    });
                  },
                  child: const Column(
                    children: [
                      RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Open Listing (No Deadline)'),
                        value: true,
                      ),
                      RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Set Application Deadline'),
                        value: false,
                      ),
                    ],
                  ),
                ),
                if (!isOpenListing)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate:
                              selectedDeadlineDate ??
                              now.add(const Duration(days: 30)),
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 730)),
                        );
                        if (pickedDate == null) {
                          return;
                        }
                        setModalState(() {
                          selectedDeadlineDate = pickedDate;
                        });
                      },
                      icon: const Icon(Icons.event),
                      label: Text(
                        selectedDeadlineDate == null
                            ? 'Choose deadline date'
                            : 'Application Deadline: ${_formatYmd(selectedDeadlineDate!)}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildEditAccordionSection(
            title: 'Salary Range *',
            initiallyExpanded: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: startingPayController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => setModalState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Starting Pay *',
                          prefixText: r'$',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: topEndStartingPayController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => setModalState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Top End Starting Pay (Optional)',
                          prefixText: r'$',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedPayMetric,
                  hint: const Text('Select pay metric'),
                  decoration: const InputDecoration(
                    labelText: 'Pay Metric *',
                    isDense: true,
                  ),
                  items: _availablePayRateMetrics
                      .map(
                        (metric) => DropdownMenuItem<String>(
                          value: metric,
                          child: Text(metric),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setModalState(() => selectedPayMetric = value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _buildEditAccordionSection(
            title: 'FAA Operational Scope *',
            initiallyExpanded: true,
            child: DropdownButtonFormField<String>(
              initialValue: selectedFaaRule,
              hint: const Text('Select FAA Operational Scope'),
              decoration: const InputDecoration(
                labelText: 'FAA Operational Scope *',
              ),
              items: [
                ..._availableFaaRules.map(
                  (rule) =>
                      DropdownMenuItem<String>(value: rule, child: Text(rule)),
                ),
              ],
              onChanged: (value) {
                setModalState(() => selectedFaaRule = value);
              },
            ),
          ),
          const SizedBox(height: 14),
          _buildEditAccordionSection(
            title: 'Required FAA Certificates *',
            initiallyExpanded: true,
            child: Column(
              children: _availableFaaCertificates.map((cert) {
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(cert),
                  value: selectedFaaCertificates.contains(cert),
                  onChanged: (selected) {
                    setModalState(() {
                      if (selected == true) {
                        if (cert == 'Airline Transport Pilot (ATP)') {
                          selectedFaaCertificates.removeWhere(
                            (c) =>
                                c == 'Private Pilot (PPL)' ||
                                c == 'Commercial Pilot (CPL)' ||
                                c == 'Instrument Rating (IFR)',
                          );
                        }
                        if (cert == 'Commercial Pilot (CPL)') {
                          selectedFaaCertificates.remove('Private Pilot (PPL)');
                        }
                        selectedFaaCertificates.add(cert);
                      } else {
                        selectedFaaCertificates.remove(cert);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          _buildEditAccordionSection(
            title: 'Instructor Certificates',
            initiallyExpanded: true,
            child: Column(
              children: _availableInstructorCertificates.map((cert) {
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(cert),
                  value: selectedFaaCertificates.contains(cert),
                  onChanged: (selected) {
                    setModalState(() {
                      if (selected == true) {
                        selectedFaaCertificates.add(cert);
                      } else {
                        selectedFaaCertificates.remove(cert);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          _buildEditAccordionSection(
            title: 'Required Ratings *',
            initiallyExpanded: true,
            child: Column(
              children: _availableRatingSelections.map((rating) {
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(rating),
                  value: selectedFaaCertificates.contains(rating),
                  onChanged: (selected) {
                    setModalState(() {
                      if (selected == true) {
                        selectedFaaCertificates.add(rating);
                      } else {
                        selectedFaaCertificates.remove(rating);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          _buildEditHourRequirementSection(
            title: 'Flight Hours Required *',
            options: flightOptions,
            selectedOptions: selectedFlightHours,
            preferredOptions: preferredFlightHours,
            hourControllers: flightHourControllers,
            setModalState: setModalState,
          ),
          const SizedBox(height: 14),
          _buildEditHourRequirementSection(
            title: 'Instructor Hours',
            options: instructorOptions,
            selectedOptions: selectedInstructorHours,
            preferredOptions: preferredInstructorHours,
            hourControllers: instructorHourControllers,
            setModalState: setModalState,
          ),
          const SizedBox(height: 14),
          _buildEditHourRequirementSection(
            title: 'Specialty Hours',
            options: specialtyOptions,
            selectedOptions: selectedSpecialtyHours,
            preferredOptions: preferredSpecialtyHours,
            hourControllers: specialtyHourControllers,
            setModalState: setModalState,
          ),
          const SizedBox(height: 10),
          _buildEditAccordionSection(
            title: 'Aircraft Experience (Coming soon)',
            child: TextField(
              controller: aircraftController,
              onChanged: (_) => setModalState(() {}),
              decoration: const InputDecoration(
                labelText: 'Aircraft (comma-separated)',
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildEditAccordionSection(
            title: 'Type Ratings (Coming soon)',
            child: TextField(
              controller: typeRatingsController,
              onChanged: (_) => setModalState(() {}),
              decoration: const InputDecoration(
                labelText: 'Type Ratings (comma-separated)',
              ),
            ),
          ),
        ],
      );
    }

    try {
      final isMobileEditor = MediaQuery.of(context).size.width < 720;
      JobListing? editedDraft;
      if (isMobileEditor) {
        editedDraft = await navigator.push<JobListing>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (pageContext) => StatefulBuilder(
              builder: (pageContext, setModalState) {
                final draftPreview = buildEditedDraft(
                  showValidationFeedback: false,
                );
                final canSave =
                    draftPreview != null && hasDraftChanges(draftPreview);

                return Scaffold(
                  appBar: AppBar(title: const Text('Edit Job Listing')),
                  body: SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: buildEditForm(setModalState),
                    ),
                  ),
                  bottomNavigationBar: SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                      decoration: BoxDecoration(
                        color: Theme.of(pageContext).scaffoldBackgroundColor,
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(pageContext).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: canSave
                                  ? () {
                                      final draft = buildEditedDraft();
                                      if (draft != null &&
                                          hasDraftChanges(draft)) {
                                        Navigator.of(pageContext).pop(draft);
                                      }
                                    }
                                  : null,
                              child: const Text('Save Changes'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      } else {
        editedDraft = await showDialog<JobListing>(
          context: navigator.context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setModalState) {
              final draftPreview = buildEditedDraft(
                showValidationFeedback: false,
              );
              final canSave =
                  draftPreview != null && hasDraftChanges(draftPreview);

              return AlertDialog(
                title: const Text('Edit Job Listing'),
                content: SizedBox(
                  width: 560,
                  child: SingleChildScrollView(
                    child: buildEditForm(setModalState),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: canSave
                        ? () {
                            final draft = buildEditedDraft();
                            if (draft != null && hasDraftChanges(draft)) {
                              Navigator.of(dialogContext).pop(draft);
                            }
                          }
                        : null,
                    child: const Text('Save Changes'),
                  ),
                ],
              );
            },
          ),
        );
      }

      if (editedDraft == null) {
        return;
      }

      final updatedJob = await _appRepository.updateJob(editedDraft);
      if (!mounted) {
        return;
      }

      setState(() {
        _allJobs = _allJobs
            .map((item) => item.id == updatedJob.id ? updatedJob : item)
            .toList();
      });

      messenger.showSnackBar(
        SnackBar(content: Text('Updated job listing "${updatedJob.title}".')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Could not update job listing: $e')),
      );
    } finally {
      titleController.dispose();
      locationController.dispose();
      descriptionController.dispose();
      startingPayController.dispose();
      topEndStartingPayController.dispose();
      typeRatingsController.dispose();
      aircraftController.dispose();
      for (final controller in flightHourControllers.values) {
        controller.dispose();
      }
      for (final controller in instructorHourControllers.values) {
        controller.dispose();
      }
      for (final controller in specialtyHourControllers.values) {
        controller.dispose();
      }
    }
  }

  Widget _buildEditAccordionSection({
    required String title,
    required Widget child,
    bool initiallyExpanded = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          children: [child],
        ),
      ),
    );
  }

  Widget _buildEditHourRequirementSection({
    required String title,
    required List<String> options,
    required Set<String> selectedOptions,
    required Set<String> preferredOptions,
    required Map<String, TextEditingController> hourControllers,
    required void Function(VoidCallback fn) setModalState,
  }) {
    return _buildEditAccordionSection(
      title: title,
      initiallyExpanded: true,
      child: Column(
        children: options.map((option) {
          final isSelected = selectedOptions.contains(option);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(option),
                  value: isSelected,
                  onChanged: (checked) {
                    setModalState(() {
                      if (checked == true) {
                        selectedOptions.add(option);
                      } else {
                        selectedOptions.remove(option);
                        preferredOptions.remove(option);
                      }
                    });
                  },
                ),
                if (isSelected)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: hourControllers[option],
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setModalState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Hours',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: preferredOptions.contains(option)
                              ? 'Preferred'
                              : 'Required',
                          isDense: true,
                          decoration: const InputDecoration(
                            labelText: 'Requirement',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Required',
                              child: Text('Required'),
                            ),
                            DropdownMenuItem(
                              value: 'Preferred',
                              child: Text('Preferred'),
                            ),
                          ],
                          onChanged: (value) {
                            setModalState(() {
                              if (value == 'Preferred') {
                                preferredOptions.add(option);
                              } else {
                                preferredOptions.remove(option);
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  bool _canDeleteJob(JobListing job) {
    return _profileType == ProfileType.employer &&
        job.employerId == _currentEmployer.id;
  }

  bool _canEditJob(JobListing job) {
    return _profileType == ProfileType.employer &&
        job.employerId == _currentEmployer.id;
  }

  String _buildCompanyLocationString() {
    final city = _currentEmployer.headquartersCity.trim();
    final state = _currentEmployer.headquartersState.trim();
    if (city.isNotEmpty && state.isNotEmpty) {
      return '$city, $state';
    } else if (city.isNotEmpty) {
      return city;
    } else if (state.isNotEmpty) {
      return state;
    }
    return 'Company headquarters location not set';
  }

  String _buildJobTimelineText(JobListing job) {
    return _buildTimelineLabels(
      createdAt: job.createdAt,
      updatedAt: job.updatedAt,
    ).join(' • ');
  }

  void _clearCreateForm() {
    _createJobStep = 0;
    _useCompanyLocationForJob = true;
    _createOpenListing = true;
    _createDeadlineDate = null;
    _createTitleController.clear();
    _createCompanyController.text = _currentEmployer.companyName;
    _createLocationController.clear();
    _createTypeController.clear();
    _selectedCreatePositionOption = null;
    _selectedTemplateId = null;
    _createOpenedFromTemplate = false;
    _createStartingPayController.clear();
    _createPayForExperienceController.clear();
    _selectedCreatePayRateMetric = null;
    _selectedCrewRole = 'Single Pilot';
    _selectedCrewPosition = 'Captain';
    _createDescriptionController.clear();
    _createTypeRatingsController.clear();
    _selectedFaaCertificates.clear();
    _selectedFaaRules.clear();
    _selectedFlightHours.clear();
    _preferredFlightHours.clear();
    _selectedInstructorHours.clear();
    _preferredInstructorHours.clear();
    _selectedSpecialtyHours.clear();
    _preferredSpecialtyHours.clear();
    _createAircraftController.clear();
    _expandedCreateRequirementsSection = 'Certificates and Ratings';
    _createAutoRejectEnabled = false;
    _createAutoRejectThreshold = 65;
    _createReapplyWindowDays = 30;
    _createReapplyWindowDaysController.text = '30';
  }

  List<String> _missingCreateBasicsRequirements() {
    final missing = <String>[];

    final title = _createTitleController.text.trim();
    final company = _profileType == ProfileType.employer
        ? _currentEmployer.companyName.trim()
        : _createCompanyController.text.trim();
    final location = _useCompanyLocationForJob
        ? _buildCompanyLocationString()
        : _createLocationController.text.trim();
    final type = _createTypeController.text.trim();
    final position = _selectedCreatePositionOption;
    final startingPay = _createStartingPayController.text.trim();
    final topEndPay = _createPayForExperienceController.text.trim();
    final payMetric = _selectedCreatePayRateMetric;
    final description = _createDescriptionController.text.trim();

    if (title.isEmpty) missing.add('Title');
    if (company.isEmpty) missing.add('Company');
    if (location.isEmpty) missing.add('Location');
    if (type.isEmpty) missing.add('Employment Type');
    if (position == null || position.isEmpty) missing.add('Position Selection');
    if (description.isEmpty) missing.add('Description');
    if (startingPay.isEmpty) missing.add('Starting Pay');
    if (startingPay.isNotEmpty && _parsePositiveInt(startingPay) == null) {
      missing.add('Starting Pay must be a positive integer');
    }
    if (topEndPay.isNotEmpty && _parsePositiveInt(topEndPay) == null) {
      missing.add('Top End Starting Pay must be a positive integer');
    }
    if (payMetric == null || payMetric.isEmpty) missing.add('Pay Metric');
    if (!_createOpenListing && _createDeadlineDate == null) {
      missing.add('Application Deadline');
    }

    return missing;
  }

  void _showMissingRequirementsDialog({
    required List<String> missingItems,
    String title = 'Required Selections Missing',
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please complete the following before continuing:'),
            const SizedBox(height: 8),
            ...missingItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('- $item'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  bool _validateCreateBasics({bool showFeedback = true}) {
    final missing = _missingCreateBasicsRequirements();

    if (missing.isNotEmpty) {
      if (showFeedback) {
        _showMissingRequirementsDialog(missingItems: missing);
      }
      return false;
    }

    return true;
  }

  bool _validateCreateQualifications({bool showFeedback = true}) {
    final hasOperationalScope = _selectedFaaRules.isNotEmpty;
    final hasCertificateSelection = _selectedFaaCertificates.any(
      _availableFaaCertificates.contains,
    );
    final hasRatingSelection = _selectedFaaCertificates.any(
      _availableRatingSelections.contains,
    );
    final selectedFlightHourEntries = _selectedFlightHours.entries.toList();
    final selectedInstructorHourEntries = _selectedInstructorHours.entries
        .toList();
    final selectedSpecialtyHourEntries = _selectedSpecialtyHours.entries
        .toList();

    final selectedHoursCount =
        selectedFlightHourEntries.length +
        selectedInstructorHourEntries.length +
        selectedSpecialtyHourEntries.length;

    final hasAnyHoursSelection = selectedHoursCount > 0;

    final hasMissingHoursValues =
        selectedFlightHourEntries.any((entry) => entry.value <= 0) ||
        selectedInstructorHourEntries.any((entry) => entry.value <= 0) ||
        selectedSpecialtyHourEntries.any((entry) => entry.value <= 0);

    final hasRequiredFlightHour = _selectedFlightHours.keys.any(
      (name) => !_preferredFlightHours.contains(name),
    );
    final hasRequiredInstructorHour = _selectedInstructorHours.keys.any(
      (name) => !_preferredInstructorHours.contains(name),
    );
    final hasRequiredSpecialtyHour = _selectedSpecialtyHours.keys.any(
      (name) => !_preferredSpecialtyHours.contains(name),
    );
    final hasRequiredHoursSelection =
        hasRequiredFlightHour ||
        hasRequiredInstructorHour ||
        hasRequiredSpecialtyHour;

    final missing = <String>[];
    if (!hasOperationalScope) {
      missing.add('FAA Operational Scope');
    }
    if (!hasCertificateSelection) {
      missing.add('At Least One Certificate Selection Required');
    }
    if (!hasRatingSelection) {
      missing.add('At Least One Rating Selection Required');
    }
    if (!hasAnyHoursSelection) {
      missing.add('Enter At Least One Minimum Hours Requirement');
    } else {
      if (hasMissingHoursValues) {
        missing.add(
          'Each selected Hours Requirement must include a numeric value greater than 0',
        );
      }
      if (!hasRequiredHoursSelection) {
        missing.add(
          'At Least One Hours Requirement must be marked as Required',
        );
      }
    }

    if (missing.isEmpty) {
      return true;
    }

    if (showFeedback) {
      _showMissingRequirementsDialog(missingItems: missing);
    }

    return false;
  }

  Future<void> _showCreatedJobSummary(JobListing job) async {
    final requirementCount =
        job.faaCertificates.length +
        job.flightHoursByType.length +
        job.instructorHoursByType.length +
        job.specialtyHoursByType.length;
    final timelineText = _buildTimelineLabels(
      createdAt: job.createdAt,
      updatedAt: job.updatedAt,
      includeUnavailable: true,
    ).join(' • ');
    final deadlineText = job.deadlineDate != null
        ? 'Application Deadline: ${_formatYmd(job.deadlineDate!.toLocal())}'
        : null;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Job Listing Created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Title: ${job.title}'),
            const SizedBox(height: 6),
            Text('Company: ${job.company}'),
            const SizedBox(height: 6),
            Text('Location: ${job.location}'),
            const SizedBox(height: 6),
            Text('Type: ${job.type}'),
            if (deadlineText != null) ...[
              const SizedBox(height: 6),
              Text(deadlineText),
            ],
            if (timelineText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(timelineText),
            ],
            const SizedBox(height: 6),
            Text('Requirements configured: $requirementCount'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String? _buildCreateSalaryRange() {
    final startingPayValue = _parsePositiveInt(
      _createStartingPayController.text,
    );
    if (startingPayValue == null) {
      return null;
    }

    final payForExperienceValue = _parsePositiveInt(
      _createPayForExperienceController.text,
    );
    final metric = _selectedCreatePayRateMetric;
    final metricSuffix = metric == null || metric.isEmpty ? '' : ' / $metric';

    final startLabel = '\$${startingPayValue.toString()}';

    if (payForExperienceValue != null) {
      final endLabel = '\$${payForExperienceValue.toString()}';
      return '$startLabel - $endLabel$metricSuffix';
    }

    return '$startLabel$metricSuffix';
  }

  Future<void> _createJobListing(BuildContext tabContext) async {
    final tabController = DefaultTabController.maybeOf(tabContext);

    if (!_validateCreateBasics()) {
      return;
    }

    if (!_validateCreateQualifications()) {
      return;
    }

    final draftJob = _buildCreateDraftJob(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
    );

    final duplicateJob = _findDuplicateEmployerListing(draftJob);
    if (duplicateJob != null) {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Duplicate listing blocked'),
          content: Text(
            'This listing matches your existing listing "${duplicateJob.title}". Update at least one required field or location before posting.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    try {
      final createdJob = await _appRepository.createJob(draftJob);
      if (!mounted) {
        return;
      }

      setState(() {
        _allJobs = [createdJob, ..._allJobs];
        _query = '';
        _page = 1;
      });

      _clearCreateForm();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Job listing "${draftJob.title}" created.')),
      );
      await _showCreatedJobSummary(createdJob);
      if (!mounted || _profileType != ProfileType.employer) {
        return;
      }
      tabController?.animateTo(1);
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create job listing: $e')),
      );
    }
  }

  Widget _buildResponsiveTabContent(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final leftInset = math.max(
          mediaQuery.viewPadding.left,
          math.max(
            mediaQuery.padding.left,
            mediaQuery.systemGestureInsets.left,
          ),
        );
        final rightInset = math.max(
          mediaQuery.viewPadding.right,
          math.max(
            mediaQuery.padding.right,
            mediaQuery.systemGestureInsets.right,
          ),
        );
        final availableWidth = math.max(
          0.0,
          constraints.maxWidth - leftInset - rightInset,
        );
        final edgePadding = availableWidth >= 900 ? 24.0 : 12.0;
        final targetMaxWidth = availableWidth >= 900 ? 960.0 : availableWidth;
        final contentMaxWidth = math.max(
          0.0,
          targetMaxWidth - (edgePadding * 2),
        );
        return Center(
          child: Padding(
            padding: EdgeInsets.only(
              left: leftInset + edgePadding,
              right: rightInset + edgePadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth),
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _buildJobsTab() {
    final mediaQuery = MediaQuery.of(context);
    final jobs = _pagedJobs;
    final totalPages = (_filteredJobs.length / _pageSize).ceil().clamp(1, 999);
    final bottomSystemInset = math.max(
      mediaQuery.viewPadding.bottom,
      math.max(
        mediaQuery.padding.bottom,
        mediaQuery.systemGestureInsets.bottom,
      ),
    );
    final safeBottomInset = math.max(
      mediaQuery.padding.bottom,
      bottomSystemInset,
    );
    final listBottomSpacer = safeBottomInset + 56.0;
    final listBottomPadding = safeBottomInset + 24.0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            if (_profileType == ProfileType.jobSeeker)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: 'Search jobs',
                        hintText: 'Flutter, remote, analyst...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _query = '';
                                    _page = 1;
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _query = value.trim();
                          _page = 1;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _fetchJobs,
                    child: const Text('Refresh'),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_filteredJobs.isEmpty)
              Expanded(
                child: _profileType == ProfileType.employer
                    ? ListView(
                        padding: EdgeInsets.only(
                          bottom: 16 + listBottomPadding,
                        ),
                        children: [
                          Card(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Post your first job listing',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Your listed jobs will appear here once you publish a role. Create your first listing to start receiving applicants.',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 12),
                                  Builder(
                                    builder: (buttonContext) =>
                                        FilledButton.icon(
                                          onPressed: () {
                                            DefaultTabController.of(
                                              buttonContext,
                                            ).animateTo(2);
                                          },
                                          icon: const Icon(
                                            Icons.add_circle_outline,
                                          ),
                                          label: const Text(
                                            'Add First Job Listing',
                                          ),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Text(
                          'No results for "$_query"',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
              )
            else
              Expanded(
                child: Column(
                  children: [
                    if (_loadingError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _loadingError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.only(
                          bottom: 16 + listBottomPadding,
                        ),
                        itemCount: jobs.length + 2,
                        itemBuilder: (context, index) {
                          if (index == jobs.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Page $_page / $totalPages'),
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: _page > 1
                                            ? () => _changePage(-1)
                                            : null,
                                        icon: const Icon(Icons.chevron_left),
                                      ),
                                      IconButton(
                                        onPressed: _page < totalPages
                                            ? () => _changePage(1)
                                            : null,
                                        icon: const Icon(Icons.chevron_right),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }
                          if (index == jobs.length + 1) {
                            return SizedBox(height: listBottomSpacer);
                          }
                          final job = jobs[index];
                          final isFav = _favoriteIds.contains(job.id);
                          final timelineText = _buildJobTimelineText(job);
                          final deadlineText = job.deadlineDate != null
                              ? _formatYmd(job.deadlineDate!.toLocal())
                              : null;
                          final isNarrowCard =
                              MediaQuery.sizeOf(context).width < 430;
                          final actionButtonSize = isNarrowCard ? 36.0 : 42.0;
                          final actionButtonPadding = EdgeInsets.all(
                            isNarrowCard ? 6 : 8,
                          );
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _openDetails(job),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    LayoutBuilder(
                                      builder: (context, cardConstraints) {
                                        final isCompactHeader =
                                            cardConstraints.maxWidth < 640;
                                        Widget? matchBadge;
                                        if (_profileType ==
                                            ProfileType.jobSeeker) {
                                          final match = _evaluateJobMatch(job);
                                          Color badgeColor = Colors.red;
                                          String badgeIcon = '✗';
                                          if (match.matchPercentage >= 80) {
                                            badgeColor = Colors.green;
                                            badgeIcon = '✓';
                                          } else if (match.matchPercentage >=
                                              50) {
                                            badgeColor = Colors.orange;
                                            badgeIcon = '⚠';
                                          }
                                          final missingText = match
                                              .missingRequirements
                                              .take(2)
                                              .join(', ');
                                          matchBadge = Tooltip(
                                            message: match.matchPercentage >= 80
                                                ? 'Strong match. You meet all required criteria.'
                                                : 'Potential fit. Missing required: $missingText',
                                            child: Container(
                                              margin: EdgeInsets.only(
                                                left: isCompactHeader ? 0 : 8,
                                                top: isCompactHeader ? 8 : 0,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: badgeColor,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                '$badgeIcon ${match.matchPercentage}%',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          );
                                        }

                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Padding(
                                                  padding: EdgeInsets.only(
                                                    top: 2,
                                                  ),
                                                  child: Icon(Icons.work),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        job.title,
                                                        style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        '${job.company} • ${job.location}',
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(job.type),
                                                      if (deadlineText !=
                                                          null) ...[
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        Container(
                                                          width:
                                                              double.infinity,
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 10,
                                                                vertical: 8,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: Colors
                                                                .orange
                                                                .shade50,
                                                            border: Border.all(
                                                              color: Colors
                                                                  .orange
                                                                  .shade200,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  10,
                                                                ),
                                                          ),
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                'Application Deadline',
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color: Colors
                                                                      .orange
                                                                      .shade900,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                height: 2,
                                                              ),
                                                              Text(
                                                                deadlineText,
                                                                style: TextStyle(
                                                                  fontSize: 15,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color: Colors
                                                                      .orange
                                                                      .shade900,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                      if (timelineText
                                                          .isNotEmpty) ...[
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        Text(
                                                          timelineText,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: Colors
                                                                .grey
                                                                .shade600,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                if (!isCompactHeader &&
                                                    matchBadge != null)
                                                  matchBadge,
                                              ],
                                            ),
                                            if (isCompactHeader &&
                                                matchBadge != null)
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: matchBadge,
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      job.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Wrap(
                                        spacing: isNarrowCard ? 2 : 4,
                                        children: [
                                          if (_profileType ==
                                              ProfileType.jobSeeker)
                                            IconButton(
                                              constraints:
                                                  BoxConstraints.tightFor(
                                                    width: actionButtonSize,
                                                    height: actionButtonSize,
                                                  ),
                                              padding: actionButtonPadding,
                                              visualDensity: isNarrowCard
                                                  ? VisualDensity.compact
                                                  : VisualDensity.standard,
                                              icon: Icon(
                                                isFav
                                                    ? Icons.star
                                                    : Icons.star_border,
                                                color: isFav
                                                    ? Colors.amber
                                                    : null,
                                              ),
                                              onPressed: () =>
                                                  _toggleFavorite(job),
                                            ),
                                          if (_profileType ==
                                              ProfileType.jobSeeker)
                                            IconButton(
                                              constraints:
                                                  BoxConstraints.tightFor(
                                                    width: actionButtonSize,
                                                    height: actionButtonSize,
                                                  ),
                                              padding: actionButtonPadding,
                                              visualDensity: isNarrowCard
                                                  ? VisualDensity.compact
                                                  : VisualDensity.standard,
                                              icon: Icon(
                                                _hasApplied(job.id)
                                                    ? Icons.check_circle
                                                    : Icons.send,
                                                color: _hasApplied(job.id)
                                                    ? Colors.green
                                                    : null,
                                              ),
                                              tooltip: _hasApplied(job.id)
                                                  ? 'Applied'
                                                  : 'Apply',
                                              onPressed: _hasApplied(job.id)
                                                  ? null
                                                  : () =>
                                                      _handleApplyTap(job),
                                            ),
                                          if (_canEditJob(job))
                                            OutlinedButton.icon(
                                              onPressed: () => _editJob(job),
                                              icon: const Icon(Icons.edit),
                                              label: const Text('Edit'),
                                            ),
                                          if (_canDeleteJob(job))
                                            OutlinedButton.icon(
                                              onPressed: () => _removeJob(job),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                              ),
                                              label: const Text('Delete'),
                                            ),
                                          if (_profileType ==
                                              ProfileType.employer)
                                            OutlinedButton.icon(
                                              onPressed: () =>
                                                  _saveJobAsTemplate(job),
                                              icon: const Icon(
                                                Icons.bookmark_add_outlined,
                                              ),
                                              label: const Text(
                                                'Save as Template',
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyApplicationsTab() {
    if (_myApplications.isEmpty) {
      return const Center(
        child: Text('No applications yet. Browse jobs and hit Apply!'),
      );
    }

    final sorted = [..._myApplications]
      ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final app = sorted[index];
        final job = _allJobs.firstWhere(
          (j) => j.id == app.jobId,
          orElse: () => JobListing(
            id: app.jobId,
            title: 'Unknown Job',
            company: 'Unknown',
            location: '',
            type: '',
            crewRole: '',
            faaRules: const [],
            description: '',
            faaCertificates: const [],
            flightExperience: const [],
            aircraftFlown: const [],
          ),
        );

        final Color badgeColor;
        final String matchLabel;
        if (app.isPerfectMatch) {
          badgeColor = Colors.green.shade100;
          matchLabel = '🟢 ${app.matchPercentage}% Perfect Match';
        } else if (app.isGoodMatch) {
          badgeColor = Colors.yellow.shade100;
          matchLabel = '🟡 ${app.matchPercentage}% Good Match';
        } else {
          badgeColor = Colors.red.shade100;
          matchLabel = '🔴 ${app.matchPercentage}% Stretch Match';
        }

        final statusLabel = switch (app.status) {
          'reviewed' => 'Reviewed by employer',
          'interested' => '⭐ Employer interested',
          'rejected' => 'Not moving forward',
          _ => 'Submitted',
        };

        final feedback = _getFeedbackForApplication(app.id);
        final hasFeedback = feedback != null;

        final feedbackIcon = switch (feedback?.feedbackType) {
          ApplicationFeedback.feedbackTypeInterested => '✅',
          ApplicationFeedback.feedbackTypeNotFit => '❌',
          _ => 'ℹ️',
        };

        final feedbackColor = switch (feedback?.feedbackType) {
          ApplicationFeedback.feedbackTypeInterested => Colors.green.shade50,
          ApplicationFeedback.feedbackTypeNotFit => Colors.red.shade50,
          _ => Colors.blue.shade50,
        };

        final feedbackBorderColor = switch (feedback?.feedbackType) {
          ApplicationFeedback.feedbackTypeInterested => Colors.green.shade200,
          ApplicationFeedback.feedbackTypeNotFit => Colors.red.shade200,
          _ => Colors.blue.shade200,
        };

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        job.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (hasFeedback)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '[!] Feedback',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${job.company} • ${job.location}'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        matchLabel,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusLabel,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Applied ${_formatYmd(app.appliedAt.toLocal())}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                // Feedback section
                if (hasFeedback) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: feedbackColor,
                      border: Border.all(color: feedbackBorderColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$feedbackIcon Employer Feedback',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(feedback.message),
                        const SizedBox(height: 4),
                        Text(
                          _formatYmd(feedback.sentAt.toLocal()),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmployerApplicationsTab() {
    final allApplications = _employerApplications;
    final filterOptions = const [
      ('all', 'All'),
      ('applied', 'Submitted'),
      ('reviewed', 'Reviewed'),
      ('interested', 'Interested'),
      ('rejected', 'Not Moving Forward'),
    ];
    final matchFilterOptions = const [
      ('all', 'All'),
      ('perfect', '🟢 90%+'),
      ('good', '🟡 70–89%'),
      ('stretch', '🔴 <70%'),
    ];
    final sortOptions = const [
      ('newest', 'Newest'),
      ('highest_match', 'Highest Match'),
      ('status', 'Status'),
    ];
    final countsByStatus = {
      'applied': allApplications.where((app) => app.status == 'applied').length,
      'reviewed': allApplications
          .where((app) => app.status == 'reviewed')
          .length,
      'interested': allApplications
          .where((app) => app.status == 'interested')
          .length,
      'rejected': allApplications.where((app) => app.status == 'rejected').length,
    };
    final perfectCount =
        allApplications.where((app) => app.isPerfectMatch).length;
    final goodCount = allApplications.where((app) => app.isGoodMatch).length;
    final stretchCount =
        allApplications.where((app) => app.isStretchMatch).length;

    // Apply status filter
    final statusFiltered = _selectedEmployerApplicationFilter == 'all'
        ? allApplications
        : allApplications
              .where((app) => app.status == _selectedEmployerApplicationFilter)
              .toList();

    // Apply match % filter
    final filteredApplications = switch (_selectedMatchFilter) {
      'perfect' => statusFiltered
          .where((app) => app.isPerfectMatch)
          .toList(),
      'good' => statusFiltered
          .where((app) => app.isGoodMatch)
          .toList(),
      'stretch' => statusFiltered
          .where((app) => app.isStretchMatch)
          .toList(),
      _ => statusFiltered,
    };

    final sorted = [...filteredApplications]
      ..sort((a, b) {
        if (_selectedEmployerApplicationSort == 'highest_match') {
          final matchCompare = b.matchPercentage.compareTo(a.matchPercentage);
          if (matchCompare != 0) {
            return matchCompare;
          }
          return b.appliedAt.compareTo(a.appliedAt);
        }

        if (_selectedEmployerApplicationSort == 'status') {
          int statusRank(String status) {
            switch (status) {
              case 'applied':
                return 0;
              case 'reviewed':
                return 1;
              case 'interested':
                return 2;
              case 'rejected':
                return 3;
              default:
                return 4;
            }
          }

          final statusCompare =
              statusRank(a.status).compareTo(statusRank(b.status));
          if (statusCompare != 0) {
            return statusCompare;
          }
          return b.appliedAt.compareTo(a.appliedAt);
        }

        return b.appliedAt.compareTo(a.appliedAt);
      });

    if (allApplications.isEmpty) {
      return const Center(
        child: Text('No submitted applications yet for this employer.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: sorted.isEmpty ? 2 : sorted.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick stats
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    border: Border.all(color: Colors.blueGrey.shade100),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      Text(
                        '🟢 $perfectCount perfect',
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text(
                        '🟡 $goodCount good',
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text(
                        '🔴 $stretchCount stretch',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                // Status filter
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: filterOptions.map((option) {
                    final key = option.$1;
                    final label = option.$2;
                    final count = key == 'all'
                        ? allApplications.length
                        : (countsByStatus[key] ?? 0);
                    return ChoiceChip(
                      label: Text('$label ($count)'),
                      selected: _selectedEmployerApplicationFilter == key,
                      onSelected: (_) {
                        setState(() {
                          _selectedEmployerApplicationFilter = key;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                // Match % filter
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Match:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    ...matchFilterOptions.map((option) {
                      final key = option.$1;
                      final label = option.$2;
                      return ChoiceChip(
                        label: Text(label),
                        selected: _selectedMatchFilter == key,
                        onSelected: (_) {
                          setState(() {
                            _selectedMatchFilter = key;
                          });
                        },
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 8),
                // Sort
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Sort:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    ...sortOptions.map((option) {
                      final key = option.$1;
                      final label = option.$2;
                      return ChoiceChip(
                        label: Text(label),
                        selected: _selectedEmployerApplicationSort == key,
                        onSelected: (_) {
                          setState(() {
                            _selectedEmployerApplicationSort = key;
                          });
                        },
                      );
                    }),
                  ],
                ),
              ],
            ),
          );
        }

        if (sorted.isEmpty) {
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No applications match the selected filters.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          );
        }

        final app = sorted[index - 1];
        final job = _allJobs.firstWhere(
          (j) => j.id == app.jobId,
          orElse: () => JobListing(
            id: app.jobId,
            title: 'Unknown Job',
            company: _currentEmployer.companyName,
            location: '',
            type: '',
            crewRole: '',
            faaRules: const [],
            description: '',
            faaCertificates: const [],
            flightExperience: const [],
            aircraftFlown: const [],
          ),
        );

        final statusLabel = switch (app.status) {
          'reviewed' => 'Reviewed',
          'interested' => 'Interested',
          'rejected' => 'Not moving forward',
          _ => 'Submitted',
        };

        final statusColor = switch (app.status) {
          'reviewed' => Colors.blueGrey.shade100,
          'interested' => Colors.green.shade100,
          'rejected' => Colors.red.shade100,
          _ => Colors.orange.shade100,
        };

        final Color matchBadgeColor;
        final String matchBadgeLabel;
        if (app.isPerfectMatch) {
          matchBadgeColor = Colors.green.shade100;
          matchBadgeLabel = '🟢 ${app.matchPercentage}%';
        } else if (app.isGoodMatch) {
          matchBadgeColor = Colors.yellow.shade100;
          matchBadgeLabel = '🟡 ${app.matchPercentage}%';
        } else {
          matchBadgeColor = Colors.red.shade100;
          matchBadgeLabel = '🔴 ${app.matchPercentage}%';
        }

        final appFeedback = _getFeedbackForApplication(app.id);
        final hasFeedback = appFeedback != null;
        final isAutoRejected =
            app.status == 'rejected' &&
            hasFeedback &&
            appFeedback.isAutoGenerated;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        job.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (hasFeedback && !isAutoRejected)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '[!]',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (isAutoRejected) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '[✓] Auto-rejected',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  app.applicantName.trim().isNotEmpty
                      ? app.applicantName
                      : 'Applicant ID: ${app.jobSeekerId}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  app.applicantEmail.trim().isNotEmpty
                      ? app.applicantEmail
                      : 'Email not provided',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 2),
                Text(
                  _applicantLocation(app),
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    border: Border.all(color: Colors.blueGrey.shade100),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profile Snapshot',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.blueGrey.shade800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('Match Score: ${app.matchPercentage}%'),
                      const SizedBox(height: 4),
                      Text(
                        'Total Flight Hours: ${app.applicantTotalFlightHours}',
                      ),
                      if (app.applicantFaaCertificates.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: app.applicantFaaCertificates
                              .take(4)
                              .map((cert) => Chip(label: Text(cert)))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: matchBadgeColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(matchBadgeLabel),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(statusLabel),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Applied ${_formatYmd(app.appliedAt.toLocal())}',
                      ),
                    ),
                  ],
                ),
                if (app.coverLetter.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Cover Letter: ${app.coverLetter.trim()}',
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _openApplicantDetails(app, job),
                      icon: const Icon(Icons.person_outline),
                      label: const Text('View & Send Feedback'),
                    ),
                    OutlinedButton(
                      onPressed: app.status == 'reviewed'
                          ? null
                          : () => _updateApplicationStatus(app, 'reviewed'),
                      child: const Text('Mark Reviewed'),
                    ),
                    OutlinedButton(
                      onPressed: app.status == 'interested'
                          ? null
                          : () => _updateApplicationStatus(app, 'interested'),
                      child: const Text('Interested'),
                    ),
                    OutlinedButton(
                      onPressed: app.status == 'rejected'
                          ? null
                          : () => _updateApplicationStatus(app, 'rejected'),
                      child: const Text('Not Moving Forward'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchTab() {
    return const Center(
      child: Text(
        'Search placeholder - eventually show filters, saved searches, and suggestions.',
      ),
    );
  }

  Widget _buildFavoritesTab() {
    final favoriteJobs = _allJobs
        .where((job) => _favoriteIds.contains(job.id))
        .toList();
    if (favoriteJobs.isEmpty) {
      return const Center(child: Text('No favorite jobs yet.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: favoriteJobs.length,
      itemBuilder: (context, index) {
        final job = favoriteJobs[index];
        final deadlineText = job.deadlineDate != null
            ? _formatYmd(job.deadlineDate!.toLocal())
            : null;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openDetails(job),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${job.company} • ${job.location}'),
                  if (deadlineText != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        border: Border.all(color: Colors.orange.shade200),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Application Deadline',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange.shade900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            deadlineText,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Returns a controller whose text is synced to [value] only in read-only
  // mode, preventing the cascade from clobbering live user input.
  TextEditingController _employerCtrl(
    TextEditingController ctrl,
    String value,
  ) {
    if (!_employerProfileEditing) ctrl.text = value;
    return ctrl;
  }

  String _stateProvinceLabel(String name) {
    final abbreviation = _stateProvinceAbbreviations[name];
    if (abbreviation == null || abbreviation.isEmpty) {
      return name;
    }
    return '$abbreviation - $name';
  }

  String? _normalizeCountryValue(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized == 'usa' ||
        normalized == 'us' ||
        normalized == 'united states' ||
        normalized == 'united states of america') {
      return 'USA';
    }
    if (normalized == 'canada' || normalized == 'ca') {
      return 'Canada';
    }
    return null;
  }

  List<String> _stateProvinceOptionsForCountry(String rawCountry) {
    switch (_normalizeCountryValue(rawCountry)) {
      case 'USA':
        return _usStateOptions;
      case 'Canada':
        return _canadaProvinceOptions;
      default:
        return _stateProvinceOptions;
    }
  }

  Widget _buildEmployerCountryField() {
    final controller = _employerCtrl(
      _employerCountryController,
      _currentEmployer.headquartersCountry,
    );

    if (!_employerProfileEditing) {
      return TextField(
        controller: controller,
        readOnly: true,
        decoration: const InputDecoration(labelText: 'Country'),
      );
    }

    final normalizedCountry = _normalizeCountryValue(controller.text);
    return DropdownButtonFormField<String>(
      initialValue: normalizedCountry,
      decoration: const InputDecoration(labelText: 'Country'),
      items: _countryOptions
          .map(
            (country) => DropdownMenuItem(value: country, child: Text(country)),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) {
          return;
        }
        setState(() {
          _employerCountryController.text = value;
          final allowed = _stateProvinceOptionsForCountry(value);
          if (!allowed.contains(_employerStateController.text)) {
            _employerStateController.clear();
          }
        });
      },
    );
  }

  Widget _buildEmployerStateField() {
    final controller = _employerCtrl(
      _employerStateController,
      _currentEmployer.headquartersState,
    );
    final countryKey = _normalizeCountryValue(_employerCountryController.text);

    if (!_employerProfileEditing) {
      return TextField(
        controller: controller,
        readOnly: true,
        decoration: const InputDecoration(labelText: 'State / Province'),
      );
    }

    return Autocomplete<String>(
      key: ValueKey('employer-state-${countryKey ?? 'any'}'),
      initialValue: TextEditingValue(text: controller.text),
      optionsBuilder: (textEditingValue) {
        final scopedOptions = _stateProvinceOptionsForCountry(
          _employerCountryController.text,
        );
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) {
          return scopedOptions;
        }

        final exactAbbreviationMatches = _stateProvinceAbbreviations.entries
            .where(
              (entry) =>
                  entry.value.toLowerCase() == query &&
                  scopedOptions.contains(entry.key),
            )
            .map((entry) => entry.key)
            .toList();
        if (exactAbbreviationMatches.isNotEmpty) {
          return exactAbbreviationMatches;
        }

        return scopedOptions.where((option) {
          final optionLower = option.toLowerCase();
          final abbreviation = (_stateProvinceAbbreviations[option] ?? '')
              .toLowerCase();
          final words = optionLower.split(RegExp(r'[\s-]+'));

          return optionLower.startsWith(query) ||
              words.any((word) => word.startsWith(query)) ||
              abbreviation.startsWith(query);
        });
      },
      onSelected: (selection) {
        _employerStateController.text = selection;
      },
      optionsViewBuilder: (context, onSelected, options) {
        final optionList = options.toList(growable: false);
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, minWidth: 280),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: optionList.length,
                itemBuilder: (context, index) {
                  final option = optionList[index];
                  return ListTile(
                    dense: true,
                    title: Text(_stateProvinceLabel(option)),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
            if (textEditingController.text != _employerStateController.text) {
              textEditingController.value = TextEditingValue(
                text: _employerStateController.text,
                selection: TextSelection.collapsed(
                  offset: _employerStateController.text.length,
                ),
              );
            }
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              decoration: const InputDecoration(labelText: 'State / Province'),
              onChanged: (value) {
                _employerStateController.text = value;
              },
            );
          },
    );
  }

  Widget _buildCompanyProfileTab() {
    final employer = _currentEmployer;
    final companyListingCount = _visibleJobs.length;
    final headquartersLine2 = employer.headquartersAddressLine2.trim();
    final websiteValue = employer.website.trim();
    final descriptionValue = employer.companyDescription.trim();
    final locationParts = [
      employer.headquartersCity.trim(),
      employer.headquartersState.trim(),
      employer.headquartersCountry.trim(),
    ].where((part) => part.isNotEmpty).toList();
    final locationHeadline = locationParts.isEmpty
        ? 'Headquarters location not set'
        : locationParts.join(' • ');
    final locationQueryParts = [
      employer.headquartersAddressLine1.trim(),
      headquartersLine2,
      employer.headquartersCity.trim(),
      employer.headquartersState.trim(),
      employer.headquartersPostalCode.trim(),
      employer.headquartersCountry.trim(),
    ].where((part) => part.isNotEmpty).toList();
    final locationQuery = locationQueryParts.join(', ');
    final canOpenLocation = locationQuery.isNotEmpty;
    final companyBenefits = employer.companyBenefits;
    final bannerUrl = employer.companyBannerUrl.trim();
    final logoUrl = employer.companyLogoUrl.trim();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                _buildCompanyBannerPreview(
                  _employerProfileEditing
                      ? _employerBannerUrlController.text
                      : bannerUrl,
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 10),
                // Employer Switcher (if multiple employers exist)
                if (_employerProfiles.length > 1) ...[
                  const Text(
                    'Switch Employer:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _employerProfiles.map((employer) {
                      final isActive = employer.id == _currentEmployer.id;
                      return ChoiceChip(
                        label: Text(employer.companyName),
                        selected: isActive,
                        onSelected: (_) => _switchEmployer(employer),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                ],
                // Current Company Info
                const Text(
                  'Company Information',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (_employerProfileEditing) ...[
                  TextField(
                    controller: _employerCtrl(
                      _employerCompanyNameController,
                      _currentEmployer.companyName,
                    ),
                    readOnly: !_employerProfileEditing,
                    decoration: const InputDecoration(
                      labelText: 'Company Name',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _employerCtrl(
                      _employerAddressLine1Controller,
                      _currentEmployer.headquartersAddressLine1,
                    ),
                    readOnly: !_employerProfileEditing,
                    decoration: const InputDecoration(
                      labelText: 'Headquarters Address Line 1',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _employerCtrl(
                      _employerAddressLine2Controller,
                      _currentEmployer.headquartersAddressLine2,
                    ),
                    readOnly: !_employerProfileEditing,
                    decoration: const InputDecoration(
                      labelText: 'Headquarters Address Line 2 (Optional)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _employerCtrl(
                            _employerCityController,
                            _currentEmployer.headquartersCity,
                          ),
                          readOnly: !_employerProfileEditing,
                          decoration: const InputDecoration(labelText: 'City'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _buildEmployerStateField()),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _employerCtrl(
                            _employerPostalCodeController,
                            _currentEmployer.headquartersPostalCode,
                          ),
                          readOnly: !_employerProfileEditing,
                          decoration: const InputDecoration(
                            labelText: 'Postal Code',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _buildEmployerCountryField()),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _uploadingEmployerBannerImage
                            ? null
                            : _pickEmployerBannerImageFile,
                        icon: _uploadingEmployerBannerImage
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_file_outlined),
                        label: Text(
                          _uploadingEmployerBannerImage
                              ? 'Uploading Banner...'
                              : 'Upload Banner Image',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _uploadingEmployerBannerImage ||
                                _employerBannerUrlController.text.trim().isEmpty
                            ? null
                            : _removeEmployerBannerImage,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove Banner'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _uploadingEmployerLogoImage
                            ? null
                            : _pickEmployerLogoImageFile,
                        icon: _uploadingEmployerLogoImage
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_file_outlined),
                        label: Text(
                          _uploadingEmployerLogoImage
                              ? 'Uploading Logo...'
                              : 'Upload Logo Image',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _uploadingEmployerLogoImage ||
                                _employerLogoUrlController.text.trim().isEmpty
                            ? null
                            : _removeEmployerLogoImage,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove Logo'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _employerCtrl(
                      _employerWebsiteController,
                      _currentEmployer.website,
                    ),
                    readOnly: !_employerProfileEditing,
                    decoration: const InputDecoration(
                      labelText: 'Company Website',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _employerCtrl(
                      _employerContactNameController,
                      _currentEmployer.contactName,
                    ),
                    readOnly: !_employerProfileEditing,
                    decoration: const InputDecoration(
                      labelText: 'Contact Name / Department',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _employerCtrl(
                      _employerContactEmailController,
                      _currentEmployer.contactEmail,
                    ),
                    readOnly: !_employerProfileEditing,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Hiring Contact Email',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _employerCtrl(
                      _employerContactPhoneController,
                      _formatPhoneNumber(_currentEmployer.contactPhone),
                    ),
                    readOnly: !_employerProfileEditing,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      _PhoneNumberTextInputFormatter(),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Hiring Contact Phone',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _employerCtrl(
                      _employerDescriptionController,
                      _currentEmployer.companyDescription,
                    ),
                    readOnly: !_employerProfileEditing,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Company Description',
                      hintText:
                          'Briefly describe your operation and hiring needs.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Company Benefits',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._companyBenefitOptions.map((benefit) {
                          final isSelected = _selectedEmployerBenefits.contains(
                            benefit,
                          );
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(benefit),
                            value: isSelected,
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedEmployerBenefits.add(benefit);
                                } else {
                                  _selectedEmployerBenefits.remove(benefit);
                                }
                              });
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildCompanyLogoPreview(logoUrl, size: 96),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.business,
                                      size: 18,
                                      color: Colors.blueGrey.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          employer.companyName.trim().isNotEmpty
                                              ? employer.companyName.trim()
                                              : 'Company Name Not Set',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Company profile overview',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: canOpenLocation
                                  ? () => _openLocationInMaps(locationQuery)
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _buildInlineInfoItem(
                                        Icons.location_on_outlined,
                                        locationHeadline,
                                      ),
                                    ),
                                    if (canOpenLocation) ...[
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.open_in_new,
                                        size: 16,
                                        color: Colors.blueGrey.shade500,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        _buildProfileSummaryRow(
                          'Address Line 1',
                          employer.headquartersAddressLine1,
                        ),
                        _buildProfileSummaryRow(
                          'Address Line 2',
                          _summaryValue(headquartersLine2),
                        ),
                        _buildProfileSummaryRow(
                          'City',
                          employer.headquartersCity,
                        ),
                        _buildProfileSummaryRow(
                          'State / Province',
                          employer.headquartersState,
                        ),
                        _buildProfileSummaryRow(
                          'Postal Code',
                          employer.headquartersPostalCode,
                        ),
                        _buildProfileSummaryRow(
                          'Country',
                          employer.headquartersCountry,
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Builder(
                      builder: (tabContext) => OutlinedButton.icon(
                        onPressed: () =>
                            DefaultTabController.of(tabContext).animateTo(1),
                        icon: const Icon(Icons.list_alt_outlined),
                        label: Text(
                          'See All Listings ($companyListingCount)',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSummarySectionCard(
                    title: 'Hiring Contact',
                    subtitle: 'How candidates can reach your team',
                    icon: Icons.contact_mail,
                    child: Column(
                      children: [
                        _buildProfileSummaryRow(
                          'Contact Name / Department',
                          employer.contactName,
                        ),
                        _buildProfileSummaryRow('Email', employer.contactEmail),
                        _buildProfileSummaryRow(
                          'Phone',
                          _formatPhoneNumber(employer.contactPhone),
                        ),
                        _buildWebsiteSummaryRow(websiteValue),
                      ],
                    ),
                  ),
                  _buildSummarySectionCard(
                    title: 'About The Company',
                    subtitle: 'What candidates should know',
                    icon: Icons.description,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          descriptionValue.isEmpty
                              ? 'Not provided'
                              : descriptionValue,
                          style: TextStyle(
                            fontStyle: descriptionValue.isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                            color: descriptionValue.isEmpty
                                ? Colors.grey.shade600
                                : null,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Company Benefits',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        if (companyBenefits.isEmpty)
                          Text(
                            'Not provided',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey.shade600,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: companyBenefits
                                .map((benefit) => Chip(label: Text(benefit)))
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(top: BorderSide(color: Colors.grey.shade300)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 760;
              if (!_employerProfileEditing) {
                return Center(
                  child: OutlinedButton.icon(
                    onPressed: _startEditingEmployerProfile,
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit'),
                  ),
                );
              }

              final saveButton = OutlinedButton.icon(
                onPressed: () async {
                  final contactEmail = _employerContactEmailController.text
                      .trim();
                  final contactPhone = _formatPhoneNumber(
                    _employerContactPhoneController.text.trim(),
                  );

                  if (contactEmail.isEmpty && contactPhone.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Provide either a hiring contact email or phone number.',
                        ),
                      ),
                    );
                    return;
                  }

                  final previousEmployer = _currentEmployer;

                  final updated = EmployerProfile(
                    id: _currentEmployer.id,
                    companyName: _employerCompanyNameController.text.trim(),
                    headquartersAddressLine1: _employerAddressLine1Controller
                        .text
                        .trim(),
                    headquartersAddressLine2: _employerAddressLine2Controller
                        .text
                        .trim(),
                    headquartersCity: _employerCityController.text.trim(),
                    headquartersState: _employerStateController.text.trim(),
                    headquartersPostalCode: _employerPostalCodeController.text
                        .trim(),
                    headquartersCountry: _employerCountryController.text.trim(),
                    companyBannerUrl: _normalizeExternalUrl(
                      _employerBannerUrlController.text,
                    ),
                    companyLogoUrl: _normalizeExternalUrl(
                      _employerLogoUrlController.text,
                    ),
                    website: _employerWebsiteController.text.trim(),
                    contactName: _employerContactNameController.text.trim(),
                    contactEmail: contactEmail,
                    contactPhone: contactPhone,
                    companyDescription: _employerDescriptionController.text
                        .trim(),
                    companyBenefits: _selectedEmployerBenefits.toList()..sort(),
                  );
                  _updateEmployer(updated);
                  await _cleanupReplacedEmployerImages(
                    previous: previousEmployer,
                    updated: updated,
                  );
                  if (!mounted || !context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Company profile saved.')),
                  );
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Changes'),
              );

              if (isCompact) {
                return Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => _employerProfileEditing = false),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel'),
                    ),
                    saveButton,
                  ],
                );
              }

              return Row(
                children: [
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () =>
                        setState(() => _employerProfileEditing = false),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  saveButton,
                  const Spacer(),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Job Seeker Profile',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openEditPersonalInformation,
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Edit Personal Information'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openEditQualifications,
                        icon: const Icon(Icons.tune, size: 18),
                        label: const Text('Edit Qualifications'),
                      ),
                    ),
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Job Seeker Profile',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _openEditPersonalInformation,
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Edit Personal Information'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openEditQualifications,
                        icon: const Icon(Icons.tune, size: 18),
                        label: const Text('Edit Qualifications'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSummarySectionCard(
                title: 'Personal Information',
                subtitle: 'Account details and contact location',
                icon: Icons.person_outline,
                child: Column(
                  children: [
                    _buildProfileSummaryRow(
                      'First Name',
                      _jobSeekerProfile.firstName,
                    ),
                    _buildProfileSummaryRow(
                      'Last Name',
                      _jobSeekerProfile.lastName,
                    ),
                    _buildProfileSummaryRow(
                      'Email',
                      _resolvedJobSeekerEmail(_jobSeekerProfile),
                    ),
                    _buildProfileSummaryRow(
                      'Phone',
                      _formatPhoneNumber(_jobSeekerProfile.phone),
                    ),
                    _buildProfileSummaryRow('City', _jobSeekerProfile.city),
                    _buildProfileSummaryRow(
                      'State / Province',
                      _jobSeekerProfile.stateOrProvince,
                    ),
                    _buildProfileSummaryRow(
                      'Country',
                      _jobSeekerProfile.country,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSummarySectionCard(
                title: 'Certificates and Flight Hours',
                subtitle: 'Your qualifications used for job matching',
                icon: Icons.flight_takeoff,
                trailing: TextButton.icon(
                  onPressed: _openEditQualifications,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Edit'),
                ),
                child: Column(
                  children: [
                    _buildChipSummaryCard(
                      title: 'FAA Certificates',
                      items: _selectedJobSeekerCertificates(_jobSeekerProfile),
                      emptyText: 'No FAA certificates selected',
                    ),
                    _buildChipSummaryCard(
                      title: 'Ratings',
                      items: _selectedJobSeekerRatings(_jobSeekerProfile),
                      emptyText: 'No ratings selected',
                    ),
                    _buildChipSummaryCard(
                      title: 'Type Ratings',
                      items: _jobSeekerProfile.typeRatings,
                      emptyText: 'No type ratings added',
                    ),
                    _buildChipSummaryCard(
                      title: 'Flight Hours',
                      items: _hoursSummaryItems(
                        options: _availableEmployerFlightHours,
                        selectedTypes: _jobSeekerProfile.flightHoursTypes,
                        hours: _jobSeekerProfile.flightHours,
                      ),
                      emptyText: 'No flight hour categories selected',
                    ),
                    _buildChipSummaryCard(
                      title: 'Instructor Hours',
                      items: _hoursSummaryItems(
                        options: _availableInstructorHours,
                        selectedTypes: _jobSeekerProfile.flightHoursTypes,
                        hours: _jobSeekerProfile.flightHours,
                      ),
                      emptyText: 'No instructor hour categories selected',
                    ),
                    _buildChipSummaryCard(
                      title: 'Specialty Flight Hours',
                      items: _hoursSummaryItems(
                        options: _availableSpecialtyExperience,
                        selectedTypes: _jobSeekerProfile.specialtyFlightHours,
                        hours: _jobSeekerProfile.specialtyFlightHoursMap,
                      ),
                      emptyText: 'No specialty experience selected',
                    ),
                    _buildChipSummaryCard(
                      title: 'Aircraft',
                      items: _jobSeekerProfile.aircraftFlown,
                      emptyText: 'No aircraft added',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildHoursRequirementSection({
    required String title,
    required List<String> options,
    required Map<String, int> selectedHours,
    required Set<String> preferredHours,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...options.map((option) {
            final isSelected = selectedHours.containsKey(option);
            final isPreferred = preferredHours.contains(option);
            final hours = selectedHours[option] ?? 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  title: Text(option),
                  value: isSelected,
                  onChanged: (bool? selected) {
                    setState(() {
                      if (selected == true) {
                        selectedHours.putIfAbsent(option, () => 0);
                      } else {
                        selectedHours.remove(option);
                        preferredHours.remove(option);
                      }
                    });
                  },
                ),
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 8,
                    ),
                    child: Column(
                      children: [
                        TextFormField(
                          key: ValueKey('create-hours-$title-$option'),
                          keyboardType: TextInputType.number,
                          initialValue: hours > 0 ? hours.toString() : '',
                          decoration: InputDecoration(
                            labelText: 'Hours for $option',
                            hintText: '0',
                            isDense: true,
                          ),
                          onChanged: (value) {
                            final parsed = int.tryParse(value.trim()) ?? 0;
                            setState(() {
                              selectedHours[option] = parsed;
                            });
                          },
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('Mark as preferred (optional)'),
                          value: isPreferred,
                          onChanged: (bool? preferred) {
                            setState(() {
                              if (preferred == true) {
                                preferredHours.add(option);
                              } else {
                                preferredHours.remove(option);
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCreateFaaRulesCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: _availableFaaRules.map((rule) {
          return CheckboxListTile(
            title: Text(rule),
            value: _selectedFaaRules.contains(rule),
            onChanged: (bool? selected) {
              if (selected != true) {
                return;
              }
              setState(() {
                _selectedFaaRules
                  ..clear()
                  ..add(rule);
              });
            },
          );
        }).toList(),
      ),
    );
  }

  List<String> _selectedCreateRequiredFaaCertificates() {
    return _selectedFaaCertificates
        .where(_availableFaaCertificates.contains)
        .toList();
  }

  List<String> _selectedCreateInstructorCertificates() {
    return _selectedFaaCertificates
        .where(_availableInstructorCertificates.contains)
        .toList();
  }

  List<String> _selectedCreateRatings() {
    return _selectedFaaCertificates
        .where(_availableRatingSelections.contains)
        .toList();
  }

  Widget _buildCreateRequiredFaaCertsContent() {
    final hasAtp = _selectedFaaCertificates.contains(
      'Airline Transport Pilot (ATP)',
    );
    final hasCpl = _selectedFaaCertificates.contains('Commercial Pilot (CPL)');

    final allowedCertificates = _availableFaaCertificates.where((cert) {
      if (hasAtp) {
        return cert != 'Commercial Pilot (CPL)' &&
            cert != 'Instrument Rating (IFR)' &&
            cert != 'Private Pilot (PPL)';
      }
      if (hasCpl) {
        return cert != 'Private Pilot (PPL)';
      }
      return true;
    }).toList();

    final pilotCerts = [
      'Airline Transport Pilot (ATP)',
      'Commercial Pilot (CPL)',
      'Instrument Rating (IFR)',
      'Private Pilot (PPL)',
    ];
    final maintenanceCerts = [
      'Airframe & Powerplant (A&P)',
      'Inspection Authorization (IA)',
    ];
    final dispatcherCert = ['Dispatcher (DSP)'];

    return Column(
      children: [
        ...[pilotCerts, maintenanceCerts, dispatcherCert].expand((group) {
          final available = group
              .where((cert) => allowedCertificates.contains(cert))
              .toList();
          if (available.isEmpty) {
            return <Widget>[];
          }

          return [
            _buildCheckboxCard(
              options: available,
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(8),
              isSelected: (cert) => _selectedFaaCertificates.contains(cert),
              onChanged: (cert, selected) {
                setState(() {
                  if (selected) {
                    if (cert == 'Airline Transport Pilot (ATP)') {
                      _selectedFaaCertificates.removeWhere(
                        (c) =>
                            c == 'Private Pilot (PPL)' ||
                            c == 'Commercial Pilot (CPL)' ||
                            c == 'Instrument Rating (IFR)',
                      );
                    }
                    if (cert == 'Commercial Pilot (CPL)') {
                      _selectedFaaCertificates.remove('Private Pilot (PPL)');
                    }
                    _selectedFaaCertificates.add(cert);
                  } else {
                    _selectedFaaCertificates.remove(cert);
                  }
                });
              },
            ),
          ];
        }),
      ],
    );
  }

  Widget _buildCreateInstructorCertsContent() {
    return _buildCheckboxCard(
      options: _availableInstructorCertificates,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      isSelected: (cert) => _selectedFaaCertificates.contains(cert),
      onChanged: (cert, selected) {
        setState(() {
          if (selected) {
            _selectedFaaCertificates.add(cert);
          } else {
            _selectedFaaCertificates.remove(cert);
          }
        });
      },
    );
  }

  Widget _buildCreateRatingsContent() {
    const landRatings = ['Multi-Engine Land', 'Single-Engine Land'];
    const seaRatings = ['Multi-Engine Sea', 'Single-Engine Sea'];
    const tailwheelRating = ['Tailwheel Endorsement'];
    const rotorRatings = ['Rotorcraft', 'Gyroplane'];
    const otherRatings = ['Glider', 'Lighter-than-Air'];

    Widget buildRatingCard(List<String> options) {
      return _buildCheckboxCard(
        options: options,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        isSelected: (cert) => _selectedFaaCertificates.contains(cert),
        onChanged: (cert, selected) {
          setState(() {
            if (selected) {
              _selectedFaaCertificates.add(cert);
            } else {
              _selectedFaaCertificates.remove(cert);
            }
          });
        },
      );
    }

    return Column(
      children: [
        buildRatingCard(landRatings),
        buildRatingCard(seaRatings),
        buildRatingCard(tailwheelRating),
        buildRatingCard(rotorRatings),
        buildRatingCard(otherRatings),
      ],
    );
  }

  Widget _buildCreateQualificationsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Step 2 of 2: Define requirements and qualifications',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _buildExpandableRequirementSection(
          sectionKey: 'FAA Operational Scope',
          title: 'FAA Operational Scope *',
          summary: _previewSelectionSummary(
            items: _selectedFaaRules,
            emptyLabel: 'Choose one FAA operational scope.',
          ),
          count: _selectedFaaRules.length,
          initiallyExpanded: true,
          child: _buildCreateFaaRulesCard(),
        ),
        const SizedBox(height: 12),
        _buildExpandableRequirementSection(
          sectionKey: 'Required FAA Certs',
          title: 'Required FAA Certificates *',
          summary: _previewSelectionSummary(
            items: _selectedCreateRequiredFaaCertificates(),
            emptyLabel: 'Choose required FAA certificates.',
          ),
          count: _selectedCreateRequiredFaaCertificates().length,
          initiallyExpanded: true,
          child: _buildCreateRequiredFaaCertsContent(),
        ),
        _buildExpandableRequirementSection(
          sectionKey: 'Instructor Certs',
          title: 'Instructor Certificates',
          summary: _previewSelectionSummary(
            items: _selectedCreateInstructorCertificates(),
            emptyLabel: 'Choose instructor certificates as needed.',
          ),
          count: _selectedCreateInstructorCertificates().length,
          initiallyExpanded: true,
          child: _buildCreateInstructorCertsContent(),
        ),
        _buildExpandableRequirementSection(
          sectionKey: 'Ratings',
          title: 'Required Ratings *',
          summary: _previewSelectionSummary(
            items: _selectedCreateRatings(),
            emptyLabel: 'Choose rating requirements.',
          ),
          count: _selectedCreateRatings().length,
          initiallyExpanded: true,
          child: _buildCreateRatingsContent(),
        ),
        _buildExpandableRequirementSection(
          sectionKey: 'Hours Requirements',
          title: 'Hours Requirements *',
          summary: _hoursRequirementSummary(),
          count:
              _selectedFlightHours.length +
              _selectedInstructorHours.length +
              _selectedSpecialtyHours.length,
          child: Column(
            children: [
              _buildHoursRequirementSection(
                title: 'Flight Hours',
                options: _availableEmployerFlightHours,
                selectedHours: _selectedFlightHours,
                preferredHours: _preferredFlightHours,
              ),
              const SizedBox(height: 12),
              _buildHoursRequirementSection(
                title: 'Instructor Hours',
                options: _availableInstructorHours,
                selectedHours: _selectedInstructorHours,
                preferredHours: _preferredInstructorHours,
              ),
              const SizedBox(height: 12),
              _buildHoursRequirementSection(
                title: 'Specialty Hours',
                options: _availableSpecialtyExperience,
                selectedHours: _selectedSpecialtyHours,
                preferredHours: _preferredSpecialtyHours,
              ),
            ],
          ),
        ),
        _buildExpandableRequirementSection(
          sectionKey: 'Aircraft Experience',
          title: 'Aircraft Experience (Coming soon)',
          summary: _previewSelectionSummary(
            items: _splitCommaSeparatedValues(_createAircraftController.text),
            emptyLabel: 'Optional aircraft types or experience notes.',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Required Aircraft Experience (Optional)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _createAircraftController,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'Aircraft types',
                  hintText: 'Cessna 172, Boeing 737',
                  helperText: 'Comma-separated. Leave blank if not required.',
                ),
              ),
            ],
          ),
        ),
        _buildExpandableRequirementSection(
          sectionKey: 'Type Ratings',
          title: 'Type Ratings (Coming soon)',
          summary: _previewSelectionSummary(
            items: _splitCommaSeparatedValues(
              _createTypeRatingsController.text,
            ),
            emptyLabel:
                'Optional aircraft type ratings for more specific roles.',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Type Ratings Required (Optional)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _createTypeRatingsController,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'Aircraft type ratings',
                  hintText: 'Boeing 737, Embraer E-175',
                  helperText: 'Comma-separated. Leave blank if not required.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildApplicationPreferencesSection(),
      ],
    );
  }

  Widget _buildApplicationPreferencesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Application Preferences',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // Auto-reject threshold
          const Text(
            'Auto-Reject Threshold',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Checkbox(
                value: _createAutoRejectEnabled,
                onChanged: (value) {
                  setState(() {
                    _createAutoRejectEnabled = value ?? false;
                  });
                },
              ),
              const Text('Enable auto-reject at '),
              if (_createAutoRejectEnabled)
                Text(
                  '$_createAutoRejectThreshold%',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )
              else
                const Text('(disabled)'),
            ],
          ),
          if (_createAutoRejectEnabled) ...[
            Slider(
              value: _createAutoRejectThreshold.toDouble().clamp(1.0, 100.0),
              min: 1,
              max: 100,
              divisions: 20,
              label: '$_createAutoRejectThreshold%',
              onChanged: (value) {
                setState(() {
                  _createAutoRejectThreshold = value.round();
                });
              },
            ),
            Text(
              'Auto-reject applications below $_createAutoRejectThreshold% match',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Reapply window
          const Text(
            'Reapply Prevention Window',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 80,
                child: TextField(
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  controller: _createReapplyWindowDaysController,
                  onChanged: (value) {
                    final parsed = int.tryParse(value.trim());
                    if (parsed != null &&
                        parsed > 0 &&
                        parsed <= _maxReapplyWindowDays) {
                      setState(() {
                        _createReapplyWindowDays = parsed;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              const Text('days'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Job seekers can apply again after this period',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateTab() {
    return Builder(
      builder: (tabContext) => Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Create a job listing',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildCreateStepHeader(),
                  const SizedBox(height: 16),
                  if (_createJobStep == 0)
                    _buildCreateBasicsStep()
                  else
                    _buildCreateQualificationsStep(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(tabContext).colorScheme.surface,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 760;
                if (_createJobStep == 0) {
                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                _cancelCreateListingFlow(tabContext);
                              },
                              icon: const Icon(Icons.cancel_outlined),
                              label: const Text('Cancel'),
                            ),
                            if (_selectedTemplate != null)
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _renameTemplate(_selectedTemplate!),
                                icon: const Icon(
                                  Icons.drive_file_rename_outline,
                                ),
                                label: const Text('Rename Template'),
                              ),
                            if (_selectedTemplate != null)
                              OutlinedButton.icon(
                                onPressed:
                                    _updateSelectedTemplateFromCurrentForm,
                                icon: const Icon(Icons.sync),
                                label: const Text('Update Selected Template'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            if (_validateCreateBasics()) {
                              setState(() {
                                _createJobStep = 1;
                              });
                            }
                          },
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Next: Qualifications'),
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () {
                          _cancelCreateListingFlow(tabContext);
                        },
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancel'),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () {
                          if (_validateCreateBasics()) {
                            setState(() {
                              _createJobStep = 1;
                            });
                          }
                        },
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Next: Qualifications'),
                      ),
                    ],
                  );
                }

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _createJobStep = 0;
                              });
                            },
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Back to Basics'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              _cancelCreateListingFlow(tabContext);
                            },
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Cancel'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _createJobListing(tabContext),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Create Job Listing'),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _createJobStep = 0;
                        });
                      },
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to Basics'),
                    ),
                    Expanded(
                      child: Center(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _cancelCreateListingFlow(tabContext);
                          },
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Cancel'),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _createJobListing(tabContext),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Create Job Listing'),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateEditorTab(JobListingTemplate template) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit ${template.name} Template',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildCreateStepHeader(),
                const SizedBox(height: 16),
                if (_createJobStep == 0)
                  _buildCreateBasicsStep()
                else
                  _buildCreateQualificationsStep(),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(top: BorderSide(color: Colors.grey.shade300)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 760;
              if (_createJobStep == 0) {
                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _closeTemplateEditor,
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Cancel'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _updateSelectedTemplateFromCurrentForm,
                            icon: const Icon(Icons.sync),
                            label: const Text('Save Changes'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          if (_validateCreateBasics()) {
                            setState(() {
                              _createJobStep = 1;
                            });
                          }
                        },
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Next: Qualifications'),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _closeTemplateEditor,
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _updateSelectedTemplateFromCurrentForm,
                          icon: const Icon(Icons.sync),
                          label: const Text('Save Changes'),
                        ),
                      ],
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () {
                        if (_validateCreateBasics()) {
                          setState(() {
                            _createJobStep = 1;
                          });
                        }
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Next: Qualifications'),
                    ),
                  ],
                );
              }

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _createJobStep = 0;
                            });
                          },
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back to Basics'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _closeTemplateEditor,
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Cancel'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _updateSelectedTemplateFromCurrentForm,
                          icon: const Icon(Icons.sync),
                          label: const Text('Save Changes'),
                        ),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _createJobStep = 0;
                      });
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to Basics'),
                  ),
                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _closeTemplateEditor,
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _updateSelectedTemplateFromCurrentForm,
                            icon: const Icon(Icons.sync),
                            label: const Text('Save Changes'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTemplatesTab() {
    final editingTemplate = _editingTemplate;
    if (editingTemplate != null) {
      return _buildTemplateEditorTab(editingTemplate);
    }

    final templates = _currentEmployerTemplates;

    if (templates.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No templates yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Build a listing once, then save it as a template to quickly create similar openings later.',
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: templates.length,
      itemBuilder: (context, index) {
        final template = templates[index];
        final templateUpdatedAt = template.updatedAt ?? template.createdAt;
        final updatedLabel = templateUpdatedAt != null
            ? _formatYmd(templateUpdatedAt.toLocal())
            : null;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openTemplateSummary(template, context),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${template.listing.title} • ${template.listing.location}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (updatedLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Last Updated: $updatedLabel',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Builder(
                        builder: (tabContext) => OutlinedButton.icon(
                          onPressed: () {
                            _openCreateFromTemplate(
                              template,
                              tabContext,
                              linkTemplate: false,
                            );
                          },
                          icon: const Icon(Icons.edit_note_outlined),
                          label: const Text('Use Template'),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _renameTemplate(template),
                        icon: const Icon(Icons.drive_file_rename_outline),
                        label: const Text('Rename'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _openTemplateEditor(template),
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _deleteTemplate(template),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEmployer = _profileType == ProfileType.employer;
    final tabs = isEmployer
        ? const [
            Tab(text: 'Employer Profile'),
            Tab(text: 'Listed Jobs'),
            Tab(text: 'Create New Listing'),
            Tab(text: 'Templates'),
            Tab(text: 'Applicants'),
          ]
        : const [
            Tab(text: 'Jobs'),
            Tab(text: 'Search'),
            Tab(text: 'Profile'),
            Tab(text: 'Favorites'),
            Tab(text: 'My Applications'),
          ];

    return DefaultTabController(
      length: tabs.length,
      initialIndex: isEmployer ? 1 : 0,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: Text(widget.title),
          actions: [
            PopupMenuButton<ProfileType>(
              icon: const Icon(Icons.person),
              onSelected: (value) {
                setState(() {
                  _profileType = value;
                  _query = '';
                  _page = 1;
                });
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: ProfileType.jobSeeker,
                  child: Text('Job Seeker'),
                ),
                const PopupMenuItem(
                  value: ProfileType.employer,
                  child: Text('Employer'),
                ),
              ],
            ),
            if (_profileType == ProfileType.jobSeeker)
              Container(
                margin: const EdgeInsets.only(right: 16),
                alignment: Alignment.center,
                child: Chip(label: Text('★ ${_favoriteIds.length}')),
              ),
            if (SupabaseBootstrap.isConfigured)
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Sign out',
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                },
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: tabs,
          ),
        ),
        body: SafeArea(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: TabBarView(
              children: isEmployer
                  ? [
                      _buildResponsiveTabContent(_buildCompanyProfileTab()),
                      _buildResponsiveTabContent(_buildJobsTab()),
                      _buildResponsiveTabContent(_buildCreateTab()),
                      _buildResponsiveTabContent(_buildTemplatesTab()),
                      _buildResponsiveTabContent(
                        _buildEmployerApplicationsTab(),
                      ),
                    ]
                  : [
                      _buildResponsiveTabContent(_buildJobsTab()),
                      _buildResponsiveTabContent(_buildSearchTab()),
                      _buildResponsiveTabContent(_buildProfileTab()),
                      _buildResponsiveTabContent(_buildFavoritesTab()),
                      _buildResponsiveTabContent(_buildMyApplicationsTab()),
                    ],
            ),
          ),
        ),
        bottomSheet: kIsWeb && _showCookieConsentBanner
            ? _buildCookieConsentBanner()
            : null,
      ),
    );
  }
}

class JobDetailsPage extends StatelessWidget {
  final JobListing job;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback? onApply;
  final VoidCallback? onShare;
  final VoidCallback? onSeeAllListings;
  final JobSeekerProfile? profile;
  final EmployerProfile? companyProfile;
  final int openRoleCount;
  final bool hasApplied;
  final int? matchPercentage;

  const JobDetailsPage({
    super.key,
    required this.job,
    required this.isFavorite,
    required this.onFavorite,
    this.onApply,
    this.onShare,
    this.onSeeAllListings,
    this.profile,
    this.companyProfile,
    this.openRoleCount = 0,
    this.hasApplied = false,
    this.matchPercentage,
  });

  void _openCompanyInfo(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublicCompanyInfoPage(
          job: job,
          employerProfile: companyProfile,
          openRoleCount: openRoleCount,
          onSeeAllListings: onSeeAllListings,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final safeLeftInset = math.max(
      mediaQuery.viewPadding.left,
      math.max(mediaQuery.padding.left, mediaQuery.systemGestureInsets.left),
    );
    final safeRightInset = math.max(
      mediaQuery.viewPadding.right,
      math.max(mediaQuery.padding.right, mediaQuery.systemGestureInsets.right),
    );
    final standardFlightHourEntries = job.flightHoursByType.entries.toList();
    final instructorHourEntries = job.instructorHoursByType.entries.toList();
    final timelineLabels = _buildTimelineLabels(
      createdAt: job.createdAt,
      updatedAt: job.updatedAt,
    );
    final applicationDeadlineText = job.deadlineDate != null
        ? _formatYmd(job.deadlineDate!.toLocal())
        : null;
    final showStickyActionBar = profile != null;
    final detailsBottomPadding = 24.0;
    final crewLabel = job.crewRole.toLowerCase() == 'crew'
        ? (job.crewPosition != null && job.crewPosition!.trim().isNotEmpty
              ? 'Crew Member - ${job.crewPosition}'
              : 'Crew Member')
        : 'Single Pilot';

    return Scaffold(
      appBar: AppBar(
        title: Text(job.title),
        actions: showStickyActionBar
            ? null
            : [
                IconButton(
                  icon: Icon(isFavorite ? Icons.star : Icons.star_border),
                  tooltip: isFavorite ? 'Remove favorite' : 'Add favorite',
                  onPressed: onFavorite,
                ),
              ],
      ),
      body: SafeArea(
        top: false,
        child: Container(
          color: Colors.grey.shade50,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16 + safeLeftInset,
                    16,
                    16 + safeRightInset,
                    16,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.only(bottom: detailsBottomPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              job.title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              job.company,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            TextButton.icon(
                              onPressed: () => _openCompanyInfo(context),
                              icon: const Icon(
                                Icons.business_outlined,
                                size: 18,
                              ),
                              label: const Text('View Company Info'),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                alignment: Alignment.centerLeft,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${job.location} • ${job.type}',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            if (applicationDeadlineText != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  border: Border.all(
                                    color: Colors.orange.shade200,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.event_available,
                                      color: Colors.orange.shade800,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Application Deadline',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.orange.shade900,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            applicationDeadlineText,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.orange.shade900,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (job.salaryRange != null)
                                  Chip(
                                    label: Text('Salary: ${job.salaryRange}'),
                                  ),
                                Chip(label: Text(crewLabel)),
                              ],
                            ),
                            if (timelineLabels.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: timelineLabels
                                    .map(
                                      (label) => Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          label,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDetailSection(
                        context: context,
                        title: 'Job Description',
                        icon: Icons.description_outlined,
                        child: Text(
                          job.description,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      if (job.benefits.isNotEmpty)
                        _buildDetailSection(
                          context: context,
                          title: 'Benefits',
                          icon: Icons.card_giftcard,
                          child: _buildChipWrap(
                            job.benefits
                                .map((benefit) => Chip(label: Text(benefit)))
                                .toList(),
                          ),
                        ),
                      if (job.faaCertificates.isNotEmpty)
                        _buildDetailSection(
                          context: context,
                          title: 'Required FAA Certificates',
                          icon: Icons.badge_outlined,
                          child: _buildChipWrap(
                            job.faaCertificates
                                .map(
                                  (cert) => Chip(
                                    label: Text(
                                      canonicalCertificateLabel(cert),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      if (job.typeRatingsRequired.isNotEmpty)
                        _buildDetailSection(
                          context: context,
                          title: 'Required Type Ratings',
                          icon: Icons.confirmation_number_outlined,
                          child: _buildChipWrap(
                            job.typeRatingsRequired
                                .map((rating) => Chip(label: Text(rating)))
                                .toList(),
                          ),
                        ),
                      if (job.faaRules.isNotEmpty)
                        _buildDetailSection(
                          context: context,
                          title: 'FAA Rules',
                          icon: Icons.rule,
                          child: _buildChipWrap(
                            job.faaRules
                                .map((rule) => Chip(label: Text(rule)))
                                .toList(),
                          ),
                        ),
                      if (standardFlightHourEntries.isNotEmpty)
                        _buildDetailSection(
                          context: context,
                          title: 'Flight Hours',
                          icon: Icons.schedule_outlined,
                          child: _buildChipWrap(
                            standardFlightHourEntries
                                .map(
                                  (entry) => _buildRequirementChip(
                                    label: _formatHoursRequirementLabel(
                                      entry.key,
                                      entry.value,
                                      job.preferredFlightHours.contains(
                                        entry.key,
                                      ),
                                    ),
                                    isPreferred: job.preferredFlightHours
                                        .contains(entry.key),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      if (instructorHourEntries.isNotEmpty)
                        _buildDetailSection(
                          context: context,
                          title: 'Instructor Hours',
                          icon: Icons.school_outlined,
                          child: _buildChipWrap(
                            instructorHourEntries
                                .map(
                                  (entry) => _buildRequirementChip(
                                    label: _formatHoursRequirementLabel(
                                      entry.key,
                                      entry.value,
                                      job.preferredInstructorHours.contains(
                                        entry.key,
                                      ),
                                    ),
                                    isPreferred: job.preferredInstructorHours
                                        .contains(entry.key),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      if (job.specialtyHoursByType.isNotEmpty)
                        _buildDetailSection(
                          context: context,
                          title: 'Specialty Hours',
                          icon: Icons.workspace_premium_outlined,
                          child: _buildChipWrap(
                            job.specialtyHoursByType.entries
                                .map(
                                  (entry) => _buildRequirementChip(
                                    label: _formatHoursRequirementLabel(
                                      entry.key,
                                      entry.value,
                                      job.preferredSpecialtyHours.contains(
                                        entry.key,
                                      ),
                                    ),
                                    isPreferred: job.preferredSpecialtyHours
                                        .contains(entry.key),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      if (job.aircraftFlown.isNotEmpty)
                        _buildDetailSection(
                          context: context,
                          title: 'Required Aircraft Experience',
                          icon: Icons.flight_outlined,
                          child: _buildChipWrap(
                            job.aircraftFlown
                                .map((aircraft) => Chip(label: Text(aircraft)))
                                .toList(),
                          ),
                        ),
                      if (profile != null) ...[
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        _buildDetailSection(
                          context: context,
                          title: 'Your Match',
                          icon: Icons.analytics_outlined,
                          child: _buildComparisonView(context),
                        ),
                      ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showStickyActionBar)
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    border: Border(top: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16 + safeLeftInset,
                        10,
                        16 + safeRightInset,
                        10,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 960),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _buildApplyButton(context),
                              OutlinedButton.icon(
                                onPressed: onShare,
                                icon: const Icon(Icons.share_outlined),
                                label: const Text('Share Listing'),
                              ),
                              OutlinedButton.icon(
                                onPressed: onFavorite,
                                icon: Icon(
                                  isFavorite ? Icons.star : Icons.star_border,
                                ),
                                label: Text(
                                  isFavorite ? 'Favorited' : 'Favorite',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildApplyButton(BuildContext context) {
    if (hasApplied) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check),
        label: const Text('✓ Applied'),
      );
    }

    final pct = matchPercentage;
    if (pct == null) {
      return ElevatedButton.icon(
        onPressed: onApply,
        icon: const Icon(Icons.send_outlined),
        label: const Text('Apply'),
      );
    }

    if (pct >= 90) {
      return FilledButton.icon(
        onPressed: onApply,
        icon: const Icon(Icons.check_circle),
        label: const Text('Apply Now'),
        style: FilledButton.styleFrom(backgroundColor: Colors.green),
      );
    } else if (pct >= 70) {
      return FilledButton.icon(
        onPressed: onApply,
        icon: const Icon(Icons.send),
        label: const Text('Quick Apply'),
        style: FilledButton.styleFrom(backgroundColor: Colors.orange),
      );
    } else {
      return FilledButton.icon(
        onPressed: onApply,
        icon: const Icon(Icons.warning),
        label: const Text('Apply Anyway'),
        style: FilledButton.styleFrom(backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildDetailSection({
    required BuildContext context,
    required String title,
    required Widget child,
    IconData? icon,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: Colors.blueGrey.shade700),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildChipWrap(List<Widget> chips) {
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _buildRequirementChip({
    required String label,
    required bool isPreferred,
  }) {
    return Chip(
      label: Text(label),
      avatar: Icon(
        isPreferred ? Icons.info_outline : Icons.check_circle_outline,
        size: 16,
        color: isPreferred ? Colors.orange.shade800 : Colors.green.shade800,
      ),
      backgroundColor: isPreferred
          ? Colors.orange.shade50
          : Colors.green.shade50,
      side: BorderSide(
        color: isPreferred ? Colors.orange.shade200 : Colors.green.shade200,
      ),
      labelStyle: TextStyle(
        color: isPreferred ? Colors.orange.shade900 : Colors.green.shade900,
      ),
    );
  }

  Widget _buildComparisonView(BuildContext context) {
    if (profile == null) return const SizedBox.shrink();
    final match = _evaluateJobMatchForProfile(
      job: job,
      profile: profile!,
      includeCertPrefix: false,
    );
    final profileCertificates = <String>{
      for (final cert in profile!.faaCertificates)
        ...expandedCertificateQualifications(cert),
    };
    final matchPercentage = match.matchPercentage;
    final isFullMatch = match.isFullMatch;
    final standardFlightHourEntries = job.flightHoursByType.entries.toList();
    final instructorHourEntries = job.instructorHoursByType.entries.toList();

    final flightRows = _buildMatchHoursRows(
      sectionTitle: 'Flight Hours:',
      entries: standardFlightHourEntries,
      isPreferredFor: (hourName) => job.preferredFlightHours.contains(hourName),
      profileHoursFor: (hourName) => profile!.flightHours[hourName] ?? 0,
      hasExperienceFor: (hourName) =>
          profile!.flightHoursTypes.contains(hourName),
    );
    final instructorRows = _buildMatchHoursRows(
      sectionTitle: 'Instructor Hours:',
      entries: instructorHourEntries,
      isPreferredFor: (hourName) =>
          job.preferredInstructorHours.contains(hourName),
      profileHoursFor: (hourName) => profile!.flightHours[hourName] ?? 0,
      hasExperienceFor: (hourName) =>
          profile!.flightHoursTypes.contains(hourName),
    );
    final specialtyRows = _buildMatchHoursRows(
      sectionTitle: 'Specialty Hours:',
      entries: job.specialtyHoursByType.entries,
      isPreferredFor: (hourName) =>
          job.preferredSpecialtyHours.contains(hourName),
      profileHoursFor: (hourName) =>
          profile!.specialtyFlightHoursMap[hourName] ?? 0,
      hasExperienceFor: (hourName) =>
          profile!.specialtyFlightHours.contains(hourName),
    );

    final hasVisibleResults =
        job.faaCertificates.isNotEmpty ||
        flightRows.isNotEmpty ||
        instructorRows.isNotEmpty ||
        specialtyRows.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              label: Text('$matchPercentage% Match'),
              backgroundColor: isFullMatch
                  ? Colors.green[100]
                  : Colors.orange[100],
              labelStyle: TextStyle(
                color: isFullMatch ? Colors.green[900] : Colors.orange[900],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (job.faaCertificates.isNotEmpty) ...[
          const Text(
            'Certificates:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ...job.faaCertificates.map((cert) {
            final hasIt = profileCertificates.contains(
              normalizeCertificateName(cert),
            );
            final certLabel = canonicalCertificateLabel(cert);
            return Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    hasIt ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: hasIt ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      certLabel,
                      softWrap: true,
                      style: TextStyle(
                        color: hasIt ? Colors.green : Colors.red,
                        decoration: hasIt ? null : TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
        ...flightRows,
        ...instructorRows,
        ...specialtyRows,
        if (!hasVisibleResults)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              border: Border.all(color: Colors.green.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'No comparison rows available for this job.',
              style: TextStyle(color: Colors.green.shade900),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildMatchHoursRows({
    required String sectionTitle,
    required Iterable<MapEntry<String, int>> entries,
    required bool Function(String hourName) isPreferredFor,
    required int Function(String hourName) profileHoursFor,
    required bool Function(String hourName) hasExperienceFor,
  }) {
    final visibleEntries = entries.toList();

    if (visibleEntries.isEmpty) {
      return const [];
    }

    return [
      const SizedBox(height: 8),
      Text(sectionTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
      ...visibleEntries.map((entry) {
        final isPreferred = isPreferredFor(entry.key);
        final profileHours = profileHoursFor(entry.key);
        final hasIt =
            hasExperienceFor(entry.key) && profileHours >= entry.value;

        return Padding(
          padding: const EdgeInsets.only(left: 8, top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isPreferred
                        ? Icons.info_outline
                        : hasIt
                        ? Icons.check_circle
                        : Icons.cancel,
                    size: 16,
                    color: isPreferred
                        ? Colors.grey[700]
                        : hasIt
                        ? Colors.green
                        : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatHoursRequirementLabel(
                        entry.key,
                        entry.value,
                        isPreferred,
                      ),
                      style: TextStyle(
                        color: isPreferred
                            ? Colors.grey[700]
                            : hasIt
                            ? Colors.green
                            : Colors.red,
                        decoration: isPreferred || hasIt
                            ? null
                            : TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                ],
              ),
              if (!isPreferred && !hasIt)
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 2),
                  child: Text(
                    'Current: $profileHours hrs • Required: ${entry.value} hrs • Progress: ${entry.value <= 0 ? 100 : ((profileHours * 100) ~/ entry.value)}%',
                    style: TextStyle(
                      color: Colors.red.shade800,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    ];
  }
}

class PublicCompanyInfoPage extends StatelessWidget {
  final JobListing job;
  final EmployerProfile? employerProfile;
  final int openRoleCount;
  final VoidCallback? onSeeAllListings;

  const PublicCompanyInfoPage({
    super.key,
    required this.job,
    this.employerProfile,
    this.openRoleCount = 0,
    this.onSeeAllListings,
  });

  String get _companyName {
    final profileName = employerProfile?.companyName.trim() ?? '';
    if (profileName.isNotEmpty) {
      return profileName;
    }
    final companyName = job.company.trim();
    return companyName.isNotEmpty ? companyName : 'Company';
  }

  String? get _headquartersLabel {
    if (employerProfile == null) {
      return null;
    }

    final parts = [
      employerProfile!.headquartersCity.trim(),
      employerProfile!.headquartersState.trim(),
      employerProfile!.headquartersCountry.trim(),
    ].where((part) => part.isNotEmpty).toList();

    if (parts.isEmpty) {
      return null;
    }

    return parts.join(' • ');
  }

  List<String> get _headquartersAddressLines {
    if (employerProfile == null) {
      return const [];
    }

    return [
      employerProfile!.headquartersAddressLine1.trim(),
      employerProfile!.headquartersAddressLine2.trim(),
      employerProfile!.headquartersCity.trim(),
      employerProfile!.headquartersState.trim(),
      employerProfile!.headquartersPostalCode.trim(),
      employerProfile!.headquartersCountry.trim(),
    ].where((part) => part.isNotEmpty).toList();
  }

  String get _websiteValue => employerProfile?.website.trim() ?? '';

  String get _contactNameValue => employerProfile?.contactName.trim() ?? '';

  String get _contactEmailValue => employerProfile?.contactEmail.trim() ?? '';

  String get _contactPhoneValue =>
      _formatPhoneNumber(employerProfile?.contactPhone.trim() ?? '');

  String get _descriptionValue =>
      employerProfile?.companyDescription.trim() ?? '';

  List<String> get _companyBenefits =>
      employerProfile?.companyBenefits ?? const [];

  Future<void> _openWebsite(BuildContext context) async {
    final rawWebsite = _websiteValue;
    if (rawWebsite.isEmpty) {
      return;
    }

    final normalized =
        rawWebsite.startsWith('http://') || rawWebsite.startsWith('https://')
        ? rawWebsite
        : 'https://$rawWebsite';
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the company website.')),
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the company website.')),
      );
    }
  }

  Widget _buildInfoCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Colors.blueGrey.shade700),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final headquartersLabel = _headquartersLabel;
    final headquartersAddressLines = _headquartersAddressLines;
    final websiteValue = _websiteValue;
    final contactNameValue = _contactNameValue;
    final contactEmailValue = _contactEmailValue;
    final contactPhoneValue = _contactPhoneValue;
    final descriptionValue = _descriptionValue;
    final companyBenefits = _companyBenefits;

    return Scaffold(
      appBar: AppBar(title: const Text('Company Info')),
      body: Container(
        color: Colors.grey.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey.shade50,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.business,
                                  color: Colors.blueGrey.shade700,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _companyName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Public-facing company information for applicants',
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (openRoleCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blueGrey.shade50,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '$openRoleCount open role${openRoleCount == 1 ? '' : 's'}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.blueGrey.shade800,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (headquartersLabel != null)
                                Chip(
                                  avatar: const Icon(
                                    Icons.location_on_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    'Headquarters: $headquartersLabel',
                                  ),
                                ),
                              Chip(
                                avatar: const Icon(
                                  Icons.work_outline,
                                  size: 18,
                                ),
                                label: Text('Current opening: ${job.title}'),
                              ),
                            ],
                          ),
                          if (websiteValue.isNotEmpty ||
                              onSeeAllListings != null) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                if (websiteValue.isNotEmpty)
                                  OutlinedButton.icon(
                                    onPressed: () => _openWebsite(context),
                                    icon: const Icon(Icons.open_in_new),
                                    label: const Text('Visit Company Website'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                    ),
                                  ),
                                if (onSeeAllListings != null)
                                  OutlinedButton.icon(
                                    onPressed: onSeeAllListings,
                                    icon: const Icon(Icons.list_alt_outlined),
                                    label: const Text('See All Listings'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (descriptionValue.isNotEmpty)
                      _buildInfoCard(
                        context: context,
                        title: 'About Company',
                        icon: Icons.info_outline,
                        child: Text(
                          descriptionValue,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    if (companyBenefits.isNotEmpty)
                      _buildInfoCard(
                        context: context,
                        title: 'What They Highlight',
                        icon: Icons.workspace_premium_outlined,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: companyBenefits
                              .map((benefit) => Chip(label: Text(benefit)))
                              .toList(),
                        ),
                      ),
                    _buildInfoCard(
                      context: context,
                      title: 'Headquarters Address',
                      icon: Icons.pin_drop_outlined,
                      child: headquartersAddressLines.isNotEmpty
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: headquartersAddressLines
                                  .map(
                                    (line) => Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: Text(
                                        line,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            )
                          : Text(
                              'No headquarters address published yet.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                    ),
                    _buildInfoCard(
                      context: context,
                      title: 'Company Contact',
                      icon: Icons.contact_phone_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Contact Name: ${contactNameValue.isNotEmpty ? contactNameValue : 'Not provided'}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Contact Email: ${contactEmailValue.isNotEmpty ? contactEmailValue : 'Not provided'}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Contact Phone: ${contactPhoneValue.isNotEmpty ? contactPhoneValue : 'Not provided'}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
