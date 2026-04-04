import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/aviation_certificate_utils.dart';
import 'models/employer_profile.dart';
import 'models/employer_profiles_data.dart';
import 'models/job_listing.dart';
import 'models/job_seeker_profile.dart';
import 'repositories/app_repository.dart';
import 'screens/sign_in_screen.dart';
import 'services/app_repository_factory.dart';
import 'services/supabase_bootstrap.dart';

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

  // ============================================================================
  // JOB LISTING STATE: Data models and data persistence
  // ============================================================================

  late List<JobListing> _allJobs;
  final Set<String> _favoriteIds = {};

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
  int _createJobStep = 0;
  String? _selectedCreatePositionOption;
  String? _selectedCreatePayRateMetric;
  String? _expandedCreateRequirementsSection = 'Certificates and Ratings';

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
    _fetchJobs();
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
      employerId: job.employerId,
    );
  }

  void _syncJobSeekerProfileControllers(JobSeekerProfile profile) {
    _profileFullNameController.text = profile.fullName;
    _profileEmailController.text = _resolvedJobSeekerEmail(profile);
    _profilePhoneController.text = profile.phone;
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
    final fullNameController = TextEditingController(
      text: _jobSeekerProfile.fullName,
    );
    final accountEmail = _resolvedJobSeekerEmail(_jobSeekerProfile);
    final phoneController = TextEditingController(
      text: _jobSeekerProfile.phone,
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
                final updated = _jobSeekerProfile.copyWith(
                  fullName: fullNameController.text.trim(),
                  email: accountEmail,
                  phone: phoneController.text.trim(),
                  city: cityController.text.trim(),
                  stateOrProvince: stateController.text.trim(),
                  country: countryController.text.trim(),
                );
                Navigator.of(pageContext).pop(updated);
              }

              bool hasPersonalChanges() {
                return fullNameController.text.trim() !=
                        _jobSeekerProfile.fullName ||
                    phoneController.text.trim() != _jobSeekerProfile.phone ||
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
                              TextField(
                                controller: fullNameController,
                                onChanged: (_) => setPageState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'Full Name',
                                ),
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

    fullNameController.dispose();
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
                child: Row(
                  children: [
                    Expanded(
                      child: RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Same as Company'),
                        value: true,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Custom'),
                        value: false,
                      ),
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
                (type) => DropdownMenuItem<String>(
                  value: type,
                  child: Text(type),
                ),
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
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
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

    setState(() {
      _employerProfiles = data.profiles;
      if (_employerProfiles.isNotEmpty) {
        _currentEmployer = _employerProfiles.firstWhere(
          (profile) => profile.id == data.currentEmployerId,
          orElse: () => _employerProfiles.first,
        );
      }
      // Pre-fill the create-form company field from the loaded profile.
      _createCompanyController.text = _currentEmployer.companyName;
    });
  }

  Future<void> _saveEmployerProfiles() async {
    await _appRepository.saveEmployerProfiles(
      EmployerProfilesData(
        profiles: _employerProfiles,
        currentEmployerId: _currentEmployer.id,
      ),
    );
  }

  void _switchEmployer(EmployerProfile employer) {
    setState(() {
      _currentEmployer = employer;
      _employerProfileEditing = false;
      // Keep the create-form company field in sync when switching employer.
      _createCompanyController.text = employer.companyName;
    });
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
    _employerWebsiteController.text = _currentEmployer.website;
    _employerContactNameController.text = _currentEmployer.contactName;
    _employerContactEmailController.text = _currentEmployer.contactEmail;
    _employerContactPhoneController.text = _currentEmployer.contactPhone;
    _employerDescriptionController.text = _currentEmployer.companyDescription;
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
      testingJob: _allCriteriaTestJob,
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

  JobListing get _allCriteriaTestJob => JobListing(
    id: 'test-all-criteria-job',
    title: 'TESTING JOB POST',
    company: 'QA Aviation Systems',
    location: 'Denver, CO',
    type: 'Contract',
    crewRole: 'Crew',
    crewPosition: 'Co-Pilot',
    faaRules: const ['Part 135'],
    description:
        'Validation posting that reflects the current create-listing workflow, including position selection, salary metric formatting, FAA scope, certificate groups, ratings, and minimum hours requirements.',
    faaCertificates: [
      ..._availableFaaCertificates,
      ..._availableInstructorCertificates,
      ..._availableRatingSelections,
    ],
    typeRatingsRequired: const ['Boeing 737', 'Embraer E-175', 'Airbus A320'],
    flightExperience: <String>[
      ..._availableEmployerFlightHours,
      ..._availableInstructorHours,
    ],
    flightHours: const {
      'Total Time': 3500,
      'PIC Jet': 1500,
      'SIC Jet': 500,
      'PIC Turbine': 1200,
      'SIC Turbine': 300,
      'PIC': 2500,
      'SIC': 500,
      'Multi-engine': 800,
    },
    instructorHours: const {
      'Total Instructor Hours': 600,
      'Instrument (CFII)': 220,
      'Multi-Engine (MEI)': 180,
    },
    preferredFlightHours: const ['SIC Jet'],
    preferredInstructorHours: const ['Instrument (CFII)'],
    specialtyExperience: List<String>.from(_availableSpecialtyExperience),
    specialtyHours: const {
      'Fire Fighting': 300,
      'Aerobatic': 50,
      'Floatplane': 100,
      'Tailwheel': 75,
      'Off Airport': 60,
      'Banner Towing': 80,
      'Low Altitude': 120,
      'Aerial Survey': 150,
    },
    preferredSpecialtyHours: const ['Aerobatic', 'Banner Towing'],
    aircraftFlown: const ['Cessna 172', 'Boeing 737', 'Airbus A320'],
    salaryRange: r'$120000 - $185000 / Annual Salary',
    benefits: const ['Health Insurance', '401k', 'Relocation', 'Sign-on Bonus'],
    deadlineDate: DateTime.now().add(const Duration(days: 60)),
  );

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
    _createCompanyController.dispose();
    _createLocationController.dispose();
    _createTypeController.dispose();
    _createStartingPayController.dispose();
    _createPayForExperienceController.dispose();
    _createDescriptionController.dispose();
    _createTypeRatingsController.dispose();
    _createAircraftController.dispose();
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

  void _openDetails(JobListing job) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobDetailsPage(
          job: job,
          isFavorite: _favoriteIds.contains(job.id),
          onFavorite: () => _toggleFavorite(job),
          profile: _profileType == ProfileType.jobSeeker
              ? _jobSeekerProfile
              : null,
        ),
      ),
    );
  }

  void _applyToJob(JobListing job) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Application sent for ${job.title} at ${job.company}.',
        ),
      ),
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

    String _extractNumericValue(String value) {
      return value.replaceAll(RegExp(r'[^0-9.]'), '');
    }

    String? _buildEditedSalaryRange() {
      final startingPay = startingPayController.text.trim();
      if (startingPay.isEmpty) {
        return null;
      }

      final topEndPay = topEndStartingPayController.text.trim();
      final metric = selectedPayMetric;
        final metricSuffix =
          metric == null || metric.isEmpty ? '' : ' / $metric';

      final startLabel = startingPay.startsWith(r'$')
          ? startingPay
          : '\$$startingPay';

      if (topEndPay.isNotEmpty) {
        final topEndLabel = topEndPay.startsWith(r'$')
            ? topEndPay
            : '\$$topEndPay';
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
          final normalizedMetric = legacyMetricMap[parsedMetric] ?? parsedMetric;
          if (_availablePayRateMetrics.contains(normalizedMetric)) {
            selectedPayMetric = normalizedMetric;
          }
        }
        amountPortion = raw.substring(0, metricMatch.start).trim();
      }

      if (amountPortion.contains('-')) {
        final parts = amountPortion.split('-');
        startingPayController.text = _extractNumericValue(parts.first.trim());
        if (parts.length > 1) {
          topEndStartingPayController.text = _extractNumericValue(
            parts[1].trim(),
          );
        }
      } else {
        startingPayController.text = _extractNumericValue(amountPortion);
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
          draft.salaryRange != job.salaryRange;
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
      if (selectedPayMetric == null || selectedPayMetric!.isEmpty) {
        missingRequirements.add('Pay Metric');
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
          final value = int.tryParse(controllers[option]?.text.trim() ?? '0') ??
              0;
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
          hasMissingHoursValues(selectedSpecialtyHours, specialtyHourControllers);

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
              content: Text(
                'Missing: ${missingRequirements.join(', ')}',
              ),
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
        salaryRange: _buildEditedSalaryRange(),
        minimumHours: job.minimumHours,
        benefits: List<String>.from(job.benefits),
        deadlineDate: job.deadlineDate,
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
                  (type) => DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  ),
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
                  (rule) => DropdownMenuItem<String>(
                    value: rule,
                    child: Text(rule),
                  ),
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

  void _clearCreateForm() {
    _createJobStep = 0;
    _useCompanyLocationForJob = true;
    _createTitleController.clear();
    _createCompanyController.text = _currentEmployer.companyName;
    _createLocationController.clear();
    _createTypeController.clear();
    _selectedCreatePositionOption = null;
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
    final payMetric = _selectedCreatePayRateMetric;
    final description = _createDescriptionController.text.trim();

    if (title.isEmpty) missing.add('Title');
    if (company.isEmpty) missing.add('Company');
    if (location.isEmpty) missing.add('Location');
    if (type.isEmpty) missing.add('Employment Type');
    if (position == null || position.isEmpty) missing.add('Position Selection');
    if (description.isEmpty) missing.add('Description');
    if (startingPay.isEmpty) missing.add('Starting Pay');
    if (payMetric == null || payMetric.isEmpty) missing.add('Pay Metric');

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
    final selectedSpecialtyHourEntries = _selectedSpecialtyHours.entries.toList();

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
    final startingPay = _createStartingPayController.text.trim();
    if (startingPay.isEmpty) {
      return null;
    }

    final payForExperience = _createPayForExperienceController.text.trim();
    final metric = _selectedCreatePayRateMetric;
    final metricSuffix =
      metric == null || metric.isEmpty ? '' : ' / $metric';

    final startLabel = startingPay.startsWith(r'$')
        ? startingPay
      : '\$$startingPay';

    if (payForExperience.isNotEmpty) {
      final endLabel = payForExperience.startsWith(r'$')
          ? payForExperience
          : '\$$payForExperience';
      return '$startLabel - $endLabel$metricSuffix';
    }

    return '$startLabel$metricSuffix';
  }

  Future<void> _createJobListing() async {
    if (!_validateCreateBasics()) {
      return;
    }

    if (!_validateCreateQualifications()) {
      return;
    }

    final title = _createTitleController.text.trim();
    final company = _profileType == ProfileType.employer
        ? _currentEmployer.companyName.trim()
        : _createCompanyController.text.trim();
    final location = _useCompanyLocationForJob
        ? _buildCompanyLocationString()
        : _createLocationController.text.trim();
    final type = _createTypeController.text.trim();
    final description = _createDescriptionController.text.trim();
    final typeRatingsRequired = _createTypeRatingsController.text
        .split(',')
        .map((rating) => rating.trim())
        .where((rating) => rating.isNotEmpty)
        .toSet()
        .toList();

    final newJob = JobListing(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      company: company,
      location: location,
      type: type.isNotEmpty ? type : 'Full-Time',
      crewRole: _selectedCrewRole,
      crewPosition: _selectedCrewRole == 'Crew' ? _selectedCrewPosition : null,
        description: description,
      faaCertificates: List.from(_selectedFaaCertificates),
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
      employerId: _profileType == ProfileType.employer
          ? _currentEmployer.id
          : null,
    );

    try {
      final createdJob = await _appRepository.createJob(newJob);
      if (!mounted) {
        return;
      }

      setState(() {
        _allJobs = [createdJob, ..._allJobs];
        _query = '';
        _page = 1;
      });

      _clearCreateForm();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Job listing "$title" created.')));
      await _showCreatedJobSummary(createdJob);
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
        final isWideLayout = constraints.maxWidth >= 900;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWideLayout ? 960 : double.infinity,
            ),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildJobsTab() {
    final jobs = _pagedJobs;
    final totalPages = (_filteredJobs.length / _pageSize).ceil().clamp(1, 999);

    return Padding(
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
              child: Center(
                child: Text(
                  _profileType == ProfileType.employer
                      ? 'No job listings for ${_currentEmployer.companyName}.'
                      : 'No results for "$_query"',
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
                      itemCount: jobs.length,
                      itemBuilder: (context, index) {
                        final job = jobs[index];
                        final isFav = _favoriteIds.contains(job.id);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            title: Text(job.title),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text('${job.company} • ${job.location}'),
                                Text('${job.type} • ${job.description}'),
                              ],
                            ),
                            isThreeLine: true,
                            leading: const Icon(Icons.work),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_profileType == ProfileType.jobSeeker) ...[
                                  Builder(
                                    builder: (context) {
                                      final match = _evaluateJobMatch(job);
                                      Color badgeColor = Colors.red;
                                      String badgeIcon = '✗';
                                      if (match.matchPercentage >= 80) {
                                        badgeColor = Colors.green;
                                        badgeIcon = '✓';
                                      } else if (match.matchPercentage >= 50) {
                                        badgeColor = Colors.orange;
                                        badgeIcon = '⚠';
                                      }
                                      final missingText = match
                                          .missingRequirements
                                          .take(2)
                                          .join(', ');
                                      return Tooltip(
                                        message: match.matchPercentage >= 80
                                            ? 'Strong match. You meet all required criteria.'
                                            : 'Potential fit. Missing required: $missingText',
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: badgeColor,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
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
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      isFav ? Icons.star : Icons.star_border,
                                      color: isFav ? Colors.amber : null,
                                    ),
                                    onPressed: () => _toggleFavorite(job),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.send),
                                    tooltip: 'Apply',
                                    onPressed: () => _applyToJob(job),
                                  ),
                                ],
                                if (_canDeleteJob(job))
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    tooltip: 'Delete job',
                                    onPressed: () => _removeJob(job),
                                  ),
                                if (_canEditJob(job))
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    tooltip: 'Edit job',
                                    onPressed: () => _editJob(job),
                                  ),
                              ],
                            ),
                            onTap: () => _openDetails(job),
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Page $_page / $totalPages'),
                      Row(
                        children: [
                          IconButton(
                            onPressed: _page > 1 ? () => _changePage(-1) : null,
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
                ],
              ),
            ),
        ],
      ),
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
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            title: Text(job.title),
            subtitle: Text('${job.company} • ${job.location}'),
            onTap: () => _openDetails(job),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_employerProfileEditing)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _startEditingEmployerProfile,
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Edit'),
              ),
            ),
          const SizedBox(height: 16),
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
          TextField(
            controller: _employerCtrl(
              _employerCompanyNameController,
              _currentEmployer.companyName,
            ),
            readOnly: !_employerProfileEditing,
            decoration: const InputDecoration(labelText: 'Company Name'),
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
                  decoration: const InputDecoration(labelText: 'Postal Code'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildEmployerCountryField()),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _employerCtrl(
              _employerWebsiteController,
              _currentEmployer.website,
            ),
            readOnly: !_employerProfileEditing,
            decoration: const InputDecoration(labelText: 'Company Website'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _employerCtrl(
              _employerContactNameController,
              _currentEmployer.contactName,
            ),
            readOnly: !_employerProfileEditing,
            decoration: const InputDecoration(labelText: 'Hiring Contact Name'),
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
              _currentEmployer.contactPhone,
            ),
            readOnly: !_employerProfileEditing,
            keyboardType: TextInputType.phone,
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
              hintText: 'Briefly describe your operation and hiring needs.',
            ),
          ),
          if (_employerProfileEditing) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  onPressed: () =>
                      setState(() => _employerProfileEditing = false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
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
                      headquartersCountry: _employerCountryController.text
                          .trim(),
                      website: _employerWebsiteController.text.trim(),
                      contactName: _employerContactNameController.text.trim(),
                      contactEmail: _employerContactEmailController.text.trim(),
                      contactPhone: _employerContactPhoneController.text.trim(),
                      companyDescription: _employerDescriptionController.text
                          .trim(),
                    );
                    _updateEmployer(updated);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Company profile saved.')),
                    );
                  },
                  child: const Text('Save Changes'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
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
                      'Full Name',
                      _jobSeekerProfile.fullName,
                    ),
                    _buildProfileSummaryRow(
                      'Email',
                      _resolvedJobSeekerEmail(_jobSeekerProfile),
                    ),
                    _buildProfileSummaryRow('Phone', _jobSeekerProfile.phone),
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
        const SizedBox(height: 16),
        Row(
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
            const Spacer(),
            FilledButton.icon(
              onPressed: _createJobListing,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Create Job Listing'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCreateTab() {
    return SingleChildScrollView(
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEmployer = _profileType == ProfileType.employer;
    final tabs = isEmployer
        ? const [
            Tab(text: 'Employer Profile'),
            Tab(text: 'Create Listing'),
            Tab(text: 'Listed Jobs'),
          ]
        : const [
            Tab(text: 'Jobs'),
            Tab(text: 'Search'),
            Tab(text: 'Profile'),
            Tab(text: 'Favorites'),
          ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
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
                      _buildResponsiveTabContent(_buildCreateTab()),
                      _buildResponsiveTabContent(_buildJobsTab()),
                    ]
                  : [
                      _buildResponsiveTabContent(_buildJobsTab()),
                      _buildResponsiveTabContent(_buildSearchTab()),
                      _buildResponsiveTabContent(_buildProfileTab()),
                      _buildResponsiveTabContent(_buildFavoritesTab()),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

class JobDetailsPage extends StatelessWidget {
  final JobListing job;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final JobSeekerProfile? profile;

  const JobDetailsPage({
    super.key,
    required this.job,
    required this.isFavorite,
    required this.onFavorite,
    this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final standardFlightHourEntries = job.flightHoursByType.entries.toList();
    final instructorHourEntries = job.instructorHoursByType.entries.toList();
    final crewLabel = job.id == 'test-all-criteria-job'
        ? null
        : (job.crewRole.toLowerCase() == 'crew'
              ? (job.crewPosition != null && job.crewPosition!.trim().isNotEmpty
                    ? 'Crew Member - ${job.crewPosition}'
                    : 'Crew Member')
              : 'Single Pilot');

    return Scaffold(
      appBar: AppBar(
        title: Text(job.title),
        actions: [
          IconButton(
            icon: Icon(isFavorite ? Icons.star : Icons.star_border),
            tooltip: isFavorite ? 'Remove favorite' : 'Add favorite',
            onPressed: onFavorite,
          ),
        ],
      ),
      body: Container(
        color: Colors.grey.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: SingleChildScrollView(
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
                          const SizedBox(height: 6),
                          Text(
                            '${job.location} • ${job.type}',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (job.salaryRange != null)
                                Chip(label: Text('Salary: ${job.salaryRange}')),
                              if (job.deadlineDate != null)
                                Chip(
                                  label: Text(
                                    'Deadline: ${job.deadlineDate!.year}-${job.deadlineDate!.month.toString().padLeft(2, '0')}-${job.deadlineDate!.day.toString().padLeft(2, '0')}',
                                  ),
                                ),
                              Chip(
                                label: Text(
                                  crewLabel ?? 'Multiple crew options',
                                ),
                              ),
                            ],
                          ),
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
                    if (job.id == 'test-all-criteria-job')
                      _buildDetailSection(
                        context: context,
                        title: 'Position',
                        icon: Icons.person_outline,
                        child: _buildChipWrap(const [
                          Chip(label: Text('Single Pilot')),
                          Chip(label: Text('Crew Member - Captain')),
                          Chip(label: Text('Crew Member - Co-Pilot')),
                        ]),
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
                                  label: Text(canonicalCertificateLabel(cert)),
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
    );
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$matchPercentage% Match',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Chip(
              label: Text(
                isFullMatch
                    ? 'Meets all required criteria'
                    : 'Partial match - review required items',
              ),
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
                children: [
                  Icon(
                    hasIt ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: hasIt ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hasIt ? certLabel : '$certLabel (Not yet met)',
                    style: TextStyle(
                      color: hasIt ? Colors.green : Colors.red,
                      decoration: hasIt ? null : TextDecoration.lineThrough,
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
