import 'dart:math' as math;
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/application.dart';
import 'models/application_feedback.dart';
import 'models/aviation_certificate_utils.dart';
import 'models/aviation_location_catalogs.dart';
import 'models/aviation_option_catalogs.dart';
import 'models/employer_profile.dart';
import 'models/employer_profiles_data.dart';
import 'models/job_listing.dart';
import 'models/job_listing_report.dart';
import 'models/job_listing_template.dart';
import 'models/job_seeker_profile.dart';
import 'repositories/app_repository.dart';
import 'screens/admin_dashboard.dart';
import 'screens/sign_in_screen.dart';
import 'services/app_repository_factory.dart';
import 'services/supabase_admin_repository.dart';
import 'services/supabase_bootstrap.dart';
import 'services/web_image_file_picker.dart';

/// Logical-pixel width below which phone-optimized layouts are applied.
const double kPhoneBreakpoint = 430.0;

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

String _profileRoleLabel(Object? value) {
  if (value is Map) {
    final map = value.cast<Object?, Object?>();
    const candidateKeys = [
      'profile_type',
      'profileType',
      'role',
      'user_role',
      'userRole',
    ];

    for (final key in candidateKeys) {
      final role = map[key]?.toString().trim().toLowerCase() ?? '';
      if (role.isNotEmpty) {
        return role;
      }
    }
    return '';
  }

  return value?.toString().trim().toLowerCase() ?? '';
}

ProfileType _profileTypeFromMetadata(Object? value) {
  final role = _profileRoleLabel(value);
  if (role == 'employer') {
    return ProfileType.employer;
  }
  return ProfileType.jobSeeker;
}

final RegExp _linkifiedUrlPattern = RegExp(
  r'((?:https?:\/\/|www\.)[^\s<>()]+)',
  caseSensitive: false,
);

final RegExp _linkifiedPhonePattern = RegExp(
  r'((?:\+?\d|\(\d)[\d\-\s().]{7,}\d)',
);

bool _isLikelyPhoneToken(String value) {
  final digits = _phoneDigits(value);
  return digits.length >= 10 && digits.length <= 15;
}

String _trimTrailingUrlPunctuation(String value) {
  var trimmed = value;
  const trailingChars = '.,;:!?)]}';
  while (trimmed.isNotEmpty && trailingChars.contains(trimmed[trimmed.length - 1])) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

Uri? _parseLaunchableHttpUri(String rawUrl) {
  final trimmed = _trimTrailingUrlPunctuation(rawUrl.trim());
  if (trimmed.isEmpty) {
    return null;
  }

  final normalized = trimmed.startsWith('http://') || trimmed.startsWith('https://')
      ? trimmed
      : 'https://$trimmed';
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
    return null;
  }

  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return null;
  }
  return uri;
}

class _LinkifiedText extends StatelessWidget {
  const _LinkifiedText({
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
    this.onTapUrl,
    this.onTapPhone,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final ValueChanged<String>? onTapUrl;
  final ValueChanged<String>? onTapPhone;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final linkStyle = baseStyle.copyWith(
      color: Colors.blue,
      decoration: TextDecoration.underline,
      decorationColor: Colors.blue,
    );

    final spans = <InlineSpan>[];
    final matches = <RegExpMatch>[
      ..._linkifiedUrlPattern.allMatches(text),
      ..._linkifiedPhonePattern.allMatches(text),
    ]..sort((a, b) => a.start.compareTo(b.start));

    var start = 0;
    for (final match in matches) {
      if (match.start < start) {
        continue;
      }

      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: baseStyle));
      }

      final matchedText = match.group(0) ?? '';
      if (matchedText.isNotEmpty) {
        final launchTargetUrl = _trimTrailingUrlPunctuation(matchedText);
        final trimmedLower = launchTargetUrl.toLowerCase();
        final hasExplicitUrlPrefix =
          trimmedLower.startsWith('http://') ||
          trimmedLower.startsWith('https://') ||
          trimmedLower.startsWith('www.');
        final isPhoneLink =
          _isLikelyPhoneToken(matchedText) &&
          _parseLaunchablePhoneUri(matchedText) != null;
        final isUrlLink =
          !isPhoneLink &&
          hasExplicitUrlPrefix &&
          _parseLaunchableHttpUri(launchTargetUrl) != null;

        if (isUrlLink) {
          spans.add(
            TextSpan(
              text: matchedText,
              style: linkStyle,
              recognizer: onTapUrl == null
                  ? null
                  : (TapGestureRecognizer()
                      ..onTap = () => onTapUrl!(launchTargetUrl)),
            ),
          );
        } else if (isPhoneLink) {
          spans.add(
            TextSpan(
              text: matchedText,
              style: onTapPhone == null ? baseStyle : linkStyle,
              recognizer: onTapPhone == null
                  ? null
                  : (TapGestureRecognizer()
                      ..onTap = () => onTapPhone!(matchedText)),
            ),
          );
        } else {
          spans.add(TextSpan(text: matchedText, style: baseStyle));
        }
      }
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: baseStyle));
    }

    return RichText(
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(children: spans),
    );
  }
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
          final roleLabel = _profileRoleLabel(session.user.userMetadata);
          final adminEmail = session.user.email?.trim() ?? '';

          if (roleLabel == 'admin') {
            return AdminDashboard(
              adminRepository: SupabaseAdminRepository(
                Supabase.instance.client,
                session.user.id,
              ),
              appRepository: repository,
              adminEmail: adminEmail,
              adminRoleLabel: roleLabel,
              currentView: AdminInterfaceView.admin,
              onSwitchView: (switchContext, view) {
                if (view == AdminInterfaceView.admin) {
                  return;
                }

                final initialType = view == AdminInterfaceView.employer
                    ? ProfileType.employer
                    : ProfileType.jobSeeker;

                Navigator.of(switchContext).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => MyHomePage(
                      title: 'Aviation Job Listings',
                      repository: repository,
                      initialProfileType: initialType,
                    ),
                  ),
                );
              },
            );
          }

          final initialType = _profileTypeFromMetadata(
            session.user.userMetadata,
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
    this.adminDashboardBuilder,
  });

  final String title;
  final AppRepository repository;
  final ProfileType? initialProfileType;
  final Widget Function(
    BuildContext context,
    void Function(BuildContext context, AdminInterfaceView view) onSwitchView,
  )?
  adminDashboardBuilder;

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

bool _isMobileDialPlatform() {
  if (kIsWeb) {
    return false;
  }

  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

Uri? _parseLaunchablePhoneUri(String rawPhone) {
  final trimmed = rawPhone.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final hasLeadingPlus = trimmed.startsWith('+');
  final digits = _phoneDigits(trimmed);
  if (digits.isEmpty) {
    return null;
  }

  final normalized = hasLeadingPlus ? '+$digits' : digits;
  return Uri(scheme: 'tel', path: normalized);
}

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

String _formatFaaRuleDisplay(String rule, String? part135SubType) {
  if (rule == 'Part 135' && part135SubType != null) {
    final normalizedSubType = part135SubType.trim().toLowerCase();
    if (normalizedSubType == 'ifr') {
      return 'Part 135 IFR';
    }
    if (normalizedSubType == 'vfr') {
      return 'Part 135 VFR';
    }
  }
  return rule;
}

String _formatFaaRuleDisplayWithFallback(
  String rule,
  String? part135SubType,
  Map<String, int> flightHours,
) {
  final explicit = _formatFaaRuleDisplay(rule, part135SubType);
  if (explicit != rule) {
    return explicit;
  }

  if (rule != 'Part 135') {
    return rule;
  }

  final total = flightHours['Total Time'] ?? 0;
  final crossCountry = flightHours['Cross-Country'] ?? 0;
  final night = flightHours['Night'] ?? 0;
  final instrument = flightHours['Instrument'] ?? 0;

  final matchesIfr =
      total >= 1200 && crossCountry >= 500 && night >= 100 && instrument >= 75;
  if (matchesIfr) {
    return 'Part 135 IFR';
  }

  final matchesVfr = total >= 500 && crossCountry >= 100 && night >= 25;
  if (matchesVfr) {
    return 'Part 135 VFR';
  }

  return rule;
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

bool _containsInstructorHourLabel(Iterable<String> labels, String hourLabel) {
  final normalizedTarget = normalizeInstructorHourLabel(hourLabel);
  for (final label in labels) {
    if (normalizeInstructorHourLabel(label) == normalizedTarget) {
      return true;
    }
  }
  return false;
}

int _instructorHoursForLabel(Map<String, int> hoursByLabel, String hourLabel) {
  final normalizedTarget = normalizeInstructorHourLabel(hourLabel);
  for (final entry in hoursByLabel.entries) {
    if (normalizeInstructorHourLabel(entry.key) == normalizedTarget) {
      return entry.value;
    }
  }
  return 0;
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

  for (final rating in job.requiredRatings) {
    totalCount++;
    if (profileCertificates.contains(normalizeCertificateName(rating))) {
      matchedCount++;
    } else {
      missingRequirements.add(rating);
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
    final isPreferred = _containsInstructorHourLabel(
      job.preferredInstructorHours,
      requirement.key,
    );
    if (isPreferred) {
      continue;
    }

    totalCount++;
    final profileHours = _instructorHoursForLabel(
      profile.flightHours,
      requirement.key,
    );
    final hasRequirement =
        _containsInstructorHourLabel(
          profile.flightHoursTypes,
          requirement.key,
        ) &&
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

  // Airframe scope compatibility: 'Both' on either side is always compatible.
  if (job.airframeScope != 'Both' && profile.airframeScope != 'Both') {
    totalCount++;
    if (job.airframeScope == profile.airframeScope) {
      matchedCount++;
    } else {
      missingRequirements.add('Airframe Scope: ${job.airframeScope}');
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
  static const List<String> _availableFaaCertificates =
      availableFaaCertificateOptions;

  static const List<String> _availableInstructorCertificates =
      availableInstructorCertificateOptions;

  // --- FAA OPERATIONAL RULES/SCOPE ---
  static const List<String> _availableFaaRules = availableFaaRuleOptions;

    static const List<String> _availableAirframeScopes =
      availableAirframeScopeOptions;

  static const List<String> _availableEmployerFlightHours =
      availableEmployerFlightHourOptions;

    static const List<String> _availableOtherFlightHours =
      availableOtherFlightHourOptions;

    static const List<String> _availableHelicopterHours =
      availableHelicopterHourOptions;

  static const List<String> _availableInstructorHours =
      availableInstructorHourOptions;

  static const List<String> _availableJobTypes = availableJobTypeOptions;

  static const List<String> _availableRatingSelections =
      availableRatingSelectionOptions;

  static const List<String> _availablePayRateMetrics =
      availablePayRateMetricOptions;

  static const List<String> _usStateOptions = usStateOptions;

  static const List<String> _canadaProvinceOptions = canadaProvinceOptions;

  static const List<String> _countryOptions = countryOptions;

  static const List<String> _companyBenefitOptions = [
    'Health Insurance',
    '401K',
    'Relocation Reinbursement',
    'Company Housing',
    'Sign-On Bonus',
    'Longevity Bonus',
    'Flight Benefits',
    'Paid Vacation',
    'Paid Sick Leave',
    'Maternity Leave',
  ];

  static const Map<String, String> _stateProvinceAbbreviations =
      stateProvinceAbbreviations;

  // --- SPECIALTY EXPERIENCE (Future: Consider adding to Job Seeker profile) ---
  static const List<String> _availableSpecialtyExperience =
      availableSpecialtyExperienceOptions;

  // ============================================================================
  // UI CONTROLLERS: Text input fields for forms
  // ============================================================================

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _searchTabController = TextEditingController();
  final TextEditingController _searchTabMatchPercentController =
      TextEditingController(text: '0');
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
  String _searchTabQuery = '';
  String _searchTabTypeFilter = 'all';
  String _searchTabLocationFilter = 'all';
  String _searchTabPositionFilter = 'all';
  String _searchTabFaaRuleFilter = 'all';
  String _searchTabAirframeScopeFilter = 'all';
  String _searchTabSpecialtyFilter = 'all';
  String _searchTabCertificateFilter = 'all';
  String _searchTabRatingFilter = 'all';
  String _searchTabFlightHoursFilter = 'all';
  String _searchTabInstructorHoursFilter = 'all';
  int _searchTabMinimumMatchPercent = 0;
  String _searchTabSort = 'best_match';
  String? _searchTabPendingTypeFilter;
  String? _searchTabPendingLocationFilter;
  String? _searchTabPendingPositionFilter;
  String? _searchTabPendingFaaRuleFilter;
  String? _searchTabPendingAirframeScopeFilter;
  String? _searchTabPendingSpecialtyFilter;
  String? _searchTabPendingInstructorHoursFilter;
  String? _searchTabPendingCertificateFilter;
  String? _searchTabPendingRatingFilter;
  String? _searchTabPendingSort;
  bool _searchTabPrimaryFiltersDrawerOpen = true;
  bool _searchTabEmploymentTypeExpanded = false;
  bool _searchTabPositionExpanded = false;
  bool _searchTabLocationExpanded = false;
  bool _searchTabFaaRuleExpanded = false;
  bool _searchTabAirframeScopeExpanded = false;
  bool _searchTabSpecialtyFilterExpanded = false;
  bool _searchTabInstructionFilterExpanded = false;
  bool _searchTabCertificateExpanded = false;
  bool _searchTabRatingExpanded = false;
  final GlobalKey _searchTabEmploymentTypeHeaderKey = GlobalKey();
  final GlobalKey _searchTabPositionHeaderKey = GlobalKey();
  final GlobalKey _searchTabLocationHeaderKey = GlobalKey();
  final GlobalKey _searchTabFaaRuleHeaderKey = GlobalKey();
  final GlobalKey _searchTabAirframeScopeHeaderKey = GlobalKey();
  final GlobalKey _searchTabCertificateHeaderKey = GlobalKey();
  final GlobalKey _searchTabRatingHeaderKey = GlobalKey();
  final GlobalKey _searchTabInstructionHeaderKey = GlobalKey();
  final GlobalKey _searchTabSpecialtyHeaderKey = GlobalKey();
  final GlobalKey _searchTabPrimaryFiltersCardKey = GlobalKey();
  final GlobalKey _searchTabFiltersHeadingKey = GlobalKey();
  final GlobalKey _topTabsBarKey = GlobalKey();
  final ScrollController _searchTabScrollController = ScrollController();
  bool _searchTabFiltersPinned = false;
  bool _searchTabExternalOnly = false;
  bool _searchTabFlightHoursExpanded = false;
  bool _searchTabFlightHoursOtherExpanded = false;
  bool _searchTabFlightHoursHelicopterExpanded = false;
  bool _searchTabSpecialtyHoursExpanded = false;
  bool _searchTabPicSicExpanded = false;
  final Map<String, int> _searchTabSpecialtyHourMinimums = {};
  String _searchTabFlightHourGroupFilter = 'all';
  final Map<String, int> _searchTabFlightHourMinimums = {};
  final Map<String, int> _searchTabInstructorHourMinimums = {};
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

  static const String _legacyLocalJobSeekerId = 'local_seeker';
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

  String _generateFeedbackId() => 'fb_${DateTime.now().millisecondsSinceEpoch}';

  String _currentJobSeekerId() {
    if (SupabaseBootstrap.isConfigured) {
      final userId = Supabase.instance.client.auth.currentUser?.id.trim() ?? '';
      if (userId.isNotEmpty) {
        return 'seeker_$userId';
      }
    }
    return _legacyLocalJobSeekerId;
  }

  List<String> _jobSeekerIdsForLoad() {
    final currentId = _currentJobSeekerId();
    if (currentId == _legacyLocalJobSeekerId) {
      return [currentId];
    }
    return [currentId, _legacyLocalJobSeekerId];
  }

  Future<List<Application>> _loadApplicationsForCurrentSeeker() async {
    final appsById = <String, Application>{};

    for (final seekerId in _jobSeekerIdsForLoad()) {
      final seekerApps = await _appRepository.getApplicationsBySeeker(seekerId);
      for (final app in seekerApps) {
        final existing = appsById[app.id];
        if (existing == null || app.updatedAt.isAfter(existing.updatedAt)) {
          appsById[app.id] = app;
        }
      }
    }

    return appsById.values.toList();
  }

  Future<Application?> _getLatestApplicationForCurrentSeeker(
    String jobId,
  ) async {
    final apps = await _loadApplicationsForCurrentSeeker();
    final matching = apps.where((app) => app.jobId == jobId).toList()
      ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
    return matching.isEmpty ? null : matching.first;
  }

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
  String _selectedAirframeScope = 'Fixed Wing';
  final List<String> _selectedFaaRules = [];
  String? _part135SubType; // 'ifr' or 'vfr'
  final List<String> _selectedFaaCertificates = [];
  final List<String> _selectedRequiredRatings = [];
  final Map<String, int> _selectedFlightHours = {};
  final Map<String, TextEditingController> _createFlightHourControllers = {};
  final Set<String> _preferredFlightHours = {};
  final Map<String, int> _selectedInstructorHours = {};
  final Set<String> _preferredInstructorHours = {};
  final Map<String, int> _selectedSpecialtyHours = {};
  final Set<String> _preferredSpecialtyHours = {};
  bool _createHoursPicSicExpanded = false;
  bool _createHoursOtherExpanded = false;
  bool _createHoursHelicopterExpanded = false;
  bool _createHoursSpecialtyExpanded = false;
  String _createHoursGroupFilter = 'all';
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
    _syncSearchTabMatchPercentController();
    _fetchJobs();
  }

  void _syncSearchTabMatchPercentController() {
    final text = '$_searchTabMinimumMatchPercent';
    if (_searchTabMatchPercentController.text == text) {
      return;
    }

    _searchTabMatchPercentController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _setSearchTabMinimumMatchPercent(int value) {
    _searchTabMinimumMatchPercent = value.clamp(0, 100);
    _syncSearchTabMatchPercentController();
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
      airframeScope: loadedProfile.airframeScope,
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
      airframeScope: job.airframeScope,
      part135SubType: job.part135SubType,
      description: job.description,
      faaCertificates: _canonicalizeCertificates(job.faaCertificates),
      requiredRatings: List<String>.from(job.requiredRatings),
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
      autoRejectThreshold: job.autoRejectThreshold,
      reapplyWindowDays: job.reapplyWindowDays,
      isExternal: job.isExternal,
      externalApplyUrl: job.externalApplyUrl,
      contactName: job.contactName,
      contactEmail: job.contactEmail,
      companyPhone: job.companyPhone,
      companyUrl: job.companyUrl,
      isActive: job.isActive,
      archivedAt: job.archivedAt,
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
              onTap: () {
                _openDetectedLink(
                  url,
                  failureMessage: 'Could not open the company website.',
                );
              },
              child: _LinkifiedText(
                text: url,
                style: const TextStyle(
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneSummaryRow(String rawPhone) {
    final formatted = _formatPhoneNumber(rawPhone);
    if (formatted.isEmpty) {
      return _buildProfileSummaryRow('Phone', '');
    }

    final enableTap = _isMobileDialPlatform();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              'Phone',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: enableTap
                  ? () {
                      _openPhoneCall(rawPhone);
                    }
                  : null,
              child: Text(
                formatted,
                style: TextStyle(
                  color: enableTap ? Colors.blue : null,
                  decoration: enableTap ? TextDecoration.underline : null,
                  decorationColor: enableTap ? Colors.blue : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExternalListingPhoneCta(JobListing job) {
    final rawPhone = job.companyPhone?.trim() ?? '';
    if (rawPhone.isEmpty) {
      return const SizedBox.shrink();
    }

    final formatted = _formatPhoneNumber(rawPhone);
    final displayPhone = formatted.isNotEmpty ? formatted : rawPhone;
    final canCall =
        _isMobileDialPlatform() && _parseLaunchablePhoneUri(rawPhone) != null;

    if (canCall) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: TextButton.icon(
          onPressed: () => _openPhoneCall(rawPhone),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            alignment: Alignment.centerLeft,
          ),
          icon: const Icon(Icons.phone_outlined, size: 15),
          label: Text(
            'Contact: $displayPhone',
            style: const TextStyle(
              fontSize: 13,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.phone_outlined,
            size: 15,
            color: Colors.grey.shade700,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Contact: $displayPhone',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
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

  Future<void> _openDetectedLink(
    String rawUrl, {
    String failureMessage = 'Could not open this link.',
  }) async {
    final uri = _parseLaunchableHttpUri(rawUrl);
    if (uri == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  Future<void> _openPhoneCall(
    String rawPhone, {
    String failureMessage = 'Could not start a phone call.',
  }) async {
    final uri = _parseLaunchablePhoneUri(rawPhone);
    if (uri == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  Future<void> _contactExternalEmployer(JobListing job) async {
    final rawUrl = job.externalApplyUrl?.trim() ?? '';
    if (rawUrl.isNotEmpty) {
      final uri = _parseLaunchableHttpUri(rawUrl);
      if (uri != null) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Opening external listing. Contact the employer directly to apply.',
                ),
              ),
            );
          }
          return;
        }
      }
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'External listing: contact the employer directly to apply.',
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
                              return Builder(
                                builder: (itemContext) {
                                  final isHighlighted =
                                      AutocompleteHighlightedOption.of(
                                        itemContext,
                                      ) ==
                                      index;

                                  if (isHighlighted) {
                                    SchedulerBinding.instance
                                        .addPostFrameCallback((_) {
                                          Scrollable.ensureVisible(
                                            itemContext,
                                            alignment: 0.5,
                                            duration: Duration.zero,
                                          );
                                        });
                                  }

                                  return Container(
                                    color: isHighlighted
                                        ? Theme.of(
                                            itemContext,
                                          ).colorScheme.primaryContainer
                                        : null,
                                    child: ListTile(
                                      dense: true,
                                      title: Text(_stateProvinceLabel(option)),
                                      onTap: () => onSelected(option),
                                    ),
                                  );
                                },
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
                          onSubmitted: (_) => onFieldSubmitted(),
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
    const allRatings = availableRatingSelectionOptions;
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

  Widget _buildGroupedFlightHoursSummaryCard(JobSeekerProfile profile) {
    Widget chip(String item) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Text(item),
    );

    List<String> hrs(List<String> options, List<String> selectedTypes, Map<String, int> hours) =>
        _hoursSummaryItems(options: options, selectedTypes: selectedTypes, hours: hours);

    const picSicOptions = [
      'Total PIC Time', 'Total SIC Time',
      'PIC Turbine', 'SIC Turbine',
      'PIC Jet', 'SIC Jet',
    ];
    const otherOptions = availableOtherFlightHourOptions;
    const helicopterOptions = availableHelicopterHourOptions;

    final totalTimeItems  = hrs(const ['Total Time'], profile.flightHoursTypes, profile.flightHours);
    final picSicItems     = hrs(picSicOptions, profile.flightHoursTypes, profile.flightHours);
    final otherItems      = hrs(otherOptions, profile.flightHoursTypes, profile.flightHours);
    final helicopterItems = hrs(helicopterOptions, profile.flightHoursTypes, profile.flightHours);
    final specialtyItems  = hrs(_availableSpecialtyExperience, profile.specialtyFlightHours, profile.specialtyFlightHoursMap);
    final instructionItems = hrs(_availableInstructorHours, profile.flightHoursTypes, profile.flightHours);

    final hasAny = totalTimeItems.isNotEmpty || picSicItems.isNotEmpty ||
        otherItems.isNotEmpty || helicopterItems.isNotEmpty || specialtyItems.isNotEmpty || instructionItems.isNotEmpty;

    Widget groupSection(String label, List<String> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: Colors.blueGrey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map(chip).toList(),
          ),
        ],
      );
    }

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
                  'Flight Hours',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!hasAny)
            Text(
              'No flight hour categories selected',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade600,
              ),
            )
          else ...[            
            if (totalTimeItems.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: totalTimeItems.map(chip).toList(),
              ),
            groupSection('PIC/SIC TIME', picSicItems),
            groupSection('OTHER CATEGORIES', otherItems),
            groupSection('SPECIALTY HOURS', specialtyItems),
            groupSection('FLIGHT INSTRUCTION', instructionItems),
            groupSection('HELICOPTER HOURS', helicopterItems),
          ],
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
    final hourLabels = <String>[
      ..._selectedFlightHours.keys,
      ..._selectedInstructorHours.keys,
      ..._selectedSpecialtyHours.keys,
    ];

    if (hourLabels.isEmpty) {
      return 'Add only the hour categories required for the job.';
    }

    final uniqueLabels = <String>[];
    for (final label in hourLabels) {
      if (!uniqueLabels.contains(label)) {
        uniqueLabels.add(label);
      }
    }

    final totalTimeIndex = uniqueLabels.indexOf('Total Time');
    if (totalTimeIndex >= 0) {
      uniqueLabels.removeAt(totalTimeIndex);
      uniqueLabels.insert(0, 'Total Time required');
    }

    final previewLimit = totalTimeIndex >= 0 ? 3 : 2;
    final previewItems = uniqueLabels.take(previewLimit).toList();
    final remaining = uniqueLabels.length - previewItems.length;
    final summary = previewItems.join(', ');

    if (remaining > 0) {
      return '$summary +$remaining more';
    }

    return summary;
  }

  List<String> _requiredInstructorCertificatesForHours(
    Iterable<String> requiredInstructorHourLabels,
  ) {
    final needed = <String>[];

    void addIfMissing(String certificate) {
      if (!needed.contains(certificate)) {
        needed.add(certificate);
      }
    }

    for (final label in requiredInstructorHourLabels) {
      final certificate = _requiredInstructorCertificateForHourLabel(label);
      if (certificate != null) {
        addIfMissing(certificate);
      }
    }

    return needed;
  }

  String? _requiredInstructorCertificateForHourLabel(String hourLabel) {
    final normalized = normalizeInstructorHourLabel(hourLabel);
    if (normalized == flightInstructionCfiHourLabel) {
      return 'Flight Instructor (CFI)';
    }
    if (normalized == 'Instrument (CFII)') {
      return 'Instrument Instructor (CFII)';
    }
    if (normalized == 'Multi-Engine (MEI)') {
      return 'Multi-Engine Instructor (MEI)';
    }
    return null;
  }

  String? _requiredInstructorHourLabelForCertificate(String certificate) {
    switch (certificate) {
      case 'Flight Instructor (CFI)':
        return flightInstructionCfiHourLabel;
      case 'Instrument Instructor (CFII)':
        return 'Instrument (CFII)';
      case 'Multi-Engine Instructor (MEI)':
        return 'Multi-Engine (MEI)';
      default:
        return null;
    }
  }

  bool _isRequiredInstructorHourSelected({
    required String hourLabel,
    required Iterable<String> selectedInstructorHours,
    required Iterable<String> preferredInstructorHours,
  }) {
    final preferred = preferredInstructorHours.toSet();
    final normalizedTarget = normalizeInstructorHourLabel(hourLabel);
    for (final selected in selectedInstructorHours) {
      if (preferred.contains(selected)) {
        continue;
      }
      if (normalizeInstructorHourLabel(selected) == normalizedTarget) {
        return true;
      }
    }
    return false;
  }

  bool _containsInstructorHourLabel(
    Iterable<String> labels,
    String hourLabel,
  ) {
    final normalizedTarget = normalizeInstructorHourLabel(hourLabel);
    for (final label in labels) {
      if (normalizeInstructorHourLabel(label) == normalizedTarget) {
        return true;
      }
    }
    return false;
  }

  int _instructorHoursForLabel(
    Map<String, int> hoursByLabel,
    String hourLabel,
  ) {
    final normalizedTarget = normalizeInstructorHourLabel(hourLabel);
    for (final entry in hoursByLabel.entries) {
      if (normalizeInstructorHourLabel(entry.key) == normalizedTarget) {
        return entry.value;
      }
    }
    return 0;
  }

  Widget _buildRequiredByHoursChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Text(
        'Required by hours',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.orange.shade900,
        ),
      ),
    );
  }

  List<String> _missingImpliedRatings({
    required Iterable<String> selectedRatings,
    required Iterable<String> requiredFlightHourLabels,
    required Iterable<String> requiredSpecialtyHourLabels,
  }) {
    final selected = selectedRatings.toSet();
    final requiredFlight = requiredFlightHourLabels.toSet();
    final requiredSpecialty = requiredSpecialtyHourLabels.toSet();
    final missing = <String>[];

    if (requiredFlight.contains('Multi-engine') &&
        !selected.contains('Multi-Engine Land') &&
        !selected.contains('Multi-Engine Sea')) {
      missing.addAll(const ['Multi-Engine Land', 'Multi-Engine Sea']);
    }

    if (requiredSpecialty.contains('Floatplane') &&
        !selected.contains('Single-Engine Sea') &&
        !selected.contains('Multi-Engine Sea')) {
      missing.addAll(const ['Single-Engine Sea', 'Multi-Engine Sea']);
    }

    final needsHelicopterRating = availableHelicopterHourOptions.any(
      requiredFlight.contains,
    );
    if (needsHelicopterRating && !selected.contains('Helicopter')) {
      missing.add('Helicopter');
    }

    final needsTailwheel =
        requiredSpecialty.contains('Ski-plane') ||
        requiredSpecialty.contains('Tailwheel') ||
        requiredSpecialty.contains('Banner Towing');
    if (needsTailwheel && !selected.contains('Tailwheel Endorsement')) {
      missing.add('Tailwheel Endorsement');
    }

    return missing.toSet().toList();
  }

  List<String> _missingImpliedRatingRuleMessages({
    required Iterable<String> selectedRatings,
    required Iterable<String> requiredFlightHourLabels,
    required Iterable<String> requiredSpecialtyHourLabels,
  }) {
    final selected = selectedRatings.toSet();
    final requiredFlight = requiredFlightHourLabels.toSet();
    final requiredSpecialty = requiredSpecialtyHourLabels.toSet();
    final messages = <String>[];

    if (requiredFlight.contains('Multi-engine') &&
        !selected.contains('Multi-Engine Land') &&
        !selected.contains('Multi-Engine Sea')) {
      messages.add(
        'Multi-engine hours require Multi-Engine Land or Multi-Engine Sea',
      );
    }

    if (requiredSpecialty.contains('Floatplane') &&
        !selected.contains('Single-Engine Sea') &&
        !selected.contains('Multi-Engine Sea')) {
      messages.add(
        'Floatplane hours require Single-Engine Sea or Multi-Engine Sea',
      );
    }

    final needsHelicopterRating = availableHelicopterHourOptions.any(
      requiredFlight.contains,
    );
    if (needsHelicopterRating && !selected.contains('Helicopter')) {
      messages.add('Helicopter hours require Helicopter rating');
    }

    final needsTailwheel =
        requiredSpecialty.contains('Ski-plane') ||
        requiredSpecialty.contains('Tailwheel') ||
        requiredSpecialty.contains('Banner Towing');
    if (needsTailwheel && !selected.contains('Tailwheel Endorsement')) {
      messages.add(
        'Ski-plane, Tailwheel, or Banner Towing hours require Tailwheel Endorsement',
      );
    }

    return messages;
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
    bool? isSatisfied,
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
              if (isSatisfied == true)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Tooltip(
                    message: 'Minimum requirement met',
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    ),
                  ),
                ),
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
    Widget Function(String option)? titleBuilder,
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
            title: titleBuilder?.call(option) ?? Text(option),
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
    String? expandedQualificationsSection;
    final typeRatingsController = TextEditingController(
      text: draftProfile.typeRatings.join(', '),
    );
    final aircraftController = TextEditingController(
      text: draftProfile.aircraftFlown.join(', '),
    );
    var seekerHoursPicSicExpanded = false;
    var seekerHoursOtherExpanded = false;
    var seekerHoursHelicopterExpanded = false;
    var seekerHoursSpecialtyExpanded = false;
    var seekerHoursGroupFilter = 'all';

    final updatedProfile = await Navigator.of(context).push<JobSeekerProfile>(
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, setPageState) {
            const landRatings = landRatingSelectionOptions;
            const seaRatings = seaRatingSelectionOptions;
            const tailwheelRating = tailwheelRatingSelectionOptions;
            const rotorRatings = rotorRatingSelectionOptions;
            const otherRatings = otherRatingSelectionOptions;
            final seekerMissingImpliedRatings = _missingImpliedRatings(
              selectedRatings: draftProfile.faaCertificates,
              requiredFlightHourLabels: draftProfile.flightHoursTypes,
              requiredSpecialtyHourLabels: draftProfile.specialtyFlightHours,
            ).toSet();
            final seekerInstrumentHoursSelected =
                draftProfile.flightHoursTypes.contains('Instrument');
            final seekerMissingInstrumentRating =
                seekerInstrumentHoursSelected &&
                !draftProfile.faaCertificates.contains(
                  'Instrument Rating (IFR)',
                );
            final seekerMissingRatingsByHours = {
              ...seekerMissingImpliedRatings,
              if (seekerMissingInstrumentRating) 'Instrument Rating (IFR)',
            };
            final seekerHasHoursTriggeredRatingRules =
                _missingImpliedRatingRuleMessages(
                      selectedRatings: const <String>[],
                      requiredFlightHourLabels: draftProfile.flightHoursTypes,
                      requiredSpecialtyHourLabels: draftProfile.specialtyFlightHours,
                    ).isNotEmpty ||
                seekerInstrumentHoursSelected;
            final selectedInstructorHourLabels =
                _availableInstructorHours
                    .where(
                      (label) =>
                          _instructorHoursForLabel(
                            draftProfile.flightHours,
                            label,
                          ) >
                          0,
                    )
                    .toList();
            final seekerInstructorHoursSelected =
                selectedInstructorHourLabels.isNotEmpty;
            final seekerMissingInstructorCerts =
                _requiredInstructorCertificatesForHours(
                      selectedInstructorHourLabels,
                    )
                    .where((cert) => !draftProfile.faaCertificates.contains(cert))
                    .toSet();
            final seekerCertificatesSatisfied = draftProfile.faaCertificates.any(
              _availableFaaCertificates.contains,
            );
            final seekerRatingsSatisfied =
                draftProfile.faaCertificates.any(
                  _availableRatingSelections.contains,
                ) &&
                seekerMissingRatingsByHours.isEmpty;
            final seekerAirframeScopeSatisfied = _availableAirframeScopes
              .contains(draftProfile.airframeScope);
            final seekerHoursSatisfied =
                (draftProfile.flightHours['Total Time'] ?? 0) > 0;

            Widget airframeScopeSelector() {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableAirframeScopes
                    .map(
                      (scope) => ChoiceChip(
                        label: Text(scope),
                        selected: draftProfile.airframeScope == scope,
                        onSelected: (_) {
                          setPageState(() {
                            draftProfile = draftProfile.copyWith(
                              airframeScope: scope,
                            );
                          });
                        },
                      ),
                    )
                    .toList(),
              );
            }

            Widget ratingTitle(String rating) {
              final isMissingImpliedRating =
                  seekerMissingRatingsByHours.contains(rating) &&
                  !draftProfile.faaCertificates.contains(rating);
              if (!isMissingImpliedRating) {
                return Text(rating);
              }

              return Row(
                children: [
                  Expanded(
                    child: Text(
                      rating,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildRequiredByHoursChip(),
                ],
              );
            }

            Widget instructorCertTitle(String cert) {
              final showRequiredByHoursChip =
                  seekerMissingInstructorCerts.contains(cert);
              if (!showRequiredByHoursChip) {
                return Text(cert);
              }

              return Row(
                children: [
                  Expanded(
                    child: Text(
                      cert,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildRequiredByHoursChip(),
                ],
              );
            }

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
              titleBuilder: ratingTitle,
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

            void updateDraftFlightHours(String label, int value) {
              final newHours = Map<String, int>.from(draftProfile.flightHours);
              final newTypes = List<String>.from(draftProfile.flightHoursTypes);
              if (value <= 0) {
                newHours.remove(label);
                newTypes.remove(label);
              } else {
                newHours[label] = value;
                if (!newTypes.contains(label)) {
                  newTypes.add(label);
                }
              }
              draftProfile = draftProfile.copyWith(
                flightHours: newHours,
                flightHoursTypes: newTypes,
              );
            }

            void updateDraftSpecialtyHours(String label, int value) {
              final newHours = Map<String, int>.from(
                draftProfile.specialtyFlightHoursMap,
              );
              final newTypes = List<String>.from(
                draftProfile.specialtyFlightHours,
              );
              if (value <= 0) {
                newHours.remove(label);
                newTypes.remove(label);
              } else {
                newHours[label] = value;
                if (!newTypes.contains(label)) {
                  newTypes.add(label);
                }
              }
              draftProfile = draftProfile.copyWith(
                specialtyFlightHoursMap: newHours,
                specialtyFlightHours: newTypes,
              );
            }

            Widget seekerHourInputRow({
              required String label,
              required int value,
              required void Function(int value) onChanged,
            }) {
              return _SearchHourSliderRow(
                label: label,
                sliderMax: _hourSliderMax(label),
                value: value,
                onChanged: (val) => setPageState(() => onChanged(val)),
              );
            }

            Widget seekerCategorizedHoursSection() {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MINIMUM EXPERIENCE (HOURS)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                    ),
                  ),
                  const SizedBox(height: 6),
                  seekerHourInputRow(
                    label: 'Total Time',
                    value: draftProfile.flightHours['Total Time'] ?? 0,
                    onChanged: (val) => updateDraftFlightHours('Total Time', val),
                  ),
                  ExpansionTile(
                    key: ValueKey(
                      'seeker-hours-picsic-${seekerHoursPicSicExpanded ? 'open' : 'closed'}',
                    ),
                    initiallyExpanded: seekerHoursPicSicExpanded,
                    onExpansionChanged: (expanded) {
                      setPageState(() => seekerHoursPicSicExpanded = expanded);
                    },
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'PIC / SIC TIME',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Text(
                              'Show:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Wrap(
                              spacing: 6,
                              children: [
                                ChoiceChip(
                                  label: const Text('ALL'),
                                  selected: seekerHoursGroupFilter == 'all',
                                  onSelected: (_) => setPageState(
                                    () => seekerHoursGroupFilter = 'all',
                                  ),
                                ),
                                ChoiceChip(
                                  label: const Text('PIC'),
                                  selected: seekerHoursGroupFilter == 'pic',
                                  onSelected: (_) => setPageState(
                                    () => seekerHoursGroupFilter = 'pic',
                                  ),
                                ),
                                ChoiceChip(
                                  label: const Text('SIC'),
                                  selected: seekerHoursGroupFilter == 'sic',
                                  onSelected: (_) => setPageState(
                                    () => seekerHoursGroupFilter = 'sic',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (seekerHoursGroupFilter != 'sic')
                        seekerHourInputRow(
                          label: 'Total PIC Time',
                          value: draftProfile.flightHours['Total PIC Time'] ?? 0,
                          onChanged: (val) =>
                              updateDraftFlightHours('Total PIC Time', val),
                        ),
                      if (seekerHoursGroupFilter != 'pic')
                        seekerHourInputRow(
                          label: 'Total SIC Time',
                          value: draftProfile.flightHours['Total SIC Time'] ?? 0,
                          onChanged: (val) =>
                              updateDraftFlightHours('Total SIC Time', val),
                        ),
                      if (seekerHoursGroupFilter != 'sic')
                        seekerHourInputRow(
                          label: 'PIC Turbine',
                          value: draftProfile.flightHours['PIC Turbine'] ?? 0,
                          onChanged: (val) =>
                              updateDraftFlightHours('PIC Turbine', val),
                        ),
                      if (seekerHoursGroupFilter != 'pic')
                        seekerHourInputRow(
                          label: 'SIC Turbine',
                          value: draftProfile.flightHours['SIC Turbine'] ?? 0,
                          onChanged: (val) =>
                              updateDraftFlightHours('SIC Turbine', val),
                        ),
                      if (seekerHoursGroupFilter != 'sic')
                        seekerHourInputRow(
                          label: 'PIC Jet',
                          value: draftProfile.flightHours['PIC Jet'] ?? 0,
                          onChanged: (val) => updateDraftFlightHours('PIC Jet', val),
                        ),
                      if (seekerHoursGroupFilter != 'pic')
                        seekerHourInputRow(
                          label: 'SIC Jet',
                          value: draftProfile.flightHours['SIC Jet'] ?? 0,
                          onChanged: (val) => updateDraftFlightHours('SIC Jet', val),
                        ),
                    ],
                  ),
                  ExpansionTile(
                    key: ValueKey(
                      'seeker-hours-other-${seekerHoursOtherExpanded ? 'open' : 'closed'}',
                    ),
                    initiallyExpanded: seekerHoursOtherExpanded,
                    onExpansionChanged: (expanded) {
                      setPageState(() => seekerHoursOtherExpanded = expanded);
                    },
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'OTHER CATEGORIES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                    children: [
                      for (final label in _availableOtherFlightHours)
                        seekerHourInputRow(
                          label: label,
                          value: draftProfile.flightHours[label] ?? 0,
                          onChanged: (val) => updateDraftFlightHours(label, val),
                        ),
                    ],
                  ),
                  ExpansionTile(
                    key: ValueKey(
                      'seeker-hours-specialty-${seekerHoursSpecialtyExpanded ? 'open' : 'closed'}',
                    ),
                    initiallyExpanded: seekerHoursSpecialtyExpanded,
                    onExpansionChanged: (expanded) {
                      setPageState(
                        () => seekerHoursSpecialtyExpanded = expanded,
                      );
                    },
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'SPECIALTY HOURS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                    children: _availableSpecialtyExperience
                        .map(
                          (label) => seekerHourInputRow(
                            label: label,
                            value: draftProfile.specialtyFlightHoursMap[label] ?? 0,
                            onChanged: (val) =>
                                updateDraftSpecialtyHours(label, val),
                          ),
                        )
                        .toList(),
                  ),
                  ExpansionTile(
                    key: ValueKey(
                      'seeker-hours-helicopter-${seekerHoursHelicopterExpanded ? 'open' : 'closed'}',
                    ),
                    initiallyExpanded: seekerHoursHelicopterExpanded,
                    onExpansionChanged: (expanded) {
                      setPageState(() => seekerHoursHelicopterExpanded = expanded);
                    },
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'HELICOPTER HOURS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                    children: [
                      for (final label in _availableHelicopterHours)
                        seekerHourInputRow(
                          label: label,
                          value: draftProfile.flightHours[label] ?? 0,
                          onChanged: (val) => updateDraftFlightHours(label, val),
                        ),
                    ],
                  ),
                ],
              );
            }

            Widget qualificationSection({
              required String sectionKey,
              required String title,
              required String subtitle,
              required IconData icon,
              required Widget child,
              bool? isSatisfied,
            }) {
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
                    title: Row(
                      children: [
                        Icon(icon, size: 18, color: Colors.blueGrey.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isSatisfied == true)
                          const Tooltip(
                            message: 'Minimum requirement met',
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 20,
                            ),
                          ),
                      ],
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
                  ) ||
                  draftProfile.airframeScope != _jobSeekerProfile.airframeScope;
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
                        sectionKey: 'AirframeScope',
                        title: seekerAirframeScopeSatisfied
                          ? 'Airframe Scope'
                          : 'Airframe Scope *',
                        isSatisfied: seekerAirframeScopeSatisfied,
                        subtitle:
                          'Select whether your experience is fixed wing, helicopter, or both.',
                        icon: Icons.flight_outlined,
                        child: airframeScopeSelector(),
                      ),
                      qualificationSection(
                        sectionKey: 'Certificates',
                        title: seekerCertificatesSatisfied
                            ? 'Certificates'
                            : 'Certificates *',
                        isSatisfied: seekerCertificatesSatisfied,
                        subtitle: 'Select FAA certificates you hold.',
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
                          ],
                        ),
                      ),
                      qualificationSection(
                        sectionKey: 'Ratings',
                        title: seekerHasHoursTriggeredRatingRules
                          ? seekerRatingsSatisfied
                            ? 'Ratings'
                            : seekerMissingImpliedRatings.isNotEmpty
                            ? 'Ratings * (Review implied ratings)'
                            : 'Ratings *'
                          : 'Ratings (Optional)',
                        isSatisfied: seekerRatingsSatisfied,
                        subtitle: seekerHasHoursTriggeredRatingRules
                          ? seekerMissingRatingsByHours.isNotEmpty
                            ? 'Ratings marked Required by hours should be selected.'
                            : 'Required ratings are satisfied for selected hours.'
                          : 'Add airframe/rating details for matching (optional).',
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
                        title: seekerHoursSatisfied
                          ? 'Hours and Specialty Experience'
                          : 'Hours and Specialty Experience *',
                        isSatisfied: seekerHoursSatisfied,
                        subtitle:
                            'Select categories and add your logged hours.',
                        icon: Icons.schedule_outlined,
                        child: seekerCategorizedHoursSection(),
                      ),
                      qualificationSection(
                        sectionKey: 'InstructorCertificates',
                        title: () {
                            final hasCerts = draftProfile.faaCertificates
                                .any(_availableInstructorCertificates.contains);
                            final hasHours = seekerInstructorHoursSelected;
                            if (!hasCerts && !hasHours) {
                              return 'Instructor Certificates and Hours (Optional)';
                            }
                            if (seekerInstructorHoursSelected &&
                                seekerMissingInstructorCerts.isNotEmpty) {
                              return 'Instructor Certificates and Hours *';
                            }
                            return 'Instructor Certificates and Hours';
                          }(),
                        isSatisfied: seekerInstructorHoursSelected
                            ? seekerMissingInstructorCerts.isEmpty
                            : null,
                        subtitle: seekerInstructorHoursSelected
                            ? seekerMissingInstructorCerts.isNotEmpty
                                  ? 'Review credentials required by selected instructor hours.'
                                  : 'Required instructor credentials are satisfied for selected hours.'
                            : 'Select instructor credentials you currently hold (optional unless instructor hours are entered).',
                        icon: Icons.school_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildCheckboxCard(
                              options: _availableInstructorCertificates,
                              titleBuilder: instructorCertTitle,
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
                            const SizedBox(height: 12),
                            const Text(
                              'INSTRUCTION HOURS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ..._availableInstructorHours.map(
                              (label) => seekerHourInputRow(
                                label: label,
                                value: draftProfile.flightHours[label] ?? 0,
                                onChanged: (val) =>
                                    updateDraftFlightHours(label, val),
                              ),
                            ),
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
      flightExperience: ['Total PIC Time', 'Instruction', 'Multi-engine'],
      flightHours: const {'Total PIC Time': 500, 'Instruction': 250, 'Multi-engine': 150},
      preferredFlightHours: const ['Total SIC Time'],
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
      preferredFlightHours: const ['Total PIC Time'],
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
      flightExperience: ['Total PIC Time', 'Multi-engine'],
      flightHours: const {'Total PIC Time': 1200, 'Multi-engine': 400},
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
    _searchTabController.dispose();
    _searchTabMatchPercentController.dispose();
    _searchTabScrollController.dispose();
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
      _sortedLowerTrimmed(job.requiredRatings).join('|'),
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
      airframeScope: _selectedAirframeScope,
      description: _createDescriptionController.text.trim(),
      faaCertificates: List<String>.from(_selectedFaaCertificates),
      requiredRatings: List<String>.from(_selectedRequiredRatings),
      typeRatingsRequired: typeRatingsRequired,
      faaRules: _selectedFaaRules.isNotEmpty ? [_selectedFaaRules.first] : [],
      part135SubType: _part135SubType,
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
      autoRejectThreshold: _createAutoRejectEnabled
          ? _createAutoRejectThreshold
          : 0,
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
        _selectedAirframeScope = job.airframeScope;

      _selectedFaaRules
        ..clear()
        ..addAll(job.faaRules.take(1));
      _part135SubType = job.part135SubType;
      _selectedFaaCertificates
        ..clear()
        ..addAll(job.faaCertificates);
      _selectedRequiredRatings
        ..clear()
        ..addAll(job.requiredRatings);
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
      _createAutoRejectThreshold = job.autoRejectThreshold > 0
          ? job.autoRejectThreshold
          : 65;
      _createReapplyWindowDays = job.reapplyWindowDays;
      _createReapplyWindowDaysController.text = job.reapplyWindowDays
          .toString();

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
                if (listing.requiredRatings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Required Ratings',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: listing.requiredRatings
                        .map((rating) => Chip(label: Text(rating)))
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
    if (_editingTemplateId != null) {
      _closeTemplateEditor();
      DefaultTabController.maybeOf(context)?.animateTo(3);
    }
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
        airframeScope: job.airframeScope,
        part135SubType: job.part135SubType,
        description: job.description,
        faaCertificates: List<String>.from(job.faaCertificates),
        requiredRatings: List<String>.from(job.requiredRatings),
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
        autoRejectThreshold: job.autoRejectThreshold,
        reapplyWindowDays: job.reapplyWindowDays,
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

  List<String> get _searchTabTypeOptions {
    final listingTypes = <String>{
      for (final job in _visibleJobs)
        if (job.type.trim().isNotEmpty) job.type.trim(),
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final canonicalTypes = List<String>.from(_availableJobTypes)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final merged = <String>{...canonicalTypes, ...listingTypes}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ['all', ...merged];
  }

  List<String> get _searchTabLocationOptions {
    final listingLocations = <String>{
      for (final job in _visibleJobs)
        if (job.location.trim().isNotEmpty) job.location.trim(),
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final canonicalLocations = <String>[
      ..._countryOptions,
      'International',
      'Remote',
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final merged = <String>{...canonicalLocations, ...listingLocations}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ['all', ...merged];
  }

  List<String> get _searchTabPositionOptions {
    return const [
      'all',
      'Single Pilot',
      'Crew Member: Captain',
      'Crew Member: Co-Pilot',
    ];
  }

  List<String> get _searchTabFaaRuleOptions {
    return const ['all', 'Part 121', 'Part 135 IFR', 'Part 135 VFR', 'Part 91'];
  }

  List<String> get _searchTabAirframeScopeOptions {
    return const ['all', 'Fixed Wing', 'Helicopter', 'Both'];
  }

  List<String> get _searchTabCertificateOptions {
    final canonical = <String>{
      ..._availableFaaCertificates,
      ..._availableInstructorCertificates,
    };
    final listingValues = <String>{
      for (final job in _visibleJobs)
        ...job.faaCertificates.where((cert) => cert.trim().isNotEmpty),
    };
    final merged = <String>{...canonical, ...listingValues}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['all', ...merged];
  }

  List<String> get _searchTabRatingOptions {
    final canonical = <String>{..._availableRatingSelections};
    final listingValues = <String>{
      for (final job in _visibleJobs)
        ...job.requiredRatings.where((rating) => rating.trim().isNotEmpty),
    };
    final merged = <String>{...canonical, ...listingValues}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['all', ...merged];
  }

  List<String> get _searchTabSpecialtyOptions {
    final listingValues = <String>{
      for (final job in _visibleJobs)
        ...job.specialtyHoursByType.keys.where((value) => value.trim().isNotEmpty),
    };
    final canonical = <String>{
      ..._availableSpecialtyExperience,
      'Low-Time Jobs',
      'Mid-Time Jobs',
    };
    final merged = <String>{...canonical, ...listingValues}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['all', ...merged];
  }

  List<String> get _searchTabFlightHoursOptions {
    return ['all', ..._availableEmployerFlightHours];
  }

  List<String> get _searchTabInstructorHoursOptions {
    return ['all', ..._availableInstructorHours];
  }

  bool _matchesSearchTabPositionFilter(JobListing job, String filterValue) {
    final selected = filterValue.trim().toLowerCase();
    if (selected == 'all') {
      return true;
    }

    final crewRole = job.crewRole.trim().toLowerCase();
    final crewPosition = (job.crewPosition ?? '').trim().toLowerCase();

    if (selected == 'single pilot') {
      return crewRole == 'single pilot';
    }
    if (selected == 'crew member: captain') {
      return crewRole == 'crew' && crewPosition == 'captain';
    }
    if (selected == 'crew member: co-pilot') {
      return crewRole == 'crew' && crewPosition == 'co-pilot';
    }
    return false;
  }

  bool _matchesSearchTabLocationFilter(String jobLocation, String filterValue) {
    final selected = filterValue.trim().toLowerCase();
    if (selected == 'all') {
      return true;
    }

    final rawLocation = jobLocation.trim();
    if (rawLocation.isEmpty) {
      return false;
    }

    final location = rawLocation.toLowerCase();
    if (location == selected) {
      return true;
    }

    if (selected == 'remote') {
      return location.contains('remote');
    }

    final parts = location
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final trailing = parts.isEmpty ? location : parts.last;

    final usStateNames = _usStateOptions
        .map((name) => name.toLowerCase())
        .toSet();
    final usStateAbbreviations = _usStateOptions
        .map((name) => (_stateProvinceAbbreviations[name] ?? '').toLowerCase())
        .where((abbr) => abbr.isNotEmpty)
        .toSet();
    final canadaProvinceNames = _canadaProvinceOptions
        .map((name) => name.toLowerCase())
        .toSet();
    final canadaProvinceAbbreviations = _canadaProvinceOptions
        .map((name) => (_stateProvinceAbbreviations[name] ?? '').toLowerCase())
        .where((abbr) => abbr.isNotEmpty)
        .toSet();

    final isUsLike =
        location.contains('usa') ||
        location.contains('united states') ||
        usStateNames.contains(trailing) ||
        usStateAbbreviations.contains(trailing) ||
        usStateNames.contains(location) ||
        usStateAbbreviations.contains(location);

    final isCanadaLike =
        location.contains('canada') ||
        canadaProvinceNames.contains(trailing) ||
        canadaProvinceAbbreviations.contains(trailing) ||
        canadaProvinceNames.contains(location) ||
        canadaProvinceAbbreviations.contains(location);

    if (selected == 'international') {
      if (location.contains('international')) {
        return true;
      }
      if (location.contains('remote')) {
        return false;
      }
      return !isUsLike && !isCanadaLike;
    }

    if (selected == 'usa') {
      return isUsLike;
    }

    if (selected == 'canada') {
      return isCanadaLike;
    }

    return location == selected;
  }

  bool _matchesSearchTabFaaRuleFilter(JobListing job, String filterValue) {
    final selected = filterValue.trim().toLowerCase();
    if (selected == 'all') {
      return true;
    }

    if (selected.startsWith('part 135 ifr') ||
        selected.startsWith('part 135 vfr')) {
      if (!job.faaRules.contains('Part 135')) {
        return false;
      }
      final normalized = _formatFaaRuleDisplayWithFallback(
        'Part 135',
        job.part135SubType,
        job.flightHours,
      ).toLowerCase();
      return normalized == selected;
    }

    return job.faaRules.any((rule) => rule.trim().toLowerCase() == selected);
  }

  bool _isLowTimeJob(JobListing job) {
    final totalTimeRequirement = job.flightHoursByType['Total Time'] ?? 0;
    return totalTimeRequirement > 0 && totalTimeRequirement <= 500;
  }

  bool _isMidTimeJob(JobListing job) {
    final totalTimeRequirement = job.flightHoursByType['Total Time'] ?? 0;
    return totalTimeRequirement >= 501 && totalTimeRequirement <= 1499;
  }

  bool _matchesSearchTabSpecialtyFilter(JobListing job, String filterValue) {
    final selected = filterValue.trim().toLowerCase();
    if (selected == 'all') {
      return true;
    }
    if (selected == 'low-time jobs') {
      return _isLowTimeJob(job);
    }
    if (selected == 'mid-time jobs') {
      return _isMidTimeJob(job);
    }

    return job.specialtyHoursByType.keys.any(
      (key) => key.trim().toLowerCase() == selected,
    );
  }

  Set<String> _decodeSearchTabMultiFilter(
    String rawValue,
    List<String> options,
  ) {
    final byLower = {
      for (final option in options) option.toLowerCase(): option,
    };
    final allOption = byLower['all'];

    if (allOption == null) {
      return {};
    }

    final trimmed = rawValue.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'all') {
      return {allOption};
    }

    final selected = trimmed
        .split('|')
        .map((part) => part.trim().toLowerCase())
        .where((part) => part.isNotEmpty)
        .map((part) => byLower[part])
        .whereType<String>()
        .toSet();

    if (selected.isEmpty) {
      return {allOption};
    }

    selected.remove(allOption);
    return selected.isEmpty ? {allOption} : selected;
  }

  String _encodeSearchTabMultiFilter(Set<String> selected) {
    final cleaned = selected
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    if (cleaned.isEmpty || cleaned.contains('all')) {
      return 'all';
    }

    final sorted = cleaned.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted.join('|');
  }

  List<JobListing> get _searchTabFilteredJobs {
    final typeFilters = _decodeSearchTabMultiFilter(
      _searchTabTypeFilter,
      _searchTabTypeOptions,
    );
    final locationFilter =
        _searchTabLocationOptions.contains(_searchTabLocationFilter)
        ? _searchTabLocationFilter
        : 'all';
    final positionFilters = _decodeSearchTabMultiFilter(
      _searchTabPositionFilter,
      _searchTabPositionOptions,
    );
    final faaRuleFilters = _decodeSearchTabMultiFilter(
      _searchTabFaaRuleFilter,
      _searchTabFaaRuleOptions,
    );
    final airframeScopeFilters = _decodeSearchTabMultiFilter(
      _searchTabAirframeScopeFilter,
      _searchTabAirframeScopeOptions,
    );
    final specialtyFilters = _decodeSearchTabMultiFilter(
      _searchTabSpecialtyFilter,
      _searchTabSpecialtyOptions,
    );
    final certificateFilters = _decodeSearchTabMultiFilter(
      _searchTabCertificateFilter,
      _searchTabCertificateOptions,
    );
    final ratingFilters = _decodeSearchTabMultiFilter(
      _searchTabRatingFilter,
      _searchTabRatingOptions,
    );
    final flightHoursFilter =
        _searchTabFlightHoursOptions.contains(_searchTabFlightHoursFilter)
        ? _searchTabFlightHoursFilter
        : 'all';
    final instructorHoursFilters = _decodeSearchTabMultiFilter(
      _searchTabInstructorHoursFilter,
      _searchTabInstructorHoursOptions,
    );

    final query = _searchTabQuery.toLowerCase();

    final filtered = _visibleJobs.where((job) {
      if (_searchTabExternalOnly && !job.isExternal) {
        return false;
      }

      if (!typeFilters.contains('all') &&
          !typeFilters.contains(job.type.trim())) {
        return false;
      }

      if (!_matchesSearchTabLocationFilter(job.location, locationFilter)) {
        return false;
      }

      if (!positionFilters.contains('all') &&
          !positionFilters.any(
            (filterValue) => _matchesSearchTabPositionFilter(job, filterValue),
          )) {
        return false;
      }

      if (!faaRuleFilters.contains('all') &&
          !faaRuleFilters.any(
            (filterValue) => _matchesSearchTabFaaRuleFilter(job, filterValue),
          )) {
        return false;
      }

      if (!airframeScopeFilters.contains('all') &&
          !airframeScopeFilters.contains(job.airframeScope)) {
        return false;
      }

      if (!specialtyFilters.contains('all') &&
          !specialtyFilters.any(
            (filterValue) => _matchesSearchTabSpecialtyFilter(job, filterValue),
          )) {
        return false;
      }

      if (!certificateFilters.contains('all') &&
          !certificateFilters.any(job.faaCertificates.contains)) {
        return false;
      }

      if (!ratingFilters.contains('all') &&
          !ratingFilters.any(job.requiredRatings.contains)) {
        return false;
      }

      if (flightHoursFilter != 'all' &&
          !job.flightHoursByType.containsKey(flightHoursFilter)) {
        return false;
      }

      if (!instructorHoursFilters.contains('all') &&
          !instructorHoursFilters.any(job.instructorHoursByType.containsKey)) {
        return false;
      }

      for (final entry in _searchTabFlightHourMinimums.entries) {
        if (entry.value > 0 &&
            (job.flightHoursByType[entry.key] ?? 0) < entry.value) {
          return false;
        }
      }

      for (final entry in _searchTabInstructorHourMinimums.entries) {
        if (entry.value > 0 &&
            (job.instructorHoursByType[entry.key] ?? 0) < entry.value) {
          return false;
        }
      }

      for (final entry in _searchTabSpecialtyHourMinimums.entries) {
        if (entry.value > 0 &&
            (job.specialtyHoursByType[entry.key] ?? 0) < entry.value) {
          return false;
        }
      }

      if (query.isNotEmpty) {
        final searchableFields = [
          job.title,
          job.company,
          job.location,
          job.type,
          job.description,
          job.crewRole,
          job.crewPosition ?? '',
          ...job.faaRules,
          ...job.faaCertificates,
          ...job.requiredRatings,
          ...job.typeRatingsRequired,
          ...job.aircraftFlown,
        ];
        final matchesQuery = searchableFields.any(
          (value) => value.toLowerCase().contains(query),
        );
        if (!matchesQuery) {
          return false;
        }
      }

      final percent = _evaluateJobMatch(job).matchPercentage;
      if (percent < _searchTabMinimumMatchPercent) {
        return false;
      }

      return true;
    }).toList();

    filtered.sort((a, b) {
      switch (_searchTabSort) {
        case 'newest':
          final aDate = a.updatedAt ?? a.createdAt;
          final bDate = b.updatedAt ?? b.createdAt;
          if (aDate != null && bDate != null) {
            return bDate.compareTo(aDate);
          }
          if (aDate != null) {
            return -1;
          }
          if (bDate != null) {
            return 1;
          }
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case 'deadline':
          final aDate = a.deadlineDate;
          final bDate = b.deadlineDate;
          if (aDate != null && bDate != null) {
            return aDate.compareTo(bDate);
          }
          if (aDate != null) {
            return -1;
          }
          if (bDate != null) {
            return 1;
          }
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case 'company':
          return a.company.toLowerCase().compareTo(b.company.toLowerCase());
        default:
          final matchCompare = _evaluateJobMatch(
            b,
          ).matchPercentage.compareTo(_evaluateJobMatch(a).matchPercentage);
          if (matchCompare != 0) {
            return matchCompare;
          }
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
    });

    return filtered;
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
    final wasFavorite = _favoriteIds.contains(job.id);

    setState(() {
      if (wasFavorite) {
        _favoriteIds.remove(job.id);
      } else {
        _favoriteIds.add(job.id);
      }
    });
    _saveFavorites();

    if (!wasFavorite && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${job.title} added to favorites.')),
      );
    }
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
          onReport: () => _reportJobListing(job),
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
    final apps = await _loadApplicationsForCurrentSeeker();
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
    final normalizedApps = await _applyEmployerAutoRejectThresholds(apps);
    if (!mounted) {
      return;
    }
    setState(() {
      _employerApplications = normalizedApps;
    });
  }

  Future<List<Application>> _applyEmployerAutoRejectThresholds(
    List<Application> apps,
  ) async {
    final jobsById = {for (final job in _allJobs) job.id: job};
    final updatedApps = <Application>[];
    var hasUpdates = false;

    for (final app in apps) {
      final job = jobsById[app.jobId];
      final threshold = job?.autoRejectThreshold ?? 0;
      final shouldAutoReject =
          app.status == Application.statusApplied &&
          threshold > 0 &&
          app.matchPercentage < threshold;

      if (!shouldAutoReject) {
        updatedApps.add(app);
        continue;
      }

      await _appRepository.updateApplicationStatus(
        app.id,
        Application.statusRejected,
      );

      updatedApps.add(
        app.copyWith(
          status: Application.statusRejected,
          updatedAt: DateTime.now(),
        ),
      );
      hasUpdates = true;
    }

    if (hasUpdates) {
      await _loadMyApplications();
    }

    return updatedApps;
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
      final existing = await _getLatestApplicationForCurrentSeeker(job.id);
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
      final applicantName =
          JobSeekerProfile.combineName(
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
        jobSeekerId: _currentJobSeekerId(),
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
        applicantFlightHours: Map<String, int>.from(
          _jobSeekerProfile.flightHours,
        ),
        applicantFlightHoursTypes: List<String>.from(
          _jobSeekerProfile.flightHoursTypes,
        ),
        applicantSpecialtyFlightHours: List<String>.from(
          _jobSeekerProfile.specialtyFlightHours,
        ),
        applicantSpecialtyFlightHoursMap: Map<String, int>.from(
          _jobSeekerProfile.specialtyFlightHoursMap,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error applying: $e')));
    }
  }

  void _handleApplyTap(JobListing job) {
    if (job.isExternal) {
      _contactExternalEmployer(job);
      return;
    }

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

  String _normalizeRequirementToken(String value) {
    return value.trim().toLowerCase();
  }

  List<String> _metRequirementsForApplicant(Application app, JobListing job) {
    final met = <String>[];

    final applicantCertificates = <String>{
      for (final cert in app.applicantFaaCertificates)
        ...expandedCertificateQualifications(cert),
    };
    for (final cert in job.faaCertificates) {
      final normalized = normalizeCertificateName(cert);
      if (applicantCertificates.contains(normalized)) {
        met.add('Cert: ${canonicalCertificateLabel(cert)}');
      }
    }

    for (final rating in job.requiredRatings) {
      final normalized = normalizeCertificateName(rating);
      if (applicantCertificates.contains(normalized)) {
        met.add('Rating: ${rating.trim()}');
      }
    }

    final applicantTypeRatings = {
      for (final rating in app.applicantTypeRatings)
        _normalizeRequirementToken(rating),
    };
    for (final rating in job.typeRatingsRequired) {
      if (applicantTypeRatings.contains(_normalizeRequirementToken(rating))) {
        met.add('Type Rating: ${rating.trim()}');
      }
    }

    final applicantAircraft = {
      for (final aircraft in app.applicantAircraftFlown)
        _normalizeRequirementToken(aircraft),
    };
    for (final aircraft in job.aircraftFlown) {
      if (applicantAircraft.contains(_normalizeRequirementToken(aircraft))) {
        met.add('Aircraft: ${aircraft.trim()}');
      }
    }

    final minimumHours = job.minimumHours;
    if (minimumHours != null && minimumHours > 0) {
      if (app.applicantTotalFlightHours >= minimumHours) {
        met.add(
          'Total Hours: ${app.applicantTotalFlightHours} / $minimumHours',
        );
      }
    }

    for (final requirement in job.flightHoursByType.entries) {
      final isPreferred = job.preferredFlightHours.contains(requirement.key);
      if (isPreferred) {
        continue;
      }

      final profileHours = app.applicantFlightHours[requirement.key] ?? 0;
      final hasRequirement =
          app.applicantFlightHoursTypes.contains(requirement.key) &&
          profileHours >= requirement.value;

      if (hasRequirement) {
        met.add(
          _formatHoursRequirementLabel(
            requirement.key,
            requirement.value,
            false,
          ),
        );
      }
    }

    for (final requirement in job.instructorHoursByType.entries) {
      final isPreferred = _containsInstructorHourLabel(
        job.preferredInstructorHours,
        requirement.key,
      );
      if (isPreferred) {
        continue;
      }

      final profileHours = _instructorHoursForLabel(
        app.applicantFlightHours,
        requirement.key,
      );
      final hasRequirement =
          _containsInstructorHourLabel(
            app.applicantFlightHoursTypes,
            requirement.key,
          ) &&
          profileHours >= requirement.value;

      if (hasRequirement) {
        met.add(
          _formatHoursRequirementLabel(
            requirement.key,
            requirement.value,
            false,
          ),
        );
      }
    }

    for (final requirement in job.specialtyHoursByType.entries) {
      final isPreferred = job.preferredSpecialtyHours.contains(requirement.key);
      if (isPreferred) {
        continue;
      }

      final profileHours =
          app.applicantSpecialtyFlightHoursMap[requirement.key] ?? 0;
      final hasRequirement =
          app.applicantSpecialtyFlightHours.contains(requirement.key) &&
          profileHours >= requirement.value;

      if (hasRequirement) {
        met.add(
          _formatHoursRequirementLabel(
            requirement.key,
            requirement.value,
            false,
          ),
        );
      }
    }

    return met;
  }

  List<String> _lackingRequirementsForApplicant(
    Application app,
    JobListing job,
  ) {
    final lacking = <String>[];

    final applicantCertificates = <String>{
      for (final cert in app.applicantFaaCertificates)
        ...expandedCertificateQualifications(cert),
    };
    for (final cert in job.faaCertificates) {
      final normalized = normalizeCertificateName(cert);
      if (!applicantCertificates.contains(normalized)) {
        lacking.add('Cert: ${canonicalCertificateLabel(cert)}');
      }
    }

    for (final rating in job.requiredRatings) {
      final normalized = normalizeCertificateName(rating);
      if (!applicantCertificates.contains(normalized)) {
        lacking.add('Rating: ${rating.trim()}');
      }
    }

    final applicantTypeRatings = {
      for (final rating in app.applicantTypeRatings)
        _normalizeRequirementToken(rating),
    };
    for (final rating in job.typeRatingsRequired) {
      if (!applicantTypeRatings.contains(_normalizeRequirementToken(rating))) {
        lacking.add('Type Rating: ${rating.trim()}');
      }
    }

    final applicantAircraft = {
      for (final aircraft in app.applicantAircraftFlown)
        _normalizeRequirementToken(aircraft),
    };
    for (final aircraft in job.aircraftFlown) {
      if (!applicantAircraft.contains(_normalizeRequirementToken(aircraft))) {
        lacking.add('Aircraft: ${aircraft.trim()}');
      }
    }

    final minimumHours = job.minimumHours;
    if (minimumHours != null && minimumHours > 0) {
      if (app.applicantTotalFlightHours < minimumHours) {
        lacking.add(
          'Total Hours: ${app.applicantTotalFlightHours} / $minimumHours',
        );
      }
    }

    for (final requirement in job.flightHoursByType.entries) {
      final isPreferred = job.preferredFlightHours.contains(requirement.key);
      if (isPreferred) {
        continue;
      }

      final profileHours = app.applicantFlightHours[requirement.key] ?? 0;
      final hasRequirement =
          app.applicantFlightHoursTypes.contains(requirement.key) &&
          profileHours >= requirement.value;

      if (!hasRequirement) {
        lacking.add(
          _formatHoursRequirementMissing(
            'Flight Hours',
            requirement.key,
            requirement.value,
          ),
        );
      }
    }

    for (final requirement in job.instructorHoursByType.entries) {
      final isPreferred = _containsInstructorHourLabel(
        job.preferredInstructorHours,
        requirement.key,
      );
      if (isPreferred) {
        continue;
      }

      final profileHours = _instructorHoursForLabel(
        app.applicantFlightHours,
        requirement.key,
      );
      final hasRequirement =
          _containsInstructorHourLabel(
            app.applicantFlightHoursTypes,
            requirement.key,
          ) &&
          profileHours >= requirement.value;

      if (!hasRequirement) {
        lacking.add(
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

      final profileHours =
          app.applicantSpecialtyFlightHoursMap[requirement.key] ?? 0;
      final hasRequirement =
          app.applicantSpecialtyFlightHours.contains(requirement.key) &&
          profileHours >= requirement.value;

      if (!hasRequirement) {
        lacking.add(
          _formatHoursRequirementMissing(
            'Specialty Hours',
            requirement.key,
            requirement.value,
          ),
        );
      }
    }

    return lacking;
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
      final nextStatus =
          feedbackType == ApplicationFeedback.feedbackTypeInterested
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error sending feedback: $e')));
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
                  Text('Total Flight Hours: ${app.applicantTotalFlightHours}'),
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
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Interested'),
                        selected:
                            selectedFeedbackType ==
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
                        selected:
                            selectedFeedbackType ==
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
                        selected:
                            selectedFeedbackType ==
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
                  final message =
                      type == ApplicationFeedback.feedbackTypeInterested
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

  Future<void> _showQuickApplyDialog(JobListing job, _MatchResult match) async {
    final coverLetterController = TextEditingController();
    final matchLabel = match.matchPercentage >= 70
        ? '${match.matchPercentage}% Good Match'
        : '${match.matchPercentage}% Growth Opportunity';
    final bodyText = match.missingRequirements.isEmpty
        ? 'Add an optional cover letter.'
        : 'Build your profile: ${match.missingRequirements.take(3).join(', ')}'
              '${match.missingRequirements.length > 3 ? ' (and more)' : ''}.';
    final dialogTitle = match.matchPercentage >= 70 ? 'Quick Apply' : 'Express Interest';
    final submitted = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              matchLabel,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
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

  Future<void> _reportJobListing(JobListing job) async {
    final reasonController = TextEditingController();
    final detailsController = TextEditingController();
    String selectedReason = 'Fraud / Scam';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report Listing'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedReason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: const [
                    DropdownMenuItem(
                      value: 'Fraud / Scam',
                      child: Text('Fraud / Scam'),
                    ),
                    DropdownMenuItem(
                      value: 'Misleading Information',
                      child: Text('Misleading Information'),
                    ),
                    DropdownMenuItem(
                      value: 'Inappropriate Content',
                      child: Text('Inappropriate Content'),
                    ),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setDialogState(() {
                      selectedReason = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: detailsController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Additional Details (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                reasonController.text = selectedReason;
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Submit Report'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) {
      reasonController.dispose();
      detailsController.dispose();
      return;
    }

    final supabaseUserId =
        Supabase.instance.client.auth.currentUser?.id.trim() ?? '';
    final reporterUserId = supabaseUserId.isNotEmpty
        ? supabaseUserId
        : _currentJobSeekerId();

    final report = JobListingReport(
      id: 'report_${DateTime.now().millisecondsSinceEpoch}',
      jobListingId: job.id,
      reporterUserId: reporterUserId,
      employerId: job.employerId,
      reason: reasonController.text.trim().isEmpty
          ? 'Other'
          : reasonController.text.trim(),
      details: detailsController.text.trim(),
      jobTitle: job.title,
      company: job.company,
      location: job.location,
      createdAt: DateTime.now(),
    );

    reasonController.dispose();
    detailsController.dispose();

    try {
      await _appRepository.reportJobListing(report);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing report submitted. Thank you.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not submit report: $e')));
    }
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
    final selectedRequiredRatings = <String>{...job.requiredRatings};
    String? selectedFaaRule = job.faaRules.isNotEmpty
        ? job.faaRules.first
        : null;
    String? editPart135SubType;
    String selectedCrewRole = job.crewRole.toLowerCase() == 'crew'
        ? 'Crew'
        : 'Single Pilot';
    String selectedCrewPosition = job.crewPosition == 'Co-Pilot'
        ? 'Co-Pilot'
        : 'Captain';
    String selectedAirframeScope = job.airframeScope;
    bool isOpenListing = job.deadlineDate == null;
    DateTime? selectedDeadlineDate = job.deadlineDate;
    bool editHoursPicSicExpanded = false;
    bool editHoursOtherExpanded = false;
    bool editHoursHelicopterExpanded = false;
    bool editHoursSpecialtyExpanded = false;
    String editHoursGroupFilter = 'all';

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

    bool editOperationalScopeSatisfied() {
      return selectedFaaRule != null &&
          selectedFaaRule!.isNotEmpty &&
          (selectedFaaRule != 'Part 135' || editPart135SubType != null);
    }

    bool editAirframeScopeSatisfied() {
      return _availableAirframeScopes.contains(selectedAirframeScope);
    }

    bool editCertificatesSatisfied() {
      return selectedFaaCertificates.any(_availableFaaCertificates.contains);
    }

    List<String> editMissingImpliedRatings() {
      return _missingImpliedRatings(
        selectedRatings: selectedRequiredRatings,
        requiredFlightHourLabels: selectedFlightHours.where(
          (name) => !preferredFlightHours.contains(name),
        ),
        requiredSpecialtyHourLabels: selectedSpecialtyHours.where(
          (name) => !preferredSpecialtyHours.contains(name),
        ),
      );
    }

    bool editRatingsSatisfied() {
      return selectedRequiredRatings.any(_availableRatingSelections.contains) &&
          editMissingImpliedRatings().isEmpty;
    }

    List<String> editRequiredInstructorCerts() {
      return _requiredInstructorCertificatesForHours(
        selectedInstructorHours.where(
          (name) => !preferredInstructorHours.contains(name),
        ),
      );
    }

    bool editInstructorCertsSatisfied() {
      final requiredCerts = editRequiredInstructorCerts();
      if (requiredCerts.isEmpty) {
        return selectedFaaCertificates.any(
          _availableInstructorCertificates.contains,
        );
      }
      return requiredCerts.every(selectedFaaCertificates.contains);
    }

    bool editHoursSatisfied() {
      final hasAnyHoursSelection =
          selectedFlightHours.isNotEmpty ||
          selectedInstructorHours.isNotEmpty ||
          selectedSpecialtyHours.isNotEmpty;
      if (!hasAnyHoursSelection) {
        return false;
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
      if (missingHoursValue) {
        return false;
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

      return hasRequiredFlightHour ||
          hasRequiredInstructorHour ||
          hasRequiredSpecialtyHour;
    }

    void setEditHourValue({
      required String label,
      required int value,
      required Set<String> selectedSet,
      required Set<String> preferredSet,
      required Map<String, TextEditingController> controllers,
      required void Function(VoidCallback fn) setModalState,
    }) {
      setModalState(() {
        if (value <= 0) {
          selectedSet.remove(label);
          preferredSet.remove(label);
          controllers[label]?.text = '';
        } else {
          selectedSet.add(label);
          controllers[label]?.text = value.toString();
        }
      });
    }

    Widget editHourRow({
      required String label,
      required Set<String> selectedSet,
      required Set<String> preferredSet,
      required Map<String, TextEditingController> controllers,
      required void Function(VoidCallback fn) setModalState,
    }) {
      final current = int.tryParse(controllers[label]?.text.trim() ?? '0') ?? 0;
      final isSelected = selectedSet.contains(label) && current > 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SearchHourSliderRow(
            label: label,
            sliderMax: _hourSliderMax(label),
            value: current.clamp(0, _hourSliderMax(label).toInt()),
            onChanged: (value) {
              setEditHourValue(
                label: label,
                value: value,
                selectedSet: selectedSet,
                preferredSet: preferredSet,
                controllers: controllers,
                setModalState: setModalState,
              );
            },
          ),
          if (isSelected)
            Padding(
              padding: const EdgeInsets.only(left: 116, right: 4, bottom: 8),
              child: DropdownButtonFormField<String>(
                initialValue: preferredSet.contains(label)
                    ? 'Preferred'
                    : 'Required',
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Requirement',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Required', child: Text('Required')),
                  DropdownMenuItem(
                    value: 'Preferred',
                    child: Text('Preferred'),
                  ),
                ],
                onChanged: (value) {
                  setModalState(() {
                    if (value == 'Preferred') {
                      preferredSet.add(label);
                    } else {
                      preferredSet.remove(label);
                    }
                  });
                },
              ),
            ),
        ],
      );
    }

    Widget buildEditCategorizedHoursSection(
      void Function(VoidCallback fn) setModalState,
    ) {
      final extraFlight = flightOptions
          .where(
            (item) => !const [
              'Total Time',
              'Total PIC Time',
              'Total SIC Time',
              'PIC Turbine',
              'SIC Turbine',
              'PIC Jet',
              'SIC Jet',
              'Multi-engine',
              'Total Turbine Time',
              'Instrument',
              'Cross-Country',
              'Night',
            ].contains(item),
          )
          .toList();
      final extraOtherFlight = extraFlight
          .where((item) => !_availableHelicopterHours.contains(item))
          .toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MINIMUM EXPERIENCE (HOURS)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.9),
          ),
          const SizedBox(height: 6),
          editHourRow(
            label: 'Total Time',
            selectedSet: selectedFlightHours,
            preferredSet: preferredFlightHours,
            controllers: flightHourControllers,
            setModalState: setModalState,
          ),
          ExpansionTile(
            key: ValueKey('edit-hours-picsic-${editHoursPicSicExpanded ? 'open' : 'closed'}'),
            initiallyExpanded: editHoursPicSicExpanded,
            onExpansionChanged: (expanded) {
              setModalState(() => editHoursPicSicExpanded = expanded);
            },
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'PIC / SIC TIME',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Text('Show:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(width: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('ALL'),
                          selected: editHoursGroupFilter == 'all',
                          onSelected: (_) =>
                              setModalState(() => editHoursGroupFilter = 'all'),
                        ),
                        ChoiceChip(
                          label: const Text('PIC'),
                          selected: editHoursGroupFilter == 'pic',
                          onSelected: (_) =>
                              setModalState(() => editHoursGroupFilter = 'pic'),
                        ),
                        ChoiceChip(
                          label: const Text('SIC'),
                          selected: editHoursGroupFilter == 'sic',
                          onSelected: (_) =>
                              setModalState(() => editHoursGroupFilter = 'sic'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (editHoursGroupFilter != 'sic')
                editHourRow(
                  label: 'Total PIC Time',
                  selectedSet: selectedFlightHours,
                  preferredSet: preferredFlightHours,
                  controllers: flightHourControllers,
                  setModalState: setModalState,
                ),
              if (editHoursGroupFilter != 'pic')
                editHourRow(
                  label: 'Total SIC Time',
                  selectedSet: selectedFlightHours,
                  preferredSet: preferredFlightHours,
                  controllers: flightHourControllers,
                  setModalState: setModalState,
                ),
              if (editHoursGroupFilter != 'sic')
                editHourRow(
                  label: 'PIC Turbine',
                  selectedSet: selectedFlightHours,
                  preferredSet: preferredFlightHours,
                  controllers: flightHourControllers,
                  setModalState: setModalState,
                ),
              if (editHoursGroupFilter != 'pic')
                editHourRow(
                  label: 'SIC Turbine',
                  selectedSet: selectedFlightHours,
                  preferredSet: preferredFlightHours,
                  controllers: flightHourControllers,
                  setModalState: setModalState,
                ),
              if (editHoursGroupFilter != 'sic')
                editHourRow(
                  label: 'PIC Jet',
                  selectedSet: selectedFlightHours,
                  preferredSet: preferredFlightHours,
                  controllers: flightHourControllers,
                  setModalState: setModalState,
                ),
              if (editHoursGroupFilter != 'pic')
                editHourRow(
                  label: 'SIC Jet',
                  selectedSet: selectedFlightHours,
                  preferredSet: preferredFlightHours,
                  controllers: flightHourControllers,
                  setModalState: setModalState,
                ),
            ],
          ),
          ExpansionTile(
            key: ValueKey('edit-hours-other-${editHoursOtherExpanded ? 'open' : 'closed'}'),
            initiallyExpanded: editHoursOtherExpanded,
            onExpansionChanged: (expanded) {
              setModalState(() => editHoursOtherExpanded = expanded);
            },
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'OTHER CATEGORIES',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8),
            ),
            children: [
              for (final label in _availableOtherFlightHours)
                editHourRow(
                  label: label,
                  selectedSet: selectedFlightHours,
                  preferredSet: preferredFlightHours,
                  controllers: flightHourControllers,
                  setModalState: setModalState,
                ),
              for (final label in extraOtherFlight)
                editHourRow(
                  label: label,
                  selectedSet: selectedFlightHours,
                  preferredSet: preferredFlightHours,
                  controllers: flightHourControllers,
                  setModalState: setModalState,
                ),
            ],
          ),
          ExpansionTile(
            key: ValueKey('edit-hours-specialty-${editHoursSpecialtyExpanded ? 'open' : 'closed'}'),
            initiallyExpanded: editHoursSpecialtyExpanded,
            onExpansionChanged: (expanded) {
              setModalState(() => editHoursSpecialtyExpanded = expanded);
            },
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'SPECIALTY HOURS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8),
            ),
            children: specialtyOptions
                .map(
                  (label) => editHourRow(
                    label: label,
                    selectedSet: selectedSpecialtyHours,
                    preferredSet: preferredSpecialtyHours,
                    controllers: specialtyHourControllers,
                    setModalState: setModalState,
                  ),
                )
                .toList(),
          ),
          ExpansionTile(
            key: ValueKey('edit-hours-helicopter-${editHoursHelicopterExpanded ? 'open' : 'closed'}'),
            initiallyExpanded: editHoursHelicopterExpanded,
            onExpansionChanged: (expanded) {
              setModalState(() => editHoursHelicopterExpanded = expanded);
            },
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'HELICOPTER HOURS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8),
            ),
            children: _availableHelicopterHours
                .map(
                  (label) => editHourRow(
                    label: label,
                    selectedSet: selectedFlightHours,
                    preferredSet: preferredFlightHours,
                    controllers: flightHourControllers,
                    setModalState: setModalState,
                  ),
                )
                .toList(),
          ),
        ],
      );
    }

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
            draft.requiredRatings,
            job.requiredRatings,
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
      final hasRatingSelection = selectedRequiredRatings.any(
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
      final missingImpliedRatings = _missingImpliedRatings(
        selectedRatings: selectedRequiredRatings,
        requiredFlightHourLabels: selectedFlightHours.where(
          (name) => !preferredFlightHours.contains(name),
        ),
        requiredSpecialtyHourLabels: selectedSpecialtyHours.where(
          (name) => !preferredSpecialtyHours.contains(name),
        ),
      );
      final missingImpliedRatingRules = _missingImpliedRatingRuleMessages(
        selectedRatings: selectedRequiredRatings,
        requiredFlightHourLabels: selectedFlightHours.where(
          (name) => !preferredFlightHours.contains(name),
        ),
        requiredSpecialtyHourLabels: selectedSpecialtyHours.where(
          (name) => !preferredSpecialtyHours.contains(name),
        ),
      );
      final requiredInstructorCertificates =
          _requiredInstructorCertificatesForHours(
            selectedInstructorHours.where(
              (name) => !preferredInstructorHours.contains(name),
            ),
          );
      final missingRequiredInstructorCertificates =
          requiredInstructorCertificates
              .where((cert) => !selectedFaaCertificates.contains(cert))
              .toList();

      if (missingImpliedRatings.isNotEmpty) {
        missingRequirements.addAll(missingImpliedRatingRules);
      }

      if (missingRequiredInstructorCertificates.isNotEmpty) {
        missingRequirements.add(
          'Instructor Certificate(s) required by selected instructor hours: '
          '${missingRequiredInstructorCertificates.join(', ')}',
        );
      }

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
        airframeScope: selectedAirframeScope,
        faaRules: selectedFaaRule == null ? [] : [selectedFaaRule!],
        part135SubType: editPart135SubType,
        description: descriptionController.text.trim(),
        faaCertificates: selectedFaaCertificates.toList(),
        requiredRatings: selectedRequiredRatings.toList(),
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
        isExternal: job.isExternal,
        externalApplyUrl: job.externalApplyUrl,
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
            initiallyExpanded: false,
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
            title: editOperationalScopeSatisfied()
                ? 'FAA Operational Scope'
                : 'FAA Operational Scope *',
            isSatisfied: editOperationalScopeSatisfied(),
            initiallyExpanded: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
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
                    setModalState(() {
                      selectedFaaRule = value;
                      if (value != 'Part 135') {
                        editPart135SubType = null;
                        selectedFaaCertificates.remove(
                          'Commercial Pilot (CPL)',
                        );
                        selectedFaaCertificates.remove(
                          'Instrument Rating (IFR)',
                        );
                      }
                    });
                  },
                ),
                if (selectedFaaRule == 'Part 135') ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Part 135 Operating Type',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  RadioGroup<String>(
                    groupValue: editPart135SubType,
                    onChanged: (value) {
                      setModalState(() {
                        editPart135SubType = value;
                        selectedFaaCertificates.removeWhere(
                          (c) =>
                              c == 'Airline Transport Pilot (ATP)' ||
                              c == 'Private Pilot (PPL)',
                        );
                        selectedFaaCertificates.add('Commercial Pilot (CPL)');

                        if (value == 'ifr') {
                          selectedFaaCertificates.add(
                            'Instrument Rating (IFR)',
                          );
                          selectedFlightHours
                            ..add('Total Time')
                            ..add('Cross-Country')
                            ..add('Night')
                            ..add('Instrument');
                          flightHourControllers['Total Time']?.text = '1200';
                          flightHourControllers['Cross-Country']?.text = '500';
                          flightHourControllers['Night']?.text = '100';
                          flightHourControllers['Instrument']?.text = '75';
                        } else {
                          selectedFaaCertificates.remove(
                            'Instrument Rating (IFR)',
                          );
                          selectedFlightHours
                            ..add('Total Time')
                            ..add('Cross-Country')
                            ..add('Night');
                          selectedFlightHours.remove('Instrument');
                          flightHourControllers['Total Time']?.text = '500';
                          flightHourControllers['Cross-Country']?.text = '100';
                          flightHourControllers['Night']?.text = '25';
                        }
                      });
                    },
                    child: Column(
                      children: const [
                        RadioListTile<String>(
                          title: Text('IFR / Commuter'),
                          subtitle: Text(
                            '1,200 TT · 500 XC · 100 Night · 75 Instrument',
                          ),
                          value: 'ifr',
                        ),
                        RadioListTile<String>(
                          title: Text('VFR Only'),
                          subtitle: Text('500 TT · 100 XC · 25 Night'),
                          value: 'vfr',
                        ),
                      ],
                    ),
                  ),
                  if (editPart135SubType != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Minimums auto-applied to flight hours below. Adjust as needed.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildEditAccordionSection(
            title: editAirframeScopeSatisfied()
                ? 'Airframe Scope'
                : 'Airframe Scope *',
            isSatisfied: editAirframeScopeSatisfied(),
            initiallyExpanded: false,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableAirframeScopes
                  .map(
                    (scope) => ChoiceChip(
                      label: Text(scope),
                      selected: selectedAirframeScope == scope,
                      onSelected: (_) {
                        setModalState(() {
                          selectedAirframeScope = scope;
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
          _buildEditAccordionSection(
            title: editCertificatesSatisfied()
                ? 'Required FAA Certificates'
                : 'Required FAA Certificates *',
            isSatisfied: editCertificatesSatisfied(),
            initiallyExpanded: false,
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
            title: editRatingsSatisfied()
                ? 'Required Ratings'
                : editMissingImpliedRatings().isNotEmpty
                ? 'Required Ratings * (Review implied ratings)'
                : 'Required Ratings *',
            isSatisfied: editRatingsSatisfied(),
            initiallyExpanded: false,
            child: Column(
              children: _availableRatingSelections.map((rating) {
                final isMissingImpliedRating =
                    editMissingImpliedRatings().contains(rating) &&
                    !selectedRequiredRatings.contains(rating);
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: isMissingImpliedRating
                      ? Row(
                          children: [
                            Expanded(
                              child: Text(
                                rating,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.orange.shade300,
                                ),
                              ),
                              child: Text(
                                'Required by hours',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Text(rating),
                  value: selectedRequiredRatings.contains(rating),
                  onChanged: (selected) {
                    setModalState(() {
                      if (selected == true) {
                        selectedRequiredRatings.add(rating);
                      } else {
                        selectedRequiredRatings.remove(rating);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          _buildEditAccordionSection(
            title: editHoursSatisfied()
                ? 'Hours Requirements'
                : 'Hours Requirements *',
            isSatisfied: editHoursSatisfied(),
            initiallyExpanded: false,
            child: buildEditCategorizedHoursSection(setModalState),
          ),
          const SizedBox(height: 14),
          _buildEditAccordionSection(
            title: () {
              final hasCerts = selectedFaaCertificates
                  .any(_availableInstructorCertificates.contains);
              final hasHours = selectedInstructorHours.isNotEmpty;
              if (!hasCerts && !hasHours) {
                return 'Instructor Certificates and Hours (Optional)';
              }
              if (editRequiredInstructorCerts().isNotEmpty &&
                  !editInstructorCertsSatisfied()) {
                return 'Instructor Certificates and Hours *';
              }
              return 'Instructor Certificates and Hours';
            }(),
            isSatisfied: editInstructorCertsSatisfied(),
            initiallyExpanded: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._availableInstructorCertificates.map((cert) {
                  final requiredHourLabel =
                      _requiredInstructorHourLabelForCertificate(cert);
                  final showRequiredByHoursChip =
                      requiredHourLabel != null &&
                      _isRequiredInstructorHourSelected(
                        hourLabel: requiredHourLabel,
                        selectedInstructorHours: selectedInstructorHours,
                        preferredInstructorHours: preferredInstructorHours,
                      ) &&
                      !selectedFaaCertificates.contains(cert);
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: showRequiredByHoursChip
                        ? Row(
                            children: [
                              Expanded(
                                child: Text(
                                  cert,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildRequiredByHoursChip(),
                            ],
                          )
                        : Text(cert),
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
                }),
                const SizedBox(height: 12),
                const Text(
                  'INSTRUCTION HOURS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                ...instructorOptions.map(
                  (label) => editHourRow(
                    label: label,
                    selectedSet: selectedInstructorHours,
                    preferredSet: preferredInstructorHours,
                    controllers: instructorHourControllers,
                    setModalState: setModalState,
                  ),
                ),
              ],
            ),
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
    bool? isSatisfied,
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
              if (isSatisfied == true)
                const Tooltip(
                  message: 'Minimum requirement met',
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 20,
                  ),
                ),
            ],
          ),
          children: [child],
        ),
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
    _selectedAirframeScope = 'Fixed Wing';
    _createDescriptionController.clear();
    _createTypeRatingsController.clear();
    _selectedFaaCertificates.clear();
    _selectedRequiredRatings.clear();
    _selectedFaaRules.clear();
    _part135SubType = null;
    _selectedFlightHours.clear();
    for (final c in _createFlightHourControllers.values) {
      c.dispose();
    }
    _createFlightHourControllers.clear();
    _preferredFlightHours.clear();
    _selectedInstructorHours.clear();
    _preferredInstructorHours.clear();
    _selectedSpecialtyHours.clear();
    _preferredSpecialtyHours.clear();
    _createHoursPicSicExpanded = false;
    _createHoursOtherExpanded = false;
    _createHoursHelicopterExpanded = false;
    _createHoursSpecialtyExpanded = false;
    _createHoursGroupFilter = 'all';
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
    final hasRatingSelection = _selectedRequiredRatings.any(
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
    final missingImpliedRatings = _missingImpliedRatings(
      selectedRatings: _selectedRequiredRatings,
      requiredFlightHourLabels: _selectedFlightHours.keys.where(
        (name) => !_preferredFlightHours.contains(name),
      ),
      requiredSpecialtyHourLabels: _selectedSpecialtyHours.keys.where(
        (name) => !_preferredSpecialtyHours.contains(name),
      ),
    );
    final missingImpliedRatingRules = _missingImpliedRatingRuleMessages(
      selectedRatings: _selectedRequiredRatings,
      requiredFlightHourLabels: _selectedFlightHours.keys.where(
        (name) => !_preferredFlightHours.contains(name),
      ),
      requiredSpecialtyHourLabels: _selectedSpecialtyHours.keys.where(
        (name) => !_preferredSpecialtyHours.contains(name),
      ),
    );
    final requiredInstructorCertificates =
        _requiredInstructorCertificatesForHours(
          _selectedInstructorHours.keys.where(
            (name) => !_preferredInstructorHours.contains(name),
          ),
        );
    final missingRequiredInstructorCertificates = requiredInstructorCertificates
        .where((cert) => !_selectedFaaCertificates.contains(cert))
        .toList();

    final missing = <String>[];
    if (!hasOperationalScope) {
      missing.add('FAA Operational Scope');
    }
    if (_selectedFaaRules.contains('Part 135') && _part135SubType == null) {
      missing.add('Part 135 Operating Type (IFR/Commuter or VFR Only)');
    }
    if (!hasCertificateSelection) {
      missing.add('At Least One Certificate Selection Required');
    }
    if (!hasRatingSelection) {
      missing.add('At Least One Rating Selection Required');
    }
    if (missingImpliedRatings.isNotEmpty) {
      missing.addAll(missingImpliedRatingRules);
    }
    if (missingRequiredInstructorCertificates.isNotEmpty) {
      missing.add(
        'Instructor Certificate(s) required by selected instructor hours: '
        '${missingRequiredInstructorCertificates.join(', ')}',
      );
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
        job.requiredRatings.length +
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
                          final isPhoneActionLayout =
                              MediaQuery.sizeOf(context).width <
                              kPhoneBreakpoint;

                          Widget cardActionButton({
                            required VoidCallback? onPressed,
                            required IconData icon,
                            required String label,
                            Color? iconColor,
                          }) {
                            if (isPhoneActionLayout) {
                              return Tooltip(
                                message: label,
                                child: OutlinedButton(
                                  onPressed: onPressed,
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(40, 40),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                  ),
                                  child: Icon(
                                    icon,
                                    size: 18,
                                    color: iconColor,
                                  ),
                                ),
                              );
                            }

                            return OutlinedButton.icon(
                              onPressed: onPressed,
                              icon: Icon(icon, color: iconColor),
                              label: Text(label),
                            );
                          }

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
                                                ? 'Strong match. Your profile exceeds requirements.'
                                                : 'Growth opportunity. Your profile is developing: $missingText',
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
                                                      Wrap(
                                                        crossAxisAlignment:
                                                            WrapCrossAlignment
                                                                .center,
                                                        spacing: 8,
                                                        runSpacing: 4,
                                                        children: [
                                                          Text(
                                                            job.title,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 16,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                          ),
                                                          if (job.isExternal)
                                                            const Text(
                                                              'EXTERNAL JOB',
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                color:
                                                                    Colors.teal,
                                                                letterSpacing:
                                                                    0.5,
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        '${job.company} • ${job.location}',
                                                      ),
                                                      if (job.isExternal)
                                                        _buildExternalListingPhoneCta(
                                                          job,
                                                        ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '${job.crewRole}${job.crewPosition != null && job.crewPosition!.isNotEmpty ? ' - ${job.crewPosition}' : ''} • ${job.type}',
                                                      ),
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
                                    _LinkifiedText(
                                      text: job.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.grey.shade800,
                                      ),
                                      onTapUrl: (url) {
                                        _openDetectedLink(url);
                                      },
                                      onTapPhone: (phone) {
                                        _openPhoneCall(phone);
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Wrap(
                                        spacing: 8,
                                        children: [
                                          if (_profileType ==
                                              ProfileType.jobSeeker)
                                            cardActionButton(
                                              onPressed: () =>
                                                  _toggleFavorite(job),
                                              icon: isFav
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              iconColor: isFav
                                                  ? Colors.amber
                                                  : null,
                                              label: isFav
                                                  ? 'Favorited'
                                                  : 'Favorite',
                                            ),
                                          if (_profileType ==
                                              ProfileType.jobSeeker)
                                            cardActionButton(
                                              onPressed:
                                                  (job.isExternal ||
                                                      !_hasApplied(job.id))
                                                  ? () => _handleApplyTap(job)
                                                  : null,
                                              icon: job.isExternal
                                                  ? Icons.open_in_new
                                                  : _hasApplied(job.id)
                                                  ? Icons.check_circle
                                                  : Icons.send,
                                              iconColor:
                                                  !job.isExternal &&
                                                      _hasApplied(job.id)
                                                  ? Colors.green
                                                  : null,
                                              label: job.isExternal
                                                  ? 'Contact Employer'
                                                  : _hasApplied(job.id)
                                                  ? 'Applied'
                                                  : 'Apply',
                                            ),
                                          if (_profileType ==
                                              ProfileType.jobSeeker)
                                            cardActionButton(
                                              onPressed: () =>
                                                  _shareJobListing(job),
                                              icon: Icons.share_outlined,
                                              label: 'Share',
                                            ),
                                          if (_profileType ==
                                              ProfileType.jobSeeker)
                                            cardActionButton(
                                              onPressed: () =>
                                                  _reportJobListing(job),
                                              icon: Icons.flag_outlined,
                                              label: 'Report',
                                            ),
                                          if (_canEditJob(job))
                                            cardActionButton(
                                              onPressed: () => _editJob(job),
                                              icon: Icons.edit,
                                              label: 'Edit',
                                            ),
                                          if (_canDeleteJob(job))
                                            cardActionButton(
                                              onPressed: () => _removeJob(job),
                                              icon: Icons.delete_outline,
                                              label: 'Delete',
                                            ),
                                          if (_profileType ==
                                              ProfileType.employer)
                                            cardActionButton(
                                              onPressed: () =>
                                                  _saveJobAsTemplate(job),
                                              icon: Icons.bookmark_add_outlined,
                                              label: 'Save as Template',
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
          matchLabel = '🔴 ${app.matchPercentage}% Growth Opportunity';
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
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
      'rejected': allApplications
          .where((app) => app.status == 'rejected')
          .length,
    };
    final perfectCount = allApplications
        .where((app) => app.isPerfectMatch)
        .length;
    final goodCount = allApplications.where((app) => app.isGoodMatch).length;
    final stretchCount = allApplications
        .where((app) => app.isStretchMatch)
        .length;

    // Apply status filter
    final statusFiltered = _selectedEmployerApplicationFilter == 'all'
        ? allApplications
        : allApplications
              .where((app) => app.status == _selectedEmployerApplicationFilter)
              .toList();

    // Apply match % filter
    final filteredApplications = switch (_selectedMatchFilter) {
      'perfect' => statusFiltered.where((app) => app.isPerfectMatch).toList(),
      'good' => statusFiltered.where((app) => app.isGoodMatch).toList(),
      'stretch' => statusFiltered.where((app) => app.isStretchMatch).toList(),
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

          final statusCompare = statusRank(
            a.status,
          ).compareTo(statusRank(b.status));
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
        final metRequirements = _metRequirementsForApplicant(app, job);
        final lackingRequirements = _lackingRequirementsForApplicant(app, job);

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
                      const SizedBox(height: 8),
                      Text(
                        'Requirements Met',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.green.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (metRequirements.isEmpty)
                        Text(
                          'No required items currently marked as met.',
                          style: TextStyle(
                            color: Colors.green.shade900,
                            fontSize: 12,
                          ),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: metRequirements
                              .take(8)
                              .map(
                                (item) => Chip(
                                  label: Text(item),
                                  backgroundColor: Colors.green.shade50,
                                  side: BorderSide(
                                    color: Colors.green.shade200,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Requirements Lacking',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (lackingRequirements.isEmpty)
                        Text(
                          'No required gaps detected in the snapshot.',
                          style: TextStyle(
                            color: Colors.green.shade900,
                            fontSize: 12,
                          ),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: lackingRequirements
                              .take(8)
                              .map(
                                (item) => Chip(
                                  label: Text(item),
                                  backgroundColor: Colors.red.shade50,
                                  side: BorderSide(color: Colors.red.shade200),
                                ),
                              )
                              .toList(),
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

  // ---------------------------------------------------------------------------
  // Search-tab filter helpers — extracted from build method for clarity.
  // ---------------------------------------------------------------------------

  /// Scrolls [scrollController] so [targetOffset] is visible, animating
  /// smoothly. Skips if already within 1 logical pixel.
  void _animateScrollController(
    ScrollController scrollController,
    double targetOffset,
  ) {
    if (!scrollController.hasClients) {
      return;
    }
    final position = scrollController.position;
    final clamped = targetOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    ).toDouble();
    if ((position.pixels - clamped).abs() < 1) {
      return;
    }
    position.animateTo(
      clamped,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// After the next frame, scrolls the outer Search list so the Filters card
  /// top sits just below the app tabs bar.
  void _pinFiltersCardBelowTabs() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_searchTabPrimaryFiltersDrawerOpen) {
        return;
      }
      final filtersCardContext =
          _searchTabPrimaryFiltersCardKey.currentContext;
      final tabsContext = _topTabsBarKey.currentContext;
      if (filtersCardContext == null || tabsContext == null) {
        return;
      }
      final filtersRO = filtersCardContext.findRenderObject();
      final tabsRO = tabsContext.findRenderObject();
      if (filtersRO is! RenderBox || tabsRO is! RenderBox) {
        return;
      }
      const gap = 8.0;
      final filtersTop = filtersRO.localToGlobal(Offset.zero).dy;
      final tabsBottom =
          tabsRO.localToGlobal(Offset(0, tabsRO.size.height)).dy;
      final delta = filtersTop - (tabsBottom + gap);
      _animateScrollController(
        _searchTabScrollController,
        _searchTabScrollController.hasClients
            ? _searchTabScrollController.offset + delta
            : 0,
      );
    });
  }

  /// After the next frame, scrolls the *inner* filter drawer scroll area so
  /// [headerKey]'s widget top sits just below the Filters box heading.
  void _scrollFilterHeaderIntoView(GlobalKey headerKey) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final headerCtx = headerKey.currentContext;
      final headingCtx = _searchTabFiltersHeadingKey.currentContext;
      if (headerCtx == null || headingCtx == null) {
        return;
      }
      final headerRO = headerCtx.findRenderObject();
      final headingRO = headingCtx.findRenderObject();
      if (headerRO is! RenderBox || headingRO is! RenderBox) {
        return;
      }
      final scrollable = Scrollable.maybeOf(headerCtx);
      final position = scrollable?.position;
      if (position == null) {
        return;
      }
      const gap = 8.0;
      final headerTop = headerRO.localToGlobal(Offset.zero).dy;
      final headingBottom =
          headingRO.localToGlobal(Offset(0, headingRO.size.height)).dy;
      final delta = headerTop - (headingBottom + gap);
      final target = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ).toDouble();
      if ((position.pixels - target).abs() < 1) {
        return;
      }
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Collapses every filter category accordion section.
  void _collapseAllFilterSections() {
    _searchTabEmploymentTypeExpanded = false;
    _searchTabPositionExpanded = false;
    _searchTabLocationExpanded = false;
    _searchTabFaaRuleExpanded = false;
    _searchTabAirframeScopeExpanded = false;
    _searchTabCertificateExpanded = false;
    _searchTabRatingExpanded = false;
    _searchTabInstructionFilterExpanded = false;
    _searchTabSpecialtyFilterExpanded = false;
  }

  /// Collapses all sections, then expands the requested one (accordion style).
  /// Pins the Filters card under the tabs and scrolls the expanded header into
  /// view within the filter drawer. If [isCurrentlyExpanded] is true the
  /// section is simply collapsed (toggle off).
  void _toggleExclusiveFilterSection({
    required bool isCurrentlyExpanded,
    required VoidCallback expandSection,
    required GlobalKey headerKey,
  }) {
    final shouldExpand = !isCurrentlyExpanded;
    setState(() {
      _collapseAllFilterSections();
      if (shouldExpand) {
        expandSection();
        _searchTabFiltersPinned = true;
      }
    });
    if (shouldExpand) {
      _pinFiltersCardBelowTabs();
      _scrollFilterHeaderIntoView(headerKey);
    }
  }

  // ---------------------------------------------------------------------------

  Widget _buildSearchTab() {
    final allVisibleJobs = _visibleJobs;
    final filteredJobs = _searchTabFilteredJobs;
    final typeOptions = _searchTabTypeOptions;
    final locationOptions = _searchTabLocationOptions;
    final positionOptions = _searchTabPositionOptions;
    final faaRuleOptions = _searchTabFaaRuleOptions;
    final airframeScopeOptions = _searchTabAirframeScopeOptions;
    final specialtyOptions = _searchTabSpecialtyOptions;
    final certificateOptions = _searchTabCertificateOptions;
    final ratingOptions = _searchTabRatingOptions;
    final instructorHoursOptions = _searchTabInstructorHoursOptions;
    final colorScheme = Theme.of(context).colorScheme;

    final selectedTypeFilters = _decodeSearchTabMultiFilter(
      _searchTabTypeFilter,
      typeOptions,
    );
    final selectedLocation = locationOptions.contains(_searchTabLocationFilter)
        ? _searchTabLocationFilter
        : 'all';
    final selectedPositionFilters = _decodeSearchTabMultiFilter(
      _searchTabPositionFilter,
      positionOptions,
    );
    final selectedFaaRuleFilters = _decodeSearchTabMultiFilter(
      _searchTabFaaRuleFilter,
      faaRuleOptions,
    );
    final selectedAirframeScopeFilters = _decodeSearchTabMultiFilter(
      _searchTabAirframeScopeFilter,
      airframeScopeOptions,
    );
    final selectedSpecialtyFilters = _decodeSearchTabMultiFilter(
      _searchTabSpecialtyFilter,
      specialtyOptions,
    );
    final selectedCertificateFilters = _decodeSearchTabMultiFilter(
      _searchTabCertificateFilter,
      certificateOptions,
    );
    final selectedRatingFilters = _decodeSearchTabMultiFilter(
      _searchTabRatingFilter,
      ratingOptions,
    );
    final selectedInstructorHourFilters = _decodeSearchTabMultiFilter(
      _searchTabInstructorHoursFilter,
      instructorHoursOptions,
    );
    final selectedSort = switch (_searchTabSort) {
      'newest' || 'deadline' || 'company' => _searchTabSort,
      _ => 'best_match',
    };
    final isNarrowSearchLayout = MediaQuery.sizeOf(context).width < 720;

    final pendingTypeFilters = _decodeSearchTabMultiFilter(
      _searchTabPendingTypeFilter ?? _encodeSearchTabMultiFilter(selectedTypeFilters),
      typeOptions,
    );
    final pendingLocation = locationOptions.contains(
      _searchTabPendingLocationFilter,
    )
      ? _searchTabPendingLocationFilter!
      : selectedLocation;
    final pendingPositionFilters = _decodeSearchTabMultiFilter(
      _searchTabPendingPositionFilter ?? _encodeSearchTabMultiFilter(selectedPositionFilters),
      positionOptions,
    );
    final pendingFaaRuleFilters = _decodeSearchTabMultiFilter(
      _searchTabPendingFaaRuleFilter ?? _encodeSearchTabMultiFilter(selectedFaaRuleFilters),
      faaRuleOptions,
    );
    final pendingAirframeScopeFilters = _decodeSearchTabMultiFilter(
      _searchTabPendingAirframeScopeFilter ?? _encodeSearchTabMultiFilter(selectedAirframeScopeFilters),
      airframeScopeOptions,
    );
    final pendingSpecialtyFilters = _decodeSearchTabMultiFilter(
      _searchTabPendingSpecialtyFilter ??
          _encodeSearchTabMultiFilter(selectedSpecialtyFilters),
      specialtyOptions,
    );
    final pendingInstructorHourFilters = _decodeSearchTabMultiFilter(
      _searchTabPendingInstructorHoursFilter ??
          _encodeSearchTabMultiFilter(selectedInstructorHourFilters),
      instructorHoursOptions,
    );
    final pendingCertificateFilters = _decodeSearchTabMultiFilter(
      _searchTabPendingCertificateFilter ??
          _encodeSearchTabMultiFilter(selectedCertificateFilters),
      certificateOptions,
    );
    final pendingRatingFilters = _decodeSearchTabMultiFilter(
      _searchTabPendingRatingFilter ?? _encodeSearchTabMultiFilter(selectedRatingFilters),
      ratingOptions,
    );
    final pendingSort = const {'best_match', 'newest', 'deadline', 'company'}
        .contains(_searchTabPendingSort)
      ? _searchTabPendingSort!
      : selectedSort;
    final hasPendingPrimaryFilterChanges =
      !setEquals(pendingTypeFilters, selectedTypeFilters) ||
      pendingLocation != selectedLocation ||
      !setEquals(pendingPositionFilters, selectedPositionFilters) ||
      !setEquals(pendingFaaRuleFilters, selectedFaaRuleFilters) ||
      !setEquals(pendingAirframeScopeFilters, selectedAirframeScopeFilters) ||
      !setEquals(pendingSpecialtyFilters, selectedSpecialtyFilters) ||
      !setEquals(pendingInstructorHourFilters, selectedInstructorHourFilters) ||
      !setEquals(pendingCertificateFilters, selectedCertificateFilters) ||
      !setEquals(pendingRatingFilters, selectedRatingFilters) ||
      pendingSort != selectedSort;
    final hasAnyVisibleDrawerSelections =
      !pendingTypeFilters.contains('all') ||
      !pendingPositionFilters.contains('all') ||
      !pendingFaaRuleFilters.contains('all') ||
      !pendingAirframeScopeFilters.contains('all') ||
      !pendingSpecialtyFilters.contains('all') ||
      !pendingInstructorHourFilters.contains('all') ||
      !pendingCertificateFilters.contains('all') ||
      !pendingRatingFilters.contains('all');

    List<String> orderOptionsByPreference(
      List<String> options,
      List<String> preferredOrder,
    ) {
      final ordered = <String>[];
      final hasAll = options.any((value) => value.toLowerCase() == 'all');
      if (hasAll) {
        final allValue = options.firstWhere(
          (value) => value.toLowerCase() == 'all',
        );
        ordered.add(allValue);
      }

      for (final preferred in preferredOrder) {
        for (final value in options) {
          if (value.toLowerCase() == preferred.toLowerCase() &&
              !ordered.contains(value)) {
            ordered.add(value);
          }
        }
      }

      final remaining = options
          .where((value) => !ordered.contains(value))
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      return [...ordered, ...remaining];
    }

    final employmentTypeFilterOptions = orderOptionsByPreference(
      typeOptions
          .where((value) => value.toLowerCase() != 'external')
          .toList(),
      const ['Full-Time', 'Part-Time', 'Seasonal', 'Contract', 'Rotations'],
    );
    final flightInstructionFilterOptions = orderOptionsByPreference(
      instructorHoursOptions,
      const [
        'Flight Instruction (CFI)',
        'Instrument (CFII)',
        'Multi-Engine (MEI)',
      ],
    );
    final specialtyFilterOptions = orderOptionsByPreference(
      specialtyOptions,
      const [
        'Fire Fighting',
        'Aerobatic',
        'Floatplane',
        'Ski-plane',
        'Alaska Time',
        'Tailwheel',
        'Off Airport',
        'Banner Towing',
        'Low Altitude',
        'Aerial Survey',
        'Low-Time Jobs',
        'Mid-Time Jobs',
      ],
    );
    final ratingFilterOptions = orderOptionsByPreference(
      ratingOptions,
      const [
        'Single-Engine Land',
        'Multi-Engine Land',
        'Single-Engine Sea',
        'Multi-Engine Sea',
        'Tailwheel Endorsement',
        'Helicopter',
        'Gyroplane',
        'Glider',
        'Lighter-than-Air',
      ],
    );
    String? findCaseInsensitiveOption(List<String> options, String target) {
      for (final option in options) {
        if (option.toLowerCase() == target.toLowerCase()) {
          return option;
        }
      }
      return null;
    }

    final certificateFilterOptions = <String>[
      if (certificateOptions.any((value) => value.toLowerCase() == 'all'))
        certificateOptions.firstWhere(
          (value) => value.toLowerCase() == 'all',
        ),
      ...const [
        'Airline Transport Pilot (ATP)',
        'Commercial Pilot (CPL)',
        'Instrument Rating (IFR)',
        'Private Pilot (PPL)',
        'Airframe & Powerplant (A&P)',
        'Inspection Authorization (IA)',
        'Dispatcher (DSP)',
      ].map((value) {
        return findCaseInsensitiveOption(certificateOptions, value);
      }).whereType<String>(),
    ];
    final certificateFilterGroups = [
      const [
        'Airline Transport Pilot (ATP)',
        'Commercial Pilot (CPL)',
        'Instrument Rating (IFR)',
        'Private Pilot (PPL)',
      ],
      const [
        'Airframe & Powerplant (A&P)',
        'Inspection Authorization (IA)',
      ],
      const ['Dispatcher (DSP)'],
    ]
        .map(
          (group) => group
              .where(
                (value) => certificateFilterOptions.any(
                  (option) => option.toLowerCase() == value.toLowerCase(),
                ),
              )
              .toList(),
        )
        .where((group) => group.isNotEmpty)
        .toList();
    final ratingFilterGroups = [
      const ['Single-Engine Land', 'Multi-Engine Land'],
      const ['Single-Engine Sea', 'Multi-Engine Sea'],
      const ['Tailwheel Endorsement'],
      const ['Helicopter', 'Gyroplane'],
      const ['Glider', 'Lighter-than-Air'],
    ]
        .map(
          (group) => group
              .where(
                (value) => ratingFilterOptions.any(
                  (option) => option.toLowerCase() == value.toLowerCase(),
                ),
              )
              .toList(),
        )
        .where((group) => group.isNotEmpty)
        .toList();

    if (!hasPendingPrimaryFilterChanges) {
      _searchTabPendingTypeFilter = _encodeSearchTabMultiFilter(
        selectedTypeFilters,
      );
      _searchTabPendingLocationFilter = selectedLocation;
      _searchTabPendingPositionFilter = _encodeSearchTabMultiFilter(
        selectedPositionFilters,
      );
      _searchTabPendingFaaRuleFilter = _encodeSearchTabMultiFilter(
        selectedFaaRuleFilters,
      );
      _searchTabPendingAirframeScopeFilter = _encodeSearchTabMultiFilter(
        selectedAirframeScopeFilters,
      );
      _searchTabPendingSpecialtyFilter = _encodeSearchTabMultiFilter(
        selectedSpecialtyFilters,
      );
      _searchTabPendingInstructorHoursFilter = _encodeSearchTabMultiFilter(
        selectedInstructorHourFilters,
      );
      _searchTabPendingCertificateFilter = _encodeSearchTabMultiFilter(
        selectedCertificateFilters,
      );
      _searchTabPendingRatingFilter = _encodeSearchTabMultiFilter(
        selectedRatingFilters,
      );
      _searchTabPendingSort = selectedSort;
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (allVisibleJobs.isEmpty) {
      return const Center(
        child: Text(
          'No jobs available yet. Check back after listings are added.',
        ),
      );
    }

    Widget buildFilterOptionBoxes({
      required String title,
      required List<String> options,
      required Set<String> selectedValues,
      required String allLabel,
      required bool isExpanded,
      required VoidCallback onToggle,
      required ValueChanged<Set<String>> onSelected,
      required Key headerKey,
      String Function(String)? displayLabelFor,
    }) {
      String displayLabel(String value) {
        if (displayLabelFor != null) {
          return displayLabelFor(value);
        }
        if (value == 'all') {
          return allLabel;
        }
        return value;
      }

      Widget buildOptionBox(String value) {
        final isSelected = selectedValues.contains(value);
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            final next = Set<String>.from(selectedValues);
            if (value == 'all') {
              onSelected({'all'});
              return;
            }

            next.remove('all');
            if (next.contains(value)) {
              next.remove(value);
            } else {
              next.add(value);
            }

            onSelected(next.isEmpty ? {'all'} : next);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: isSelected
                  ? colorScheme.primaryContainer
                  : colorScheme.surface,
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Text(
              displayLabel(value),
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurface,
              ),
            ),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onToggle,
            child: Container(
              key: headerKey,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant),
                color: colorScheme.surfaceContainerLowest,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map(buildOptionBox).toList(),
            ),
          ],
        ],
      );
    }

    Widget buildGroupedFilterOptionBoxes({
      required String title,
      required List<List<String>> groups,
      required Set<String> selectedValues,
      required String allLabel,
      required bool isExpanded,
      required VoidCallback onToggle,
      required ValueChanged<Set<String>> onSelected,
      required Key headerKey,
    }) {
      Widget buildOptionBox(String value) {
        final isSelected = selectedValues.contains(value);
        final label = value == 'all' ? allLabel : value;
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            final next = Set<String>.from(selectedValues);
            if (value == 'all') {
              onSelected({'all'});
              return;
            }

            next.remove('all');
            if (next.contains(value)) {
              next.remove(value);
            } else {
              next.add(value);
            }

            onSelected(next.isEmpty ? {'all'} : next);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: isSelected
                  ? colorScheme.primaryContainer
                  : colorScheme.surface,
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurface,
              ),
            ),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onToggle,
            child: Container(
              key: headerKey,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant),
                color: colorScheme.surfaceContainerLowest,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [buildOptionBox('all')],
            ),
            if (groups.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: colorScheme.outlineVariant, height: 1),
              ),
            ...[
              for (var i = 0; i < groups.length; i++) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: groups[i].map(buildOptionBox).toList(),
                ),
                if (i < groups.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Divider(
                      color: colorScheme.outlineVariant,
                      height: 1,
                    ),
                  ),
              ],
            ],
          ],
        ],
      );
    }

    final activeFilters = <Widget>[];

    void addActiveFilter(String label, VoidCallback onDeleted) {
      activeFilters.add(
        InputChip(
          label: Text(label),
          onDeleted: onDeleted,
          deleteIcon: const Icon(Icons.close, size: 18),
        ),
      );
    }

    if (_searchTabQuery.isNotEmpty) {
      addActiveFilter('Query: "$_searchTabQuery"', () {
        setState(() {
          _searchTabQuery = '';
          _searchTabController.clear();
        });
      });
    }
    for (final type in selectedTypeFilters.where((value) => value != 'all')) {
      addActiveFilter('Type: $type', () {
        setState(() {
          final next = Set<String>.from(selectedTypeFilters)..remove(type);
          final encoded = _encodeSearchTabMultiFilter(
            next.isEmpty ? {'all'} : next,
          );
          _searchTabTypeFilter = encoded;
          _searchTabPendingTypeFilter = encoded;
        });
      });
    }
    if (selectedLocation != 'all') {
      addActiveFilter('Location: $selectedLocation', () {
        setState(() {
          _searchTabLocationFilter = 'all';
          _searchTabPendingLocationFilter = 'all';
        });
      });
    }
    for (final position in selectedPositionFilters.where(
      (value) => value != 'all',
    )) {
      addActiveFilter('Position: $position', () {
        setState(() {
          final next = Set<String>.from(selectedPositionFilters)
            ..remove(position);
          final encoded = _encodeSearchTabMultiFilter(
            next.isEmpty ? {'all'} : next,
          );
          _searchTabPositionFilter = encoded;
          _searchTabPendingPositionFilter = encoded;
        });
      });
    }
    for (final faaRule in selectedFaaRuleFilters.where(
      (value) => value != 'all',
    )) {
      addActiveFilter('FAA: $faaRule', () {
        setState(() {
          final next = Set<String>.from(selectedFaaRuleFilters)
            ..remove(faaRule);
          final encoded = _encodeSearchTabMultiFilter(
            next.isEmpty ? {'all'} : next,
          );
          _searchTabFaaRuleFilter = encoded;
          _searchTabPendingFaaRuleFilter = encoded;
        });
      });
    }
    for (final scope in selectedAirframeScopeFilters.where(
      (value) => value != 'all',
    )) {
      addActiveFilter('Airframe: $scope', () {
        setState(() {
          final next = Set<String>.from(selectedAirframeScopeFilters)
            ..remove(scope);
          final encoded = _encodeSearchTabMultiFilter(
            next.isEmpty ? {'all'} : next,
          );
          _searchTabAirframeScopeFilter = encoded;
          _searchTabPendingAirframeScopeFilter = encoded;
        });
      });
    }
    for (final specialty in selectedSpecialtyFilters.where(
      (value) => value != 'all',
    )) {
      addActiveFilter('Specialty: $specialty', () {
        setState(() {
          final next = Set<String>.from(selectedSpecialtyFilters)
            ..remove(specialty);
          final encoded = _encodeSearchTabMultiFilter(
            next.isEmpty ? {'all'} : next,
          );
          _searchTabSpecialtyFilter = encoded;
          _searchTabPendingSpecialtyFilter = encoded;
        });
      });
    }
    for (final certificate in selectedCertificateFilters.where(
      (value) => value != 'all',
    )) {
      addActiveFilter('Certificate: $certificate', () {
        setState(() {
          final next = Set<String>.from(selectedCertificateFilters)
            ..remove(certificate);
          final encoded = _encodeSearchTabMultiFilter(
            next.isEmpty ? {'all'} : next,
          );
          _searchTabCertificateFilter = encoded;
          _searchTabPendingCertificateFilter = encoded;
        });
      });
    }
    for (final rating in selectedRatingFilters.where((value) => value != 'all')) {
      addActiveFilter('Rating: $rating', () {
        setState(() {
          final next = Set<String>.from(selectedRatingFilters)..remove(rating);
          final encoded = _encodeSearchTabMultiFilter(
            next.isEmpty ? {'all'} : next,
          );
          _searchTabRatingFilter = encoded;
          _searchTabPendingRatingFilter = encoded;
        });
      });
    }
    for (final instructor in selectedInstructorHourFilters.where(
      (value) => value != 'all',
    )) {
      addActiveFilter('Instructor Hours: $instructor', () {
        setState(() {
          final next = Set<String>.from(selectedInstructorHourFilters)
            ..remove(instructor);
          final encoded = _encodeSearchTabMultiFilter(
            next.isEmpty ? {'all'} : next,
          );
          _searchTabInstructorHoursFilter = encoded;
          _searchTabPendingInstructorHoursFilter = encoded;
        });
      });
    }
    for (final entry in _searchTabFlightHourMinimums.entries) {
      if (entry.value > 0) {
        addActiveFilter('${entry.key}: ${entry.value}+ hrs', () {
          setState(() {
            _searchTabFlightHourMinimums.remove(entry.key);
          });
        });
      }
    }
    for (final entry in _searchTabSpecialtyHourMinimums.entries) {
      if (entry.value > 0) {
        addActiveFilter('${entry.key}: ${entry.value}+ hrs', () {
          setState(() {
            _searchTabSpecialtyHourMinimums.remove(entry.key);
          });
        });
      }
    }
    for (final entry in _searchTabInstructorHourMinimums.entries) {
      if (entry.value > 0) {
        addActiveFilter('${entry.key}: ${entry.value}+ hrs', () {
          setState(() {
            _searchTabInstructorHourMinimums.remove(entry.key);
          });
        });
      }
    }
    if (_searchTabMinimumMatchPercent != 0) {
      final label = 'Qualifications Match: $_searchTabMinimumMatchPercent%+';
      addActiveFilter(label, () {
        setState(() {
          _setSearchTabMinimumMatchPercent(0);
        });
      });
    }
    if (_searchTabExternalOnly) {
      addActiveFilter('External postings only', () {
        setState(() {
          _searchTabExternalOnly = false;
        });
      });
    }
    if (selectedSort != 'best_match') {
      final label = switch (selectedSort) {
        'newest' => 'Sort: Newest',
        'deadline' => 'Sort: Deadline',
        'company' => 'Sort: Company A-Z',
        _ => 'Sort: Best Match',
      };
      addActiveFilter(label, () {
        setState(() {
          _searchTabSort = 'best_match';
          _searchTabPendingSort = 'best_match';
        });
      });
    }

    return SafeArea(
      top: false,
      child: ListView.builder(
        key: const ValueKey('search-tab-scroll'),
        controller: _searchTabScrollController,
        physics: _searchTabFiltersPinned
            ? const NeverScrollableScrollPhysics()
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: filteredJobs.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: ExpansionTile(
                    key: ValueKey(
                      'search-flight-hours-${_searchTabFlightHoursExpanded ? 'open' : 'closed'}',
                    ),
                    initiallyExpanded: _searchTabFlightHoursExpanded,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _searchTabFlightHoursExpanded = expanded;
                      });
                    },
                    leading: Icon(Icons.flight, color: colorScheme.primary),
                    title: const Text('Flight Hour Filters'),
                    subtitle: Builder(
                      builder: (context) {
                        final activeCount =
                            _searchTabFlightHourMinimums.values
                                .where((v) => v > 0)
                                .length +
                            _searchTabInstructorHourMinimums.values
                                .where((v) => v > 0)
                                .length;
                        return Text(
                          activeCount > 0
                              ? '$activeCount minimum(s) set'
                              : 'Filter by minimum hour requirements',
                        );
                      },
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'MINIMUM EXPERIENCE (HOURS)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildSearchHourSliderRow(
                              label: 'Total Time',
                              sliderMax: 5000,
                              map: _searchTabFlightHourMinimums,
                            ),
                            const SizedBox(height: 4),
                            ExpansionTile(
                              key: ValueKey(
                                'search-hours-picsic-${_searchTabPicSicExpanded ? 'open' : 'closed'}',
                              ),
                              initiallyExpanded: _searchTabPicSicExpanded,
                              onExpansionChanged: (expanded) {
                                setState(() {
                                  _searchTabPicSicExpanded = expanded;
                                });
                              },
                              tilePadding: EdgeInsets.zero,
                              title: const Text(
                                'PIC / SIC TIME',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      const Text(
                                        'Show:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Wrap(
                                        spacing: 6,
                                        children: [
                                          ChoiceChip(
                                            label: const Text('ALL'),
                                            selected:
                                                _searchTabFlightHourGroupFilter ==
                                                'all',
                                            onSelected: (_) => setState(() {
                                              _searchTabFlightHourGroupFilter =
                                                  'all';
                                            }),
                                          ),
                                          ChoiceChip(
                                            label: const Text('PIC'),
                                            selected:
                                                _searchTabFlightHourGroupFilter ==
                                                'pic',
                                            onSelected: (_) => setState(() {
                                              _searchTabFlightHourGroupFilter =
                                                  'pic';
                                            }),
                                          ),
                                          ChoiceChip(
                                            label: const Text('SIC'),
                                            selected:
                                                _searchTabFlightHourGroupFilter ==
                                                'sic',
                                            onSelected: (_) => setState(() {
                                              _searchTabFlightHourGroupFilter =
                                                  'sic';
                                            }),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (_searchTabFlightHourGroupFilter != 'sic')
                                  _buildSearchHourSliderRow(
                                    label: 'Total PIC Time',
                                    sliderMax: 3000,
                                    map: _searchTabFlightHourMinimums,
                                  ),
                                if (_searchTabFlightHourGroupFilter != 'pic')
                                  _buildSearchHourSliderRow(
                                    label: 'Total SIC Time',
                                    sliderMax: 3000,
                                    map: _searchTabFlightHourMinimums,
                                  ),
                                if (_searchTabFlightHourGroupFilter != 'sic')
                                  _buildSearchHourSliderRow(
                                    label: 'PIC Turbine',
                                    sliderMax: 1500,
                                    map: _searchTabFlightHourMinimums,
                                  ),
                                if (_searchTabFlightHourGroupFilter != 'pic')
                                  _buildSearchHourSliderRow(
                                    label: 'SIC Turbine',
                                    sliderMax: 1500,
                                    map: _searchTabFlightHourMinimums,
                                  ),
                                if (_searchTabFlightHourGroupFilter != 'sic')
                                  _buildSearchHourSliderRow(
                                    label: 'PIC Jet',
                                    sliderMax: 1000,
                                    map: _searchTabFlightHourMinimums,
                                  ),
                                if (_searchTabFlightHourGroupFilter != 'pic')
                                  _buildSearchHourSliderRow(
                                    label: 'SIC Jet',
                                    sliderMax: 1000,
                                    map: _searchTabFlightHourMinimums,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ExpansionTile(
                              key: ValueKey(
                                'search-hours-other-${_searchTabFlightHoursOtherExpanded ? 'open' : 'closed'}',
                              ),
                              initiallyExpanded:
                                  _searchTabFlightHoursOtherExpanded,
                              onExpansionChanged: (expanded) {
                                setState(() {
                                  _searchTabFlightHoursOtherExpanded = expanded;
                                });
                              },
                              tilePadding: EdgeInsets.zero,
                              title: const Text(
                                'OTHER CATEGORIES',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              children: [
                                _buildSearchHourSliderRow(
                                  label: 'Multi-engine',
                                  sliderMax: 2000,
                                  map: _searchTabFlightHourMinimums,
                                ),
                                _buildSearchHourSliderRow(
                                  label: 'Total Turbine Time',
                                  sliderMax: 3000,
                                  map: _searchTabFlightHourMinimums,
                                ),
                                _buildSearchHourSliderRow(
                                  label: 'Instrument',
                                  sliderMax: 500,
                                  map: _searchTabFlightHourMinimums,
                                ),
                                _buildSearchHourSliderRow(
                                  label: 'Cross-Country',
                                  sliderMax: 1000,
                                  map: _searchTabFlightHourMinimums,
                                ),
                                _buildSearchHourSliderRow(
                                  label: 'Night',
                                  sliderMax: 300,
                                  map: _searchTabFlightHourMinimums,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ExpansionTile(
                              key: ValueKey(
                                'search-hours-specialty-${_searchTabSpecialtyHoursExpanded ? 'open' : 'closed'}',
                              ),
                              initiallyExpanded:
                                  _searchTabSpecialtyHoursExpanded,
                              onExpansionChanged: (expanded) {
                                setState(() {
                                  _searchTabSpecialtyHoursExpanded = expanded;
                                });
                              },
                              tilePadding: EdgeInsets.zero,
                              title: const Text(
                                'SPECIALTY HOURS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              children: [
                                _buildSearchHourSliderRow(
                                  label: 'Fire Fighting',
                                  sliderMax: 2000,
                                  map: _searchTabSpecialtyHourMinimums,
                                ),
                                _buildSearchHourSliderRow(
                                  label: 'Aerobatic',
                                  sliderMax: 500,
                                  map: _searchTabSpecialtyHourMinimums,
                                ),
                                _buildSearchHourSliderRow(
                                  label: 'Floatplane',
                                  sliderMax: 500,
                                  map: _searchTabSpecialtyHourMinimums,
                                ),
                                _buildSearchHourSliderRow(
                                  label: 'Ski-plane',
                                  sliderMax: 500,
                                  map: _searchTabSpecialtyHourMinimums,
                                ),
                                _buildSearchHourSliderRow(
                                  label: 'Alaska Time',
                                  sliderMax: 1000,
                                  map: _searchTabSpecialtyHourMinimums,
                                ),
                                _buildSearchHourSliderRow(
                                  label: 'Tailwheel',
                                  sliderMax: 500,
                                  map: _searchTabSpecialtyHourMinimums,
                                ),
                                _buildSearchHourSliderRow(
                                  label: 'Off Airport',
                                  sliderMax: 500,
                                  map: _searchTabSpecialtyHourMinimums,
                                ),
                                _buildSearchHourSliderRow(
                                  label: 'Banner Towing',
                                  sliderMax: 500,
                                  map: _searchTabSpecialtyHourMinimums,
                                ),
                                _buildSearchHourSliderRow(
                                  label: 'Low Altitude',
                                  sliderMax: 500,
                                  map: _searchTabSpecialtyHourMinimums,
                                ),
                                _buildSearchHourSliderRow(
                                  label: 'Aerial Survey',
                                  sliderMax: 500,
                                  map: _searchTabSpecialtyHourMinimums,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ExpansionTile(
                              key: ValueKey(
                                'search-hours-helicopter-${_searchTabFlightHoursHelicopterExpanded ? 'open' : 'closed'}',
                              ),
                              initiallyExpanded:
                                  _searchTabFlightHoursHelicopterExpanded,
                              onExpansionChanged: (expanded) {
                                setState(() {
                                  _searchTabFlightHoursHelicopterExpanded = expanded;
                                });
                              },
                              tilePadding: EdgeInsets.zero,
                              title: const Text(
                                'HELICOPTER HOURS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              children: _availableHelicopterHours
                                  .map(
                                    (label) => _buildSearchHourSliderRow(
                                      label: label,
                                      sliderMax: _hourSliderMax(label),
                                      map: _searchTabFlightHourMinimums,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.search, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Search Query',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          key: const ValueKey('search-tab-query'),
                          controller: _searchTabController,
                          decoration: InputDecoration(
                            labelText: 'Search jobs and keywords',
                            hintText: 'Part 135, Captain, Dallas, turbine...',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            suffixIcon: _searchTabQuery.isNotEmpty
                                ? IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _searchTabQuery = '';
                                        _searchTabController.clear();
                                      });
                                    },
                                    icon: const Icon(Icons.close),
                                  )
                                : null,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchTabQuery = value.trim();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isNarrowSearchLayout ? 420 : 360),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _searchTabPrimaryFiltersDrawerOpen
                          ? Card(
                              key: const ValueKey('search-primary-filters-open'),
                              clipBehavior: Clip.antiAlias,
                              child: SizedBox(
                                key: _searchTabPrimaryFiltersCardKey,
                                height: isNarrowSearchLayout ? 540 : 580,
                                child: Column(
                                  children: [
                                    Padding(
                                      key: _searchTabFiltersHeadingKey,
                                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                                      child: Row(
                                        children: [
                                          Icon(Icons.tune, color: colorScheme.primary),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Filters',
                                            style: Theme.of(context).textTheme.titleMedium,
                                          ),
                                          const Spacer(),
                                          IconButton(
                                            tooltip: 'Close filters',
                                            onPressed: () {
                                              setState(() {
                                                _searchTabPrimaryFiltersDrawerOpen = false;
                                                _searchTabFiltersPinned = false;
                                              });
                                            },
                                            icon: const Icon(Icons.close),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Divider(height: 1),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            buildFilterOptionBoxes(
                                              title: 'Employment Type',
                                              options:
                                                employmentTypeFilterOptions,
                                              selectedValues:
                                                  pendingTypeFilters,
                                              allLabel: 'All Types',
                                              isExpanded:
                                                  _searchTabEmploymentTypeExpanded,
                                              headerKey:
                                                  _searchTabEmploymentTypeHeaderKey,
                                              onToggle: () {
                                                _toggleExclusiveFilterSection(
                                                  isCurrentlyExpanded:
                                                      _searchTabEmploymentTypeExpanded,
                                                  expandSection: () {
                                                    _searchTabEmploymentTypeExpanded =
                                                        true;
                                                  },
                                                  headerKey:
                                                      _searchTabEmploymentTypeHeaderKey,
                                                );
                                              },
                                              onSelected: (values) {
                                                setState(() {
                                                  _searchTabPendingTypeFilter =
                                                      _encodeSearchTabMultiFilter(
                                                        values,
                                                      );
                                                  _searchTabFiltersPinned = true;
                                                });
                                                _pinFiltersCardBelowTabs();
                                              },
                                            ),
                                            const SizedBox(height: 10),
                                            buildFilterOptionBoxes(
                                              title: 'Position',
                                              options: positionOptions,
                                              selectedValues:
                                                  pendingPositionFilters,
                                              allLabel: 'All Positions',
                                              isExpanded:
                                                  _searchTabPositionExpanded,
                                              headerKey:
                                                  _searchTabPositionHeaderKey,
                                              onToggle: () {
                                                _toggleExclusiveFilterSection(
                                                  isCurrentlyExpanded:
                                                      _searchTabPositionExpanded,
                                                  expandSection: () {
                                                    _searchTabPositionExpanded = true;
                                                  },
                                                  headerKey:
                                                      _searchTabPositionHeaderKey,
                                                );
                                              },
                                              onSelected: (values) {
                                                setState(() {
                                                  _searchTabPendingPositionFilter =
                                                      _encodeSearchTabMultiFilter(
                                                        values,
                                                      );
                                                  _searchTabFiltersPinned = true;
                                                });
                                                _pinFiltersCardBelowTabs();
                                              },
                                            ),
                                            const SizedBox(height: 10),
                                            buildFilterOptionBoxes(
                                              title: 'Location',
                                              options: locationOptions,
                                              selectedValues: {pendingLocation},
                                              allLabel: 'All Locations',
                                              isExpanded:
                                                  _searchTabLocationExpanded,
                                              headerKey:
                                                  _searchTabLocationHeaderKey,
                                              onToggle: () {
                                                _toggleExclusiveFilterSection(
                                                  isCurrentlyExpanded:
                                                      _searchTabLocationExpanded,
                                                  expandSection: () {
                                                    _searchTabLocationExpanded = true;
                                                  },
                                                  headerKey:
                                                      _searchTabLocationHeaderKey,
                                                );
                                              },
                                              onSelected: (values) {
                                                setState(() {
                                                  if (values.contains('all') ||
                                                      values.isEmpty) {
                                                    _searchTabPendingLocationFilter =
                                                        'all';
                                                  } else {
                                                    _searchTabPendingLocationFilter =
                                                        values.first;
                                                  }
                                                  _searchTabFiltersPinned = true;
                                                });
                                                _pinFiltersCardBelowTabs();
                                              },
                                            ),
                                            const SizedBox(height: 10),
                                            buildFilterOptionBoxes(
                                              title: 'FAA Rule',
                                              options: faaRuleOptions,
                                              selectedValues:
                                                  pendingFaaRuleFilters,
                                              allLabel: 'All FAA Rules',
                                              isExpanded:
                                                  _searchTabFaaRuleExpanded,
                                              headerKey:
                                                  _searchTabFaaRuleHeaderKey,
                                              onToggle: () {
                                                _toggleExclusiveFilterSection(
                                                  isCurrentlyExpanded:
                                                      _searchTabFaaRuleExpanded,
                                                  expandSection: () {
                                                    _searchTabFaaRuleExpanded = true;
                                                  },
                                                  headerKey:
                                                      _searchTabFaaRuleHeaderKey,
                                                );
                                              },
                                              onSelected: (values) {
                                                setState(() {
                                                  _searchTabPendingFaaRuleFilter =
                                                      _encodeSearchTabMultiFilter(
                                                        values,
                                                      );
                                                  _searchTabFiltersPinned = true;
                                                });
                                                _pinFiltersCardBelowTabs();
                                              },
                                            ),
                                            const SizedBox(height: 10),
                                            buildFilterOptionBoxes(
                                              title: 'Airframe Scope',
                                              options: airframeScopeOptions,
                                              selectedValues:
                                                  pendingAirframeScopeFilters,
                                              allLabel: 'All Scopes',
                                              isExpanded:
                                                  _searchTabAirframeScopeExpanded,
                                              headerKey:
                                                  _searchTabAirframeScopeHeaderKey,
                                              onToggle: () {
                                                _toggleExclusiveFilterSection(
                                                  isCurrentlyExpanded:
                                                      _searchTabAirframeScopeExpanded,
                                                  expandSection: () {
                                                    _searchTabAirframeScopeExpanded = true;
                                                  },
                                                  headerKey:
                                                      _searchTabAirframeScopeHeaderKey,
                                                );
                                              },
                                              onSelected: (values) {
                                                setState(() {
                                                  _searchTabPendingAirframeScopeFilter =
                                                      _encodeSearchTabMultiFilter(
                                                        values,
                                                      );
                                                  _searchTabFiltersPinned = true;
                                                });
                                                _pinFiltersCardBelowTabs();
                                              },
                                            ),
                                            const SizedBox(height: 10),
                                            buildGroupedFilterOptionBoxes(
                                              title: 'Certificate',
                                              groups: certificateFilterGroups,
                                              selectedValues:
                                                  pendingCertificateFilters,
                                              allLabel: 'All Certificates',
                                              isExpanded:
                                                  _searchTabCertificateExpanded,
                                              headerKey:
                                                  _searchTabCertificateHeaderKey,
                                              onToggle: () {
                                                _toggleExclusiveFilterSection(
                                                  isCurrentlyExpanded:
                                                      _searchTabCertificateExpanded,
                                                  expandSection: () {
                                                    _searchTabCertificateExpanded = true;
                                                  },
                                                  headerKey:
                                                      _searchTabCertificateHeaderKey,
                                                );
                                              },
                                              onSelected: (values) {
                                                setState(() {
                                                  _searchTabPendingCertificateFilter =
                                                      _encodeSearchTabMultiFilter(
                                                        values,
                                                      );
                                                  _searchTabFiltersPinned = true;
                                                });
                                                _pinFiltersCardBelowTabs();
                                              },
                                            ),
                                            const SizedBox(height: 10),
                                            buildGroupedFilterOptionBoxes(
                                              title: 'Rating',
                                              groups: ratingFilterGroups,
                                              selectedValues:
                                                  pendingRatingFilters,
                                              allLabel: 'All Ratings',
                                              isExpanded:
                                                  _searchTabRatingExpanded,
                                              headerKey:
                                                  _searchTabRatingHeaderKey,
                                              onToggle: () {
                                                _toggleExclusiveFilterSection(
                                                  isCurrentlyExpanded:
                                                      _searchTabRatingExpanded,
                                                  expandSection: () {
                                                    _searchTabRatingExpanded = true;
                                                  },
                                                  headerKey:
                                                      _searchTabRatingHeaderKey,
                                                );
                                              },
                                              onSelected: (values) {
                                                setState(() {
                                                  _searchTabPendingRatingFilter =
                                                      _encodeSearchTabMultiFilter(
                                                        values,
                                                      );
                                                  _searchTabFiltersPinned = true;
                                                });
                                                _pinFiltersCardBelowTabs();
                                              },
                                            ),
                                            const SizedBox(height: 10),
                                            buildFilterOptionBoxes(
                                              title: 'Instructor',
                                              options:
                                                  flightInstructionFilterOptions,
                                              selectedValues:
                                                pendingInstructorHourFilters,
                                              allLabel: 'None Selected',
                                              isExpanded:
                                                  _searchTabInstructionFilterExpanded,
                                              headerKey:
                                                  _searchTabInstructionHeaderKey,
                                              onToggle: () {
                                                _toggleExclusiveFilterSection(
                                                  isCurrentlyExpanded:
                                                      _searchTabInstructionFilterExpanded,
                                                  expandSection: () {
                                                    _searchTabInstructionFilterExpanded =
                                                        true;
                                                  },
                                                  headerKey:
                                                      _searchTabInstructionHeaderKey,
                                                );
                                              },
                                              onSelected: (values) {
                                                setState(() {
                                                  _searchTabPendingInstructorHoursFilter =
                                                      _encodeSearchTabMultiFilter(
                                                        values,
                                                      );
                                                  _searchTabFiltersPinned = true;
                                                });
                                                _pinFiltersCardBelowTabs();
                                              },
                                              displayLabelFor: (value) {
                                                if (value == 'all') {
                                                  return 'None Selected';
                                                }
                                                if (value ==
                                                    'Flight Instruction (CFI)') {
                                                  return 'Flight Instructor (CFI)';
                                                }
                                                if (value == 'Instrument (CFII)') {
                                                  return 'Instrument Instructor (CFII)';
                                                }
                                                if (value == 'Multi-Engine (MEI)') {
                                                  return 'Multi-Engine Instructor (MEI)';
                                                }
                                                return value;
                                              },
                                            ),
                                            if (_searchTabInstructionFilterExpanded) ...[
                                              const SizedBox(height: 10),
                                              const Text(
                                                'INSTRUCTION HOURS',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 0.8,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              _buildSearchHourSliderRow(
                                                label: 'Flight Instruction (CFI)',
                                                sliderMax: 2000,
                                                map: _searchTabInstructorHourMinimums,
                                              ),
                                              _buildSearchHourSliderRow(
                                                label: 'Instrument (CFII)',
                                                sliderMax: 1000,
                                                map: _searchTabInstructorHourMinimums,
                                              ),
                                              _buildSearchHourSliderRow(
                                                label: 'Multi-Engine (MEI)',
                                                sliderMax: 500,
                                                map: _searchTabInstructorHourMinimums,
                                              ),
                                            ],
                                            const SizedBox(height: 10),
                                            buildFilterOptionBoxes(
                                              title: 'Specialty Categories',
                                              options: specialtyFilterOptions,
                                              selectedValues:
                                                  pendingSpecialtyFilters,
                                              allLabel: 'None Selected',
                                              isExpanded:
                                                  _searchTabSpecialtyFilterExpanded,
                                              headerKey:
                                                  _searchTabSpecialtyHeaderKey,
                                              onToggle: () {
                                                _toggleExclusiveFilterSection(
                                                  isCurrentlyExpanded:
                                                      _searchTabSpecialtyFilterExpanded,
                                                  expandSection: () {
                                                    _searchTabSpecialtyFilterExpanded =
                                                        true;
                                                  },
                                                  headerKey:
                                                      _searchTabSpecialtyHeaderKey,
                                                );
                                              },
                                              onSelected: (values) {
                                                setState(() {
                                                  _searchTabPendingSpecialtyFilter =
                                                      _encodeSearchTabMultiFilter(
                                                        values,
                                                      );
                                                  _searchTabFiltersPinned = true;
                                                });
                                                _pinFiltersCardBelowTabs();
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const Divider(height: 1),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: hasAnyVisibleDrawerSelections
                                                  ? () {
                                                      setState(() {
                                                  _searchTabPendingTypeFilter = 'all';
                                                  _searchTabPendingPositionFilter = 'all';
                                                  _searchTabPendingFaaRuleFilter = 'all';
                                                  _searchTabPendingAirframeScopeFilter = 'all';
                                                  _searchTabPendingSpecialtyFilter = 'all';
                                                  _searchTabPendingInstructorHoursFilter = 'all';
                                                  _searchTabPendingCertificateFilter = 'all';
                                                  _searchTabPendingRatingFilter = 'all';
                                                  _searchTabFiltersPinned = false;
                                                      });
                                                    }
                                                  : null,
                                              child: const Text('Reset'),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: FilledButton(
                                              onPressed: hasPendingPrimaryFilterChanges
                                                  ? () {
                                                      setState(() {
                                                        _searchTabTypeFilter = _encodeSearchTabMultiFilter(
                                                          pendingTypeFilters,
                                                        );
                                                        _searchTabLocationFilter =
                                                            pendingLocation;
                                                        _searchTabPositionFilter =
                                                            _encodeSearchTabMultiFilter(
                                                              pendingPositionFilters,
                                                            );
                                                        _searchTabFaaRuleFilter =
                                                            _encodeSearchTabMultiFilter(
                                                              pendingFaaRuleFilters,
                                                            );
                                                        _searchTabAirframeScopeFilter =
                                                            _encodeSearchTabMultiFilter(
                                                              pendingAirframeScopeFilters,
                                                            );
                                                        _searchTabSpecialtyFilter =
                                                            _encodeSearchTabMultiFilter(
                                                              pendingSpecialtyFilters,
                                                            );
                                                        _searchTabInstructorHoursFilter =
                                                            _encodeSearchTabMultiFilter(
                                                              pendingInstructorHourFilters,
                                                            );
                                                        _searchTabCertificateFilter =
                                                          _encodeSearchTabMultiFilter(
                                                            pendingCertificateFilters,
                                                          );
                                                        _searchTabRatingFilter =
                                                          _encodeSearchTabMultiFilter(
                                                            pendingRatingFilters,
                                                          );
                                                        _searchTabSort = pendingSort;
                                                        _searchTabFiltersPinned = false;
                                                        _searchTabPrimaryFiltersDrawerOpen =
                                                            false;
                                                      });
                                                    }
                                                  : null,
                                              child: const Text('Apply'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Card(
                              key: const ValueKey('search-primary-filters-closed'),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _searchTabPrimaryFiltersDrawerOpen = true;
                                      _searchTabFiltersPinned = true;
                                    });
                                    _pinFiltersCardBelowTabs();
                                  },
                                  icon: const Icon(Icons.tune),
                                  label: const Text('Open Filters'),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.fact_check, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Qualifications Match',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                min: 0,
                                max: 100,
                                divisions: 100,
                                value: _searchTabMinimumMatchPercent
                                    .toDouble(),
                                label: '$_searchTabMinimumMatchPercent%+',
                                onChanged: (value) {
                                  setState(() {
                                    _setSearchTabMinimumMatchPercent(
                                      value.round(),
                                    );
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 88,
                              child: TextFormField(
                                key: const ValueKey('search-tab-match-percent'),
                                controller: _searchTabMatchPercentController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.right,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  isDense: true,
                                  suffixText: '%',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) {
                                  if (value.isEmpty) {
                                    return;
                                  }

                                  final parsed = int.tryParse(value);
                                  if (parsed == null) {
                                    return;
                                  }

                                  setState(() {
                                    _setSearchTabMinimumMatchPercent(parsed);
                                  });
                                },
                                onTapOutside: (_) {
                                  _syncSearchTabMatchPercentController();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Set to 0% to leave results unfiltered, or enter a percentage manually.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Showing ${filteredJobs.length} of ${allVisibleJobs.length} jobs',
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (activeFilters.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: activeFilters,
                        ),
                      ],
                    ],
                  ),
                ),
                if (filteredJobs.isEmpty) ...[
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        'No jobs match your current search. Try broadening your filters.',
                        style: TextStyle(color: Colors.grey.shade800),
                      ),
                    ),
                  ),
                ],
              ],
            );
          }

          final job = filteredJobs[index - 1];
          final match = _evaluateJobMatch(job);
          final deadlineText = job.deadlineDate != null
              ? _formatYmd(job.deadlineDate!.toLocal())
              : null;
          final isPhoneActionLayout =
              MediaQuery.sizeOf(context).width < kPhoneBreakpoint;

          Widget cardActionButton({
            required VoidCallback? onPressed,
            required IconData icon,
            required String label,
            bool filled = false,
            Color? iconColor,
          }) {
            if (isPhoneActionLayout) {
              final iconWidget = Icon(icon, size: 18, color: iconColor);
              if (filled) {
                return Tooltip(
                  message: label,
                  child: FilledButton.tonal(
                    onPressed: onPressed,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(40, 40),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                    child: iconWidget,
                  ),
                );
              }

              return Tooltip(
                message: label,
                child: OutlinedButton(
                  onPressed: onPressed,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(40, 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  child: iconWidget,
                ),
              );
            }

            if (filled) {
              return FilledButton.tonalIcon(
                onPressed: onPressed,
                icon: Icon(icon, color: iconColor),
                label: Text(label),
              );
            }

            return OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, color: iconColor),
              label: Text(label),
            );
          }

          final matchColor = match.matchPercentage >= 90
              ? Colors.green
              : match.matchPercentage >= 70
              ? Colors.orange
              : Colors.red;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openDetails(job),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    job.title,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (job.isExternal)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.shade50,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: Colors.teal.shade200,
                                        ),
                                      ),
                                      child: Text(
                                        'EXTERNAL JOB',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.teal.shade800,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${job.company} • ${job.location}',
                                style: TextStyle(color: Colors.grey.shade800),
                              ),
                              if (job.isExternal)
                                _buildExternalListingPhoneCta(job),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Chip(label: Text(job.type)),
                                  Chip(
                                    label: Text(
                                      '${job.crewRole}${job.crewPosition != null && job.crewPosition!.isNotEmpty ? ' - ${job.crewPosition}' : ''}',
                                    ),
                                  ),
                                ],
                              ),
                              if (deadlineText != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Deadline: $deadlineText',
                                  style: TextStyle(
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: matchColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${match.matchPercentage}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _LinkifiedText(
                      text: job.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade800),
                      onTapUrl: (url) {
                        _openDetectedLink(url);
                      },
                      onTapPhone: (phone) {
                        _openPhoneCall(phone);
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        cardActionButton(
                          onPressed: () => _toggleFavorite(job),
                          icon: _favoriteIds.contains(job.id)
                              ? Icons.star
                              : Icons.star_border,
                          iconColor: _favoriteIds.contains(job.id)
                              ? Colors.amber
                              : null,
                          label: _favoriteIds.contains(job.id)
                              ? 'Favorited'
                              : 'Favorite',
                        ),
                        cardActionButton(
                          onPressed: (job.isExternal || !_hasApplied(job.id))
                              ? () => _handleApplyTap(job)
                              : null,
                          icon: job.isExternal
                              ? Icons.open_in_new
                              : _hasApplied(job.id)
                              ? Icons.check_circle
                              : Icons.send,
                          iconColor: !job.isExternal && _hasApplied(job.id)
                              ? Colors.green
                              : null,
                          label: job.isExternal
                              ? 'Contact Employer'
                              : _hasApplied(job.id)
                              ? 'Applied'
                              : 'Apply',
                          filled: true,
                        ),
                        cardActionButton(
                          onPressed: () => _shareJobListing(job),
                          icon: Icons.share_outlined,
                          label: 'Share',
                        ),
                        cardActionButton(
                          onPressed: () => _reportJobListing(job),
                          icon: Icons.flag_outlined,
                          label: 'Report',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
                  if (job.isExternal) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        border: Border.all(color: Colors.blueGrey.shade200),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'External Listing',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.blueGrey.shade800,
                        ),
                      ),
                    ),
                  ],
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
    return stateProvinceLabel(name);
  }

  String? _normalizeCountryValue(String value) {
    return normalizeCountryValue(value);
  }

  List<String> _stateProvinceOptionsForCountry(String rawCountry) {
    return stateProvinceOptionsForCountry(rawCountry);
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
                  return Builder(
                    builder: (itemContext) {
                      final isHighlighted =
                          AutocompleteHighlightedOption.of(itemContext) ==
                          index;

                      if (isHighlighted) {
                        SchedulerBinding.instance.addPostFrameCallback((_) {
                          Scrollable.ensureVisible(
                            itemContext,
                            alignment: 0.5,
                            duration: Duration.zero,
                          );
                        });
                      }

                      return Container(
                        color: isHighlighted
                            ? Theme.of(itemContext).colorScheme.primaryContainer
                            : null,
                        child: ListTile(
                          dense: true,
                          title: Text(_stateProvinceLabel(option)),
                          onTap: () => onSelected(option),
                        ),
                      );
                    },
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
              onSubmitted: (_) => onFieldSubmitted(),
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
                        label: Text('See All Listings ($companyListingCount)'),
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
                        _buildPhoneSummaryRow(employer.contactPhone),
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
                      title: 'Airframe Scope',
                      items: [_jobSeekerProfile.airframeScope],
                      emptyText: 'No airframe scope selected',
                    ),
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
                    _buildGroupedFlightHoursSummaryCard(_jobSeekerProfile),
                    _buildChipSummaryCard(
                      title: 'Aircraft (Coming Soon)',
                      items: _jobSeekerProfile.aircraftFlown,
                      emptyText: 'No aircraft added',
                    ),
                    _buildChipSummaryCard(
                      title: 'Type Ratings (Coming Soon)',
                      items: _jobSeekerProfile.typeRatings,
                      emptyText: 'No type ratings added',
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

  Map<String, int> _part135Minimums() {
    if (!_selectedFaaRules.contains('Part 135') || _part135SubType == null) {
      return {};
    }
    if (_part135SubType == 'ifr') {
      return {
        'Total Time': 1200,
        'Cross-Country': 500,
        'Night': 100,
        'Instrument': 75,
      };
    }
    return {'Total Time': 500, 'Cross-Country': 100, 'Night': 25};
  }

  double _hourSliderMax(String label) {
    switch (label) {
      case 'Total Time':
        return 5000;
      case 'Total PIC Time':
      case 'Total SIC Time':
        return 3000;
      case 'PIC Turbine':
      case 'SIC Turbine':
        return 1500;
      case 'PIC Jet':
      case 'SIC Jet':
        return 1000;
      case 'Multi-engine':
        return 2000;
      case 'Total Turbine Time':
        return 3000;
      case 'Helicopter Time':
        return 4000;
      case 'Helicopter PIC':
        return 2500;
      case 'Cross-Country':
      case 'Alaska Time':
      case 'Flight Instruction (CFI)':
        return 1000;
      case 'Instrument':
      case 'Night':
      case 'Fire Fighting':
      case 'Instrument (CFII)':
      case 'Turbine Helicopter':
      case 'External Load':
      case 'Night Vision Ops':
        return 500;
      case 'Multi-Engine (MEI)':
      case 'Aerobatic':
      case 'Floatplane':
      case 'Ski-plane':
      case 'Tailwheel':
      case 'Off Airport':
      case 'Banner Towing':
      case 'Low Altitude':
      case 'Aerial Survey':
        return 500;
      default:
        return 1000;
    }
  }

  Widget _buildCreateHourInputRow({
    required String label,
    required Map<String, int> map,
    required Set<String> preferredSet,
    int minimumValue = 0,
  }) {
    final current = (map[label] ?? 0).clamp(0, _hourSliderMax(label).toInt());
    final isSelected = current > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SearchHourSliderRow(
            label: label,
            sliderMax: _hourSliderMax(label),
            value: current,
            onChanged: (val) {
              setState(() {
                if (val <= 0) {
                  map.remove(label);
                  preferredSet.remove(label);
                  return;
                }
                final enforced = val < minimumValue ? minimumValue : val;
                map[label] = enforced;
              });
            },
          ),
          if (minimumValue > 0)
            Padding(
              padding: const EdgeInsets.only(left: 116, bottom: 4),
              child: Text(
                'Part 135 minimum: $minimumValue hrs',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
          if (isSelected)
            Padding(
              padding: const EdgeInsets.only(left: 116, right: 4, bottom: 6),
              child: DropdownButtonFormField<String>(
                initialValue: preferredSet.contains(label)
                    ? 'Preferred'
                    : 'Required',
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Requirement',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Required', child: Text('Required')),
                  DropdownMenuItem(
                    value: 'Preferred',
                    child: Text('Preferred'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    if (value == 'Preferred') {
                      preferredSet.add(label);
                    } else {
                      preferredSet.remove(label);
                    }
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCreateCategorizedHoursSection() {
    final part135Minimums = _part135Minimums();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MINIMUM EXPERIENCE (HOURS)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
          ),
        ),
        const SizedBox(height: 6),
        _buildCreateHourInputRow(
          label: 'Total Time',
          map: _selectedFlightHours,
          preferredSet: _preferredFlightHours,
          minimumValue: part135Minimums['Total Time'] ?? 0,
        ),
        ExpansionTile(
          key: ValueKey(
            'create-hours-picsic-${_createHoursPicSicExpanded ? 'open' : 'closed'}',
          ),
          initiallyExpanded: _createHoursPicSicExpanded,
          onExpansionChanged: (expanded) {
            setState(() => _createHoursPicSicExpanded = expanded);
          },
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'PIC / SIC TIME',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Text(
                    'Show:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('ALL'),
                        selected: _createHoursGroupFilter == 'all',
                        onSelected: (_) =>
                            setState(() => _createHoursGroupFilter = 'all'),
                      ),
                      ChoiceChip(
                        label: const Text('PIC'),
                        selected: _createHoursGroupFilter == 'pic',
                        onSelected: (_) =>
                            setState(() => _createHoursGroupFilter = 'pic'),
                      ),
                      ChoiceChip(
                        label: const Text('SIC'),
                        selected: _createHoursGroupFilter == 'sic',
                        onSelected: (_) =>
                            setState(() => _createHoursGroupFilter = 'sic'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_createHoursGroupFilter != 'sic')
              _buildCreateHourInputRow(
                label: 'Total PIC Time',
                map: _selectedFlightHours,
                preferredSet: _preferredFlightHours,
              ),
            if (_createHoursGroupFilter != 'pic')
              _buildCreateHourInputRow(
                label: 'Total SIC Time',
                map: _selectedFlightHours,
                preferredSet: _preferredFlightHours,
              ),
            if (_createHoursGroupFilter != 'sic')
              _buildCreateHourInputRow(
                label: 'PIC Turbine',
                map: _selectedFlightHours,
                preferredSet: _preferredFlightHours,
              ),
            if (_createHoursGroupFilter != 'pic')
              _buildCreateHourInputRow(
                label: 'SIC Turbine',
                map: _selectedFlightHours,
                preferredSet: _preferredFlightHours,
              ),
            if (_createHoursGroupFilter != 'sic')
              _buildCreateHourInputRow(
                label: 'PIC Jet',
                map: _selectedFlightHours,
                preferredSet: _preferredFlightHours,
              ),
            if (_createHoursGroupFilter != 'pic')
              _buildCreateHourInputRow(
                label: 'SIC Jet',
                map: _selectedFlightHours,
                preferredSet: _preferredFlightHours,
              ),
          ],
        ),
        ExpansionTile(
          key: ValueKey(
            'create-hours-other-${_createHoursOtherExpanded ? 'open' : 'closed'}',
          ),
          initiallyExpanded: _createHoursOtherExpanded,
          onExpansionChanged: (expanded) {
            setState(() => _createHoursOtherExpanded = expanded);
          },
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'OTHER CATEGORIES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          children: [
            _buildCreateHourInputRow(
              label: 'Multi-engine',
              map: _selectedFlightHours,
              preferredSet: _preferredFlightHours,
            ),
            _buildCreateHourInputRow(
              label: 'Total Turbine Time',
              map: _selectedFlightHours,
              preferredSet: _preferredFlightHours,
            ),
            _buildCreateHourInputRow(
              label: 'Instrument',
              map: _selectedFlightHours,
              preferredSet: _preferredFlightHours,
              minimumValue: part135Minimums['Instrument'] ?? 0,
            ),
            _buildCreateHourInputRow(
              label: 'Cross-Country',
              map: _selectedFlightHours,
              preferredSet: _preferredFlightHours,
              minimumValue: part135Minimums['Cross-Country'] ?? 0,
            ),
            _buildCreateHourInputRow(
              label: 'Night',
              map: _selectedFlightHours,
              preferredSet: _preferredFlightHours,
              minimumValue: part135Minimums['Night'] ?? 0,
            ),
          ],
        ),
        ExpansionTile(
          key: ValueKey(
            'create-hours-specialty-${_createHoursSpecialtyExpanded ? 'open' : 'closed'}',
          ),
          initiallyExpanded: _createHoursSpecialtyExpanded,
          onExpansionChanged: (expanded) {
            setState(() => _createHoursSpecialtyExpanded = expanded);
          },
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'SPECIALTY HOURS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          children: _availableSpecialtyExperience
              .map(
                (label) => _buildCreateHourInputRow(
                  label: label,
                  map: _selectedSpecialtyHours,
                  preferredSet: _preferredSpecialtyHours,
                ),
              )
              .toList(),
        ),
        ExpansionTile(
          key: ValueKey(
            'create-hours-helicopter-${_createHoursHelicopterExpanded ? 'open' : 'closed'}',
          ),
          initiallyExpanded: _createHoursHelicopterExpanded,
          onExpansionChanged: (expanded) {
            setState(() => _createHoursHelicopterExpanded = expanded);
          },
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'HELICOPTER HOURS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          children: _availableHelicopterHours
              .map(
                (label) => _buildCreateHourInputRow(
                  label: label,
                  map: _selectedFlightHours,
                  preferredSet: _preferredFlightHours,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildSearchHourSliderRow({
    required String label,
    required double sliderMax,
    required Map<String, int> map,
    String? mapKey,
  }) {
    final key = mapKey ?? label;
    final currentVal = (map[key] ?? 0).clamp(0, sliderMax.toInt());
    return _SearchHourSliderRow(
      label: label,
      sliderMax: sliderMax,
      value: currentVal,
      onChanged: (val) {
        setState(() {
          if (val <= 0) {
            map.remove(key);
          } else {
            map[key] = val;
          }
        });
      },
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._availableFaaRules.map((rule) {
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
                  if (rule != 'Part 135') {
                    _part135SubType = null;
                    _selectedFaaCertificates.remove('Commercial Pilot (CPL)');
                    _selectedFaaCertificates.remove('Instrument Rating (IFR)');
                    _selectedFlightHours.clear();
                    for (final c in _createFlightHourControllers.values) {
                      c.dispose();
                    }
                    _createFlightHourControllers.clear();
                  }
                });
              },
            );
          }),
          if (_selectedFaaRules.contains('Part 135')) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.only(left: 16, bottom: 4),
              child: Text(
                'Part 135 Operating Type',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            RadioGroup<String>(
              groupValue: _part135SubType,
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _part135SubType = value;
                  _applyPart135Minimums(value);
                });
              },
              child: Column(
                children: const [
                  RadioListTile<String>(
                    title: Text('IFR / Commuter'),
                    subtitle: Text(
                      '1,200 TT · 500 XC · 100 Night · 75 Instrument',
                    ),
                    value: 'ifr',
                  ),
                  RadioListTile<String>(
                    title: Text('VFR Only'),
                    subtitle: Text('500 TT · 100 XC · 25 Night'),
                    value: 'vfr',
                  ),
                ],
              ),
            ),
            if (_part135SubType != null)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: Text(
                  'Minimums auto-applied to Hours Requirements. '
                  'You can still adjust them manually.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _applyPart135Minimums(String subType) {
    final Map<String, int> minimums;
    if (subType == 'ifr') {
      minimums = {
        'Total Time': 1200,
        'Cross-Country': 500,
        'Night': 100,
        'Instrument': 75,
      };
    } else if (subType == 'vfr') {
      minimums = {'Total Time': 500, 'Cross-Country': 100, 'Night': 25};
      _selectedFlightHours.remove('Instrument');
      _createFlightHourControllers['Instrument']?.text = '';
    } else {
      return;
    }

    _selectedFaaCertificates.removeWhere(
      (cert) =>
          cert == 'Airline Transport Pilot (ATP)' ||
          cert == 'Private Pilot (PPL)',
    );
    _selectedFaaCertificates.add('Commercial Pilot (CPL)');
    if (subType == 'ifr') {
      _selectedFaaCertificates.add('Instrument Rating (IFR)');
    } else {
      _selectedFaaCertificates.remove('Instrument Rating (IFR)');
    }

    for (final entry in minimums.entries) {
      _selectedFlightHours[entry.key] = entry.value;
      final ctrl = _createFlightHourControllers.putIfAbsent(
        entry.key,
        () => TextEditingController(),
      );
      ctrl.text = entry.value.toString();
    }
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
    return _selectedRequiredRatings
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
    Widget certTitle(String cert) {
      final requiredHourLabel = _requiredInstructorHourLabelForCertificate(cert);
      final showRequiredByHoursChip =
          requiredHourLabel != null &&
          _isRequiredInstructorHourSelected(
            hourLabel: requiredHourLabel,
            selectedInstructorHours: _selectedInstructorHours.keys,
            preferredInstructorHours: _preferredInstructorHours,
          ) &&
          !_selectedFaaCertificates.contains(cert);
      if (!showRequiredByHoursChip) {
        return Text(cert);
      }

      return Row(
        children: [
          Expanded(
            child: Text(
              cert,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          _buildRequiredByHoursChip(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCheckboxCard(
          options: _availableInstructorCertificates,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(8),
          titleBuilder: certTitle,
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
        ),
        const SizedBox(height: 12),
        const Text(
          'INSTRUCTION HOURS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        ..._availableInstructorHours.map(
          (label) => _buildCreateHourInputRow(
            label: label,
            map: _selectedInstructorHours,
            preferredSet: _preferredInstructorHours,
          ),
        ),
      ],
    );
  }

  Widget _buildCreateRatingsContent() {
    const landRatings = landRatingSelectionOptions;
    const seaRatings = seaRatingSelectionOptions;
    const tailwheelRating = tailwheelRatingSelectionOptions;
    const rotorRatings = rotorRatingSelectionOptions;
    const otherRatings = otherRatingSelectionOptions;

    final missingImpliedRatings = _missingImpliedRatings(
      selectedRatings: _selectedRequiredRatings,
      requiredFlightHourLabels: _selectedFlightHours.keys.where(
        (name) => !_preferredFlightHours.contains(name),
      ),
      requiredSpecialtyHourLabels: _selectedSpecialtyHours.keys.where(
        (name) => !_preferredSpecialtyHours.contains(name),
      ),
    ).toSet();

    Widget ratingTitle(String rating) {
      final isMissing =
          missingImpliedRatings.contains(rating) &&
          !_selectedRequiredRatings.contains(rating);
      if (!isMissing) {
        return Text(rating);
      }

      return Row(
        children: [
          Expanded(
            child: Text(
              rating,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Text(
              'Required by hours',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.orange.shade900,
              ),
            ),
          ),
        ],
      );
    }

    Widget buildRatingCard(List<String> options) {
      return _buildCheckboxCard(
        options: options,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        titleBuilder: ratingTitle,
        isSelected: (cert) => _selectedRequiredRatings.contains(cert),
        onChanged: (cert, selected) {
          setState(() {
            if (selected) {
              _selectedRequiredRatings.add(cert);
            } else {
              _selectedRequiredRatings.remove(cert);
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
    final createOperationalScopeSatisfied =
        _selectedFaaRules.isNotEmpty &&
        (!_selectedFaaRules.contains('Part 135') || _part135SubType != null);
    final createCertificatesSatisfied = _selectedFaaCertificates.any(
      _availableFaaCertificates.contains,
    );
    final selectedFlightHourEntries = _selectedFlightHours.entries.toList();
    final selectedInstructorHourEntries = _selectedInstructorHours.entries
        .toList();
    final selectedSpecialtyHourEntries = _selectedSpecialtyHours.entries
        .toList();
    final createHasAnyHoursSelection =
        selectedFlightHourEntries.isNotEmpty ||
        selectedInstructorHourEntries.isNotEmpty ||
        selectedSpecialtyHourEntries.isNotEmpty;
    final createHasMissingHoursValues =
        selectedFlightHourEntries.any((entry) => entry.value <= 0) ||
        selectedInstructorHourEntries.any((entry) => entry.value <= 0) ||
        selectedSpecialtyHourEntries.any((entry) => entry.value <= 0);
    final createHasRequiredFlightHour = _selectedFlightHours.keys.any(
      (name) => !_preferredFlightHours.contains(name),
    );
    final createHasRequiredInstructorHour = _selectedInstructorHours.keys.any(
      (name) => !_preferredInstructorHours.contains(name),
    );
    final createHasRequiredSpecialtyHour = _selectedSpecialtyHours.keys.any(
      (name) => !_preferredSpecialtyHours.contains(name),
    );
    final createRequiredFlightHourLabels = _selectedFlightHours.keys.where(
      (name) => !_preferredFlightHours.contains(name),
    );
    final createRequiredSpecialtyHourLabels = _selectedSpecialtyHours.keys
        .where((name) => !_preferredSpecialtyHours.contains(name));
    final createMissingImpliedRatings = _missingImpliedRatings(
      selectedRatings: _selectedRequiredRatings,
      requiredFlightHourLabels: createRequiredFlightHourLabels,
      requiredSpecialtyHourLabels: createRequiredSpecialtyHourLabels,
    );
    final createHoursSatisfied =
        createHasAnyHoursSelection &&
        !createHasMissingHoursValues &&
        (createHasRequiredFlightHour ||
            createHasRequiredInstructorHour ||
            createHasRequiredSpecialtyHour);
    final createRequiredInstructorCerts =
        _requiredInstructorCertificatesForHours(
          _selectedInstructorHours.keys.where(
            (name) => !_preferredInstructorHours.contains(name),
          ),
        );
    final createInstructorCertsSatisfied =
        createRequiredInstructorCerts.isEmpty
        ? _selectedCreateInstructorCertificates().isNotEmpty
      : createRequiredInstructorCerts.every(_selectedFaaCertificates.contains);
    final createRatingsSatisfied =
      _selectedRequiredRatings.any(_availableRatingSelections.contains) &&
      createMissingImpliedRatings.isEmpty;
    final createAirframeScopeSatisfied = _availableAirframeScopes.contains(
      _selectedAirframeScope,
    );

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
          title: createOperationalScopeSatisfied
              ? 'FAA Operational Scope'
              : 'FAA Operational Scope *',
          summary: _previewSelectionSummary(
            items: _selectedFaaRules,
            emptyLabel: 'Choose one FAA operational scope.',
          ),
          isSatisfied: createOperationalScopeSatisfied,
          initiallyExpanded: false,
          child: _buildCreateFaaRulesCard(),
        ),
        const SizedBox(height: 12),
        _buildExpandableRequirementSection(
          sectionKey: 'Airframe Scope',
          title: createAirframeScopeSatisfied
              ? 'Airframe Scope'
              : 'Airframe Scope *',
          summary: _selectedAirframeScope,
          isSatisfied: createAirframeScopeSatisfied,
          initiallyExpanded: false,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableAirframeScopes
                .map(
                  (scope) => ChoiceChip(
                    label: Text(scope),
                    selected: _selectedAirframeScope == scope,
                    onSelected: (_) {
                      setState(() {
                        _selectedAirframeScope = scope;
                      });
                    },
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
        _buildExpandableRequirementSection(
          sectionKey: 'Required FAA Certs',
          title: createCertificatesSatisfied
              ? 'Required FAA Certificates'
              : 'Required FAA Certificates *',
          summary: _previewSelectionSummary(
            items: _selectedCreateRequiredFaaCertificates(),
            emptyLabel: 'Choose required FAA certificates.',
          ),
          isSatisfied: createCertificatesSatisfied,
          initiallyExpanded: false,
          child: _buildCreateRequiredFaaCertsContent(),
        ),
        _buildExpandableRequirementSection(
          sectionKey: 'Ratings',
          title: createRatingsSatisfied
              ? 'Required Ratings'
              : createMissingImpliedRatings.isNotEmpty
              ? 'Required Ratings * (Review implied ratings)'
              : 'Required Ratings *',
          summary: _previewSelectionSummary(
            items: _selectedCreateRatings(),
            emptyLabel: 'Choose rating requirements.',
          ),
          isSatisfied: createRatingsSatisfied,
          initiallyExpanded: false,
          child: _buildCreateRatingsContent(),
        ),
        _buildExpandableRequirementSection(
          sectionKey: 'Hours Requirements',
          title: createHoursSatisfied
              ? 'Hours Requirements'
              : 'Hours Requirements *',
          summary: _hoursRequirementSummary(),
          isSatisfied: createHoursSatisfied,
          child: _buildCreateCategorizedHoursSection(),
        ),
        _buildExpandableRequirementSection(
          sectionKey: 'Instructor Certs',
          title: () {
              final hasCerts = _selectedCreateInstructorCertificates().isNotEmpty;
              final hasHours = _selectedInstructorHours.isNotEmpty;
              if (!hasCerts && !hasHours) {
                return 'Instructor Certificates and Hours (Optional)';
              }
              if (createRequiredInstructorCerts.isNotEmpty &&
                  !createInstructorCertsSatisfied) {
                return 'Instructor Certificates and Hours *';
              }
              return 'Instructor Certificates and Hours';
            }(),
          summary: _previewSelectionSummary(
            items: _selectedCreateInstructorCertificates(),
            emptyLabel: 'Choose instructor certificates as needed.',
          ),
          isSatisfied: createInstructorCertsSatisfied,
          initiallyExpanded: false,
          child: _buildCreateInstructorCertsContent(),
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
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
            PopupMenuButton<String>(
              key: const ValueKey('home-profile-switcher'),
              icon: const Icon(Icons.person),
              onSelected: (value) {
                if (value == 'admin') {
                  if (widget.adminDashboardBuilder != null) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => widget.adminDashboardBuilder!(context, (
                          switchContext,
                          selectedView,
                        ) {
                          if (selectedView == AdminInterfaceView.admin) {
                            return;
                          }

                          final initialType =
                              selectedView == AdminInterfaceView.employer
                              ? ProfileType.employer
                              : ProfileType.jobSeeker;

                          Navigator.of(switchContext).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => MyHomePage(
                                title: widget.title,
                                repository: widget.repository,
                                initialProfileType: initialType,
                                adminDashboardBuilder:
                                    widget.adminDashboardBuilder,
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                    return;
                  }

                  if (!SupabaseBootstrap.isConfigured) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Admin dashboard requires Supabase sign-in.',
                        ),
                      ),
                    );
                    return;
                  }

                  final user = Supabase.instance.client.auth.currentUser;
                  if (user == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Please sign in to open Admin dashboard.',
                        ),
                      ),
                    );
                    return;
                  }

                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => AdminDashboard(
                        adminRepository: SupabaseAdminRepository(
                          Supabase.instance.client,
                          user.id,
                        ),
                        appRepository: widget.repository,
                        adminEmail: user.email?.trim() ?? '',
                        adminRoleLabel: 'admin',
                        currentView: AdminInterfaceView.admin,
                        onSwitchView: (switchContext, selectedView) {
                          if (selectedView == AdminInterfaceView.admin) {
                            return;
                          }

                          final initialType =
                              selectedView == AdminInterfaceView.employer
                              ? ProfileType.employer
                              : ProfileType.jobSeeker;

                          Navigator.of(switchContext).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => MyHomePage(
                                title: widget.title,
                                repository: widget.repository,
                                initialProfileType: initialType,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                  return;
                }

                setState(() {
                  _profileType = value == 'employer'
                      ? ProfileType.employer
                      : ProfileType.jobSeeker;
                  _query = '';
                  _searchTabController.clear();
                  _searchTabQuery = '';
                  _searchTabTypeFilter = 'all';
                  _searchTabLocationFilter = 'all';
                  _searchTabPositionFilter = 'all';
                  _searchTabFaaRuleFilter = 'all';
                  _searchTabAirframeScopeFilter = 'all';
                  _searchTabSpecialtyFilter = 'all';
                  _searchTabCertificateFilter = 'all';
                  _searchTabRatingFilter = 'all';
                  _searchTabFlightHoursFilter = 'all';
                  _searchTabInstructorHoursFilter = 'all';
                  _setSearchTabMinimumMatchPercent(0);
                  _searchTabSort = 'best_match';
                  _searchTabExternalOnly = false;
                  _page = 1;
                });
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'jobSeeker',
                  child: Text('Job Seeker'),
                ),
                const PopupMenuItem(value: 'employer', child: Text('Employer')),
                const PopupMenuItem(value: 'admin', child: Text('Admin')),
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
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: SizedBox(
              key: _topTabsBarKey,
              height: 48,
              child: Stack(
                children: [
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: tabs,
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        width: 28,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            stops: const [0, 0.45, 1],
                            colors: [
                              Theme.of(context).colorScheme.inversePrimary,
                              Theme.of(context).colorScheme.inversePrimary
                                  .withValues(alpha: 0.58),
                              Theme.of(
                                context,
                              ).colorScheme.inversePrimary.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        width: 28,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            stops: const [0, 0.45, 1],
                            colors: [
                              Theme.of(context).colorScheme.inversePrimary,
                              Theme.of(context).colorScheme.inversePrimary
                                  .withValues(alpha: 0.58),
                              Theme.of(
                                context,
                              ).colorScheme.inversePrimary.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

class _SearchHourSliderRow extends StatefulWidget {
  const _SearchHourSliderRow({
    required this.label,
    required this.sliderMax,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double sliderMax;
  final int value;
  final void Function(int) onChanged;

  @override
  State<_SearchHourSliderRow> createState() => _SearchHourSliderRowState();
}

class _SearchHourSliderRowState extends State<_SearchHourSliderRow> {
  late final TextEditingController _controller;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value > 0 ? '${widget.value}' : '',
    );
  }

  @override
  void didUpdateWidget(_SearchHourSliderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && oldWidget.value != widget.value) {
      _controller.text = widget.value > 0 ? '${widget.value}' : '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(widget.label, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: Slider(
              value: widget.value.toDouble().clamp(0, widget.sliderMax),
              min: 0,
              max: widget.sliderMax,
              divisions: widget.sliderMax > 1000 ? 50 : 20,
              onChanged: (val) {
                final rounded = val.round();
                _controller.text = rounded > 0 ? '$rounded' : '';
                widget.onChanged(rounded);
              },
            ),
          ),
          SizedBox(
            width: 52,
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: Colors.grey.shade400),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: Colors.grey.shade400),
                ),
                isDense: true,
              ),
              onTap: () => setState(() => _isEditing = true),
              onEditingComplete: () => setState(() => _isEditing = false),
              onChanged: (text) {
                final parsed = int.tryParse(text.trim());
                if (parsed != null) {
                  final clamped = parsed.clamp(0, widget.sliderMax.toInt());
                  widget.onChanged(clamped);
                } else if (text.trim().isEmpty) {
                  widget.onChanged(0);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class JobDetailsPage extends StatelessWidget {
  static const Map<String, int> _part135IfrBaseline = {
    'Total Time': 1200,
    'Cross-Country': 500,
    'Night': 100,
    'Instrument': 75,
  };

  static const Map<String, int> _part135VfrBaseline = {
    'Total Time': 500,
    'Cross-Country': 100,
    'Night': 25,
  };

  final JobListing job;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback? onApply;
  final VoidCallback? onShare;
  final VoidCallback? onReport;
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
    this.onReport,
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

  Future<void> _openDetectedUrl(BuildContext context, String rawUrl) async {
    final uri = _parseLaunchableHttpUri(rawUrl);
    if (uri == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open this link.')));
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open this link.')));
    }
  }

  Future<void> _openPhone(BuildContext context, String rawPhone) async {
    final uri = _parseLaunchablePhoneUri(rawPhone);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start a phone call.')),
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start a phone call.')),
      );
    }
  }

  bool get _hasPart135Rule {
    final rules = job.faaRules
        .map((rule) => rule.trim().toLowerCase())
        .where((rule) => rule.isNotEmpty)
        .toSet();
    return rules.contains('part 135') ||
        rules.contains('part 135 ifr') ||
        rules.contains('part 135 commuter') ||
        rules.contains('part 135 vfr');
  }

  Map<String, int>? get _part135Baseline {
    if (!_hasPart135Rule) {
      return null;
    }

    final normalizedSubType = job.part135SubType?.trim().toLowerCase();
    if (normalizedSubType == 'ifr') {
      return _part135IfrBaseline;
    }
    if (normalizedSubType == 'vfr') {
      return _part135VfrBaseline;
    }

    var qualifiesIfr = true;
    for (final entry in _part135IfrBaseline.entries) {
      if ((job.flightHoursByType[entry.key] ?? 0) < entry.value) {
        qualifiesIfr = false;
        break;
      }
    }
    if (qualifiesIfr) {
      return _part135IfrBaseline;
    }

    var qualifiesVfr = true;
    for (final entry in _part135VfrBaseline.entries) {
      if ((job.flightHoursByType[entry.key] ?? 0) < entry.value) {
        qualifiesVfr = false;
        break;
      }
    }
    if (qualifiesVfr) {
      return _part135VfrBaseline;
    }

    return null;
  }

  String? get _part135BaselineLabel {
    final baseline = _part135Baseline;
    if (baseline == null) {
      return null;
    }
    if (identical(baseline, _part135IfrBaseline)) {
      return 'Part 135 IFR Minimums';
    }
    return 'Part 135 VFR Minimums';
  }

  String? get _part135BaselineTooltip {
    final baseline = _part135Baseline;
    final label = _part135BaselineLabel;
    if (baseline == null || label == null) {
      return null;
    }

    final detailLines = baseline.entries
        .map((entry) => '${entry.key}: ${entry.value} hrs')
        .join('\n');
    return '$label\n$detailLines';
  }

  List<MapEntry<String, int>> _summaryFlightHourEntries(Map<String, int>? baseline) {
    final entries = job.flightHoursByType.entries.toList();
    if (baseline == null) {
      return entries;
    }

    return entries.where((entry) {
      final minimum = baseline[entry.key];
      if (minimum == null) {
        return true;
      }
      return entry.value > minimum;
    }).toList();
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
    final baselineFlightHours = _part135Baseline;
    final baselineFlightLabel = _part135BaselineLabel;
    final baselineFlightTooltip = _part135BaselineTooltip;
    final standardFlightHourEntries = _summaryFlightHourEntries(
      baselineFlightHours,
    );
    final showPart135SummaryChip = baselineFlightLabel != null;
    final instructorHourEntries = job.instructorHoursByType.entries.toList();
    final timelineLabels = _buildTimelineLabels(
      createdAt: job.createdAt,
      updatedAt: job.updatedAt,
    );
    final applicationDeadlineText = job.deadlineDate != null
        ? _formatYmd(job.deadlineDate!.toLocal())
        : null;
    final externalContactName = job.contactName?.trim() ?? '';
    final externalContactEmail = job.contactEmail?.trim() ?? '';
    final externalContactPhoneRaw = job.companyPhone?.trim() ?? '';
    final externalContactPhoneFormatted = _formatPhoneNumber(
      externalContactPhoneRaw,
    );
    final externalContactPhoneDisplay = externalContactPhoneFormatted.isNotEmpty
      ? externalContactPhoneFormatted
      : externalContactPhoneRaw;
    final canCallExternalPhone =
      _isMobileDialPlatform() &&
      externalContactPhoneRaw.isNotEmpty &&
      _parseLaunchablePhoneUri(externalContactPhoneRaw) != null;
    final detailsBottomPadding = 24.0;
    final crewLabel = job.crewRole.toLowerCase() == 'crew'
        ? (job.crewPosition != null && job.crewPosition!.trim().isNotEmpty
              ? 'Crew Member - ${job.crewPosition}'
              : 'Crew Member')
        : 'Single Pilot';

    return Scaffold(
      appBar: AppBar(title: Text(job.title)),
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    job.company,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  TextButton.icon(
                                    onPressed: job.isExternal
                                        ? null
                                        : () => _openCompanyInfo(context),
                                    icon: const Icon(
                                      Icons.business_outlined,
                                      size: 18,
                                    ),
                                    label: job.isExternal
                                        ? const Text(
                                            'View Company Info (External - No Profile)',
                                          )
                                        : const Text('View Company Info'),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 32),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      alignment: Alignment.centerLeft,
                                    ),
                                  ),
                                  if (job.isExternal)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Is this your company? Claim it to post verified listings.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  Text(
                                    job.location,
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  if (job.isExternal) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.shade50,
                                        border: Border.all(
                                          color: Colors.blueGrey.shade200,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        'External Listing',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.blueGrey.shade800,
                                        ),
                                      ),
                                    ),
                                    if (externalContactName.isNotEmpty ||
                                        externalContactEmail.isNotEmpty ||
                                        externalContactPhoneDisplay.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.shade50,
                                          border: Border.all(
                                            color: Colors.teal.shade200,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'External Contact',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.teal.shade900,
                                              ),
                                            ),
                                            if (externalContactName.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 6,
                                                ),
                                                child: Text(
                                                  'Name: $externalContactName',
                                                ),
                                              ),
                                            if (externalContactEmail.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 6,
                                                ),
                                                child: Text(
                                                  'Email: $externalContactEmail',
                                                ),
                                              ),
                                            if (externalContactPhoneDisplay
                                                .isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 6,
                                                ),
                                                child: GestureDetector(
                                                  onTap: canCallExternalPhone
                                                      ? () => _openPhone(
                                                          context,
                                                          externalContactPhoneRaw,
                                                        )
                                                      : null,
                                                  child: Text(
                                                    'Phone: $externalContactPhoneDisplay',
                                                    style: TextStyle(
                                                      color:
                                                          canCallExternalPhone
                                                          ? Colors.blue
                                                          : null,
                                                      decoration:
                                                          canCallExternalPhone
                                                          ? TextDecoration
                                                                .underline
                                                          : null,
                                                      decorationColor:
                                                          canCallExternalPhone
                                                          ? Colors.blue
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                                    color:
                                                        Colors.orange.shade900,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  applicationDeadlineText,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleLarge
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: Colors
                                                            .orange
                                                            .shade900,
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
                                          label: Text(
                                            '${job.salaryRange}',
                                          ),
                                        ),
                                      Chip(label: Text(crewLabel)),
                                      Chip(label: Text(job.type)),
                                      ...job.faaRules.map(
                                        (rule) => Chip(
                                          label: Text(
                                            _formatFaaRuleDisplayWithFallback(
                                              rule,
                                              job.part135SubType,
                                              job.flightHours,
                                            ),
                                          ),
                                        ),
                                      ),
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(999),
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
                            if (profile != null)
                              _buildDetailSection(
                                context: context,
                                title: 'Your Match',
                                icon: Icons.analytics_outlined,
                                child: _buildComparisonView(context),
                              ),
                            // ── Requirements card ──────────────────────────
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: Colors.grey.shade300,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Card header
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.checklist_outlined,
                                        size: 18,
                                        color: Colors.blueGrey.shade700,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Requirements',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  // ── Certificates & Ratings ──
                                  const SizedBox(height: 14),
                                  _buildRequirementsSubsection(
                                    context,
                                    'Airframe Scope',
                                    Icons.flight_outlined,
                                    _buildChipWrap([
                                      Chip(label: Text(job.airframeScope)),
                                    ]),
                                  ),
                                  if (job.faaCertificates.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    _buildRequirementsSubsection(
                                      context,
                                      'FAA Certificates',
                                      Icons.badge_outlined,
                                      _buildChipWrap(
                                        job.faaCertificates
                                            .map(
                                              (cert) => Chip(
                                                label: Text(
                                                  canonicalCertificateLabel(
                                                    cert,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                  ],
                                  if (job.requiredRatings.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    _buildRequirementsSubsection(
                                      context,
                                      'Required Ratings',
                                      Icons.fact_check_outlined,
                                      _buildChipWrap(
                                        job.requiredRatings
                                            .map(
                                              (r) => Chip(label: Text(r)),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                  ],
                                  if (job.typeRatingsRequired.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    _buildRequirementsSubsection(
                                      context,
                                      'Type Ratings',
                                      Icons.confirmation_number_outlined,
                                      _buildChipWrap(
                                        job.typeRatingsRequired
                                            .map(
                                              (r) => Chip(label: Text(r)),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                  ],
                                  // ── Flight Time ──
                                  if (showPart135SummaryChip ||
                                      standardFlightHourEntries.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    _buildRequirementsSubsection(
                                      context,
                                      'Flight Hours',
                                      Icons.schedule_outlined,
                                      _buildChipWrap([
                                        if (showPart135SummaryChip)
                                          Tooltip(
                                            message: baselineFlightTooltip ??
                                                baselineFlightLabel,
                                            child: _buildRequirementChip(
                                              label: baselineFlightLabel,
                                              isPreferred: false,
                                            ),
                                          ),
                                        ...standardFlightHourEntries.map(
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
                                        ),
                                      ]),
                                    ),
                                  ],
                                  if (job.specialtyHoursByType.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    _buildRequirementsSubsection(
                                      context,
                                      'Specialty Hours',
                                      Icons.workspace_premium_outlined,
                                      _buildChipWrap(
                                        job.specialtyHoursByType.entries
                                            .map(
                                              (entry) => _buildRequirementChip(
                                                label:
                                                    _formatHoursRequirementLabel(
                                                      entry.key,
                                                      entry.value,
                                                      job.preferredSpecialtyHours
                                                          .contains(entry.key),
                                                    ),
                                                isPreferred: job
                                                    .preferredSpecialtyHours
                                                    .contains(entry.key),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                  ],
                                  if (instructorHourEntries.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    _buildRequirementsSubsection(
                                      context,
                                      'Instructor Hours',
                                      Icons.school_outlined,
                                      _buildChipWrap(
                                        instructorHourEntries
                                            .map(
                                              (entry) => _buildRequirementChip(
                                                label:
                                                    _formatHoursRequirementLabel(
                                                      entry.key,
                                                      entry.value,
                                                      job.preferredInstructorHours
                                                          .contains(entry.key),
                                                    ),
                                                isPreferred: job
                                                    .preferredInstructorHours
                                                    .contains(entry.key),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                  ],
                                  // ── Aircraft Experience ──
                                  if (job.aircraftFlown.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    _buildRequirementsSubsection(
                                      context,
                                      'Aircraft Experience',
                                      Icons.flight_outlined,
                                      _buildChipWrap(
                                        job.aircraftFlown
                                            .map(
                                              (a) => Chip(label: Text(a)),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // ── Job Description ──────────────────────────────
                            _buildDetailSection(
                              context: context,
                              title: 'Job Description',
                              icon: Icons.description_outlined,
                              child: _LinkifiedText(
                                text: job.description,
                                style: Theme.of(context).textTheme.bodyLarge,
                                onTapUrl: (url) {
                                  _openDetectedUrl(context, url);
                                },
                                onTapPhone: (phone) {
                                  _openPhone(context, phone);
                                },
                              ),
                            ),
                            if (job.benefits.isNotEmpty)
                              _buildDetailSection(
                                context: context,
                                title: 'Benefits',
                                icon: Icons.card_giftcard,
                                child: _buildChipWrap(
                                  job.benefits
                                      .map(
                                        (benefit) => Chip(label: Text(benefit)),
                                      )
                                      .toList(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (profile != null)
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                    ),
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
                                onPressed: onReport,
                                icon: const Icon(Icons.flag_outlined),
                                label: const Text('Report Listing'),
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
    if (job.isExternal) {
      final hasExternalUrl = (job.externalApplyUrl?.trim().isNotEmpty ?? false);
      return FilledButton.icon(
        onPressed: onApply,
        icon: const Icon(Icons.open_in_new),
        label: Text(hasExternalUrl ? 'Apply Externally' : 'Contact Employer'),
      );
    }

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
        icon: const Icon(Icons.arrow_forward),
        label: const Text('Express Interest'),
        style: FilledButton.styleFrom(backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildRequirementsSubsection(
    BuildContext context,
    String label,
    IconData icon,
    Widget content,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.blueGrey.shade600),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        content,
      ],
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
    final baselineFlightHours = _part135Baseline;
    final baselineFlightLabel = _part135BaselineLabel;
    final baselineFlightTooltip = _part135BaselineTooltip;
    final standardFlightHourEntries = _summaryFlightHourEntries(
      baselineFlightHours,
    );
    final instructorHourEntries = job.instructorHoursByType.entries.toList();
    final showPart135SummaryRow = baselineFlightHours != null;

    final hasMetPart135Baseline = baselineFlightHours != null
        ? baselineFlightHours.entries.every((entry) {
            final profileHours = profile!.flightHours[entry.key] ?? 0;
            return profile!.flightHoursTypes.contains(entry.key) &&
                profileHours >= entry.value;
          })
        : false;

    final flightRows = _buildMatchHoursRows(
      sectionTitle: 'Flight Hours:',
      entries: standardFlightHourEntries,
      isPreferredFor: (hourName) => job.preferredFlightHours.contains(hourName),
      profileHoursFor: (hourName) => profile!.flightHours[hourName] ?? 0,
      hasExperienceFor: (hourName) =>
          profile!.flightHoursTypes.contains(hourName),
      leadingRows: [
        if (showPart135SummaryRow)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  hasMetPart135Baseline ? Icons.check_circle : Icons.cancel,
                  size: 16,
                  color: hasMetPart135Baseline ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: baselineFlightTooltip ??
                        baselineFlightLabel ??
                        'Part 135 Minimums',
                    child: Text(
                      baselineFlightLabel ?? 'Part 135 Minimums',
                      style: TextStyle(
                        color:
                            hasMetPart135Baseline ? Colors.green : Colors.red,
                        decoration: hasMetPart135Baseline
                            ? null
                            : TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    final instructorRows = _buildMatchHoursRows(
      sectionTitle: 'Instructor Hours:',
      entries: instructorHourEntries,
      isPreferredFor: (hourName) => _containsInstructorHourLabel(
        job.preferredInstructorHours,
        hourName,
      ),
      profileHoursFor: (hourName) =>
          _instructorHoursForLabel(profile!.flightHours, hourName),
      hasExperienceFor: (hourName) =>
          _containsInstructorHourLabel(profile!.flightHoursTypes, hourName),
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
        job.requiredRatings.isNotEmpty ||
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
        if (job.requiredRatings.isNotEmpty) ...[
          const Text('Ratings:', style: TextStyle(fontWeight: FontWeight.bold)),
          ...job.requiredRatings.map((rating) {
            final hasIt = profileCertificates.contains(
              normalizeCertificateName(rating),
            );
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
                      rating,
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
        ...specialtyRows,
        ...instructorRows,
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
    List<Widget> leadingRows = const [],
  }) {
    final visibleEntries = entries.toList();

    if (visibleEntries.isEmpty && leadingRows.isEmpty) {
      return const [];
    }

    return [
      const SizedBox(height: 8),
      Text(sectionTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
      ...leadingRows,
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

  String get _contactNameValue {
    final profileName = employerProfile?.contactName.trim() ?? '';
    if (profileName.isNotEmpty) {
      return profileName;
    }
    return job.contactName?.trim() ?? '';
  }

  String get _contactEmailValue {
    final profileEmail = employerProfile?.contactEmail.trim() ?? '';
    if (profileEmail.isNotEmpty) {
      return profileEmail;
    }
    return job.contactEmail?.trim() ?? '';
  }

  String get _contactPhoneRaw {
    final profilePhone = employerProfile?.contactPhone.trim() ?? '';
    if (profilePhone.isNotEmpty) {
      return profilePhone;
    }
    return job.companyPhone?.trim() ?? '';
  }

  String get _contactPhoneValue =>
      _formatPhoneNumber(_contactPhoneRaw);

  String get _descriptionValue =>
      employerProfile?.companyDescription.trim() ?? '';

  List<String> get _companyBenefits =>
      employerProfile?.companyBenefits ?? const [];

  Future<void> _openWebsite(BuildContext context) async {
    final uri = _parseLaunchableHttpUri(_websiteValue);
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

  Future<void> _openPhone(BuildContext context) async {
    final uri = _parseLaunchablePhoneUri(_contactPhoneRaw);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start a phone call.')),
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start a phone call.')),
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
    final canCallPhone =
      _isMobileDialPlatform() &&
      _contactPhoneRaw.isNotEmpty &&
      _parseLaunchablePhoneUri(_contactPhoneRaw) != null;
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
                        child: _LinkifiedText(
                          text: descriptionValue,
                          style: Theme.of(context).textTheme.bodyLarge,
                          onTapUrl: (url) async {
                            final uri = _parseLaunchableHttpUri(url);
                            if (uri == null) {
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Could not open this link.')),
                              );
                              return;
                            }

                            final launched = await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                            if (!launched && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Could not open this link.')),
                              );
                            }
                          },
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
                          GestureDetector(
                            onTap: canCallPhone
                                ? () {
                                    _openPhone(context);
                                  }
                                : null,
                            child: Text(
                              'Contact Phone: ${contactPhoneValue.isNotEmpty ? contactPhoneValue : 'Not provided'}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: canCallPhone ? Colors.blue : null,
                                    decoration: canCallPhone
                                        ? TextDecoration.underline
                                        : null,
                                    decorationColor: canCallPhone
                                        ? Colors.blue
                                        : null,
                                  ),
                            ),
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
