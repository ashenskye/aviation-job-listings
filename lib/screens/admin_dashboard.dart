import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_action_log.dart';
import '../models/application.dart';
import '../models/aviation_location_catalogs.dart';
import '../models/aviation_option_catalogs.dart';
import '../models/employer_moderation.dart';
import '../models/job_listing.dart';
import '../models/job_listing_report.dart';
import '../models/job_seeker_moderation.dart';
import '../repositories/admin_repository.dart';
import '../repositories/app_repository.dart';

enum AdminInterfaceView { admin, employer, jobSeeker }

/// Full-screen admin dashboard shown to users with role='admin'.
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({
    super.key,
    required this.adminRepository,
    required this.appRepository,
    required this.adminEmail,
    required this.adminRoleLabel,
    required this.currentView,
    required this.onSwitchView,
  });

  final AdminRepository adminRepository;
  final AppRepository appRepository;
  final String adminEmail;
  final String adminRoleLabel;
  final AdminInterfaceView currentView;
  final void Function(BuildContext context, AdminInterfaceView view)
  onSwitchView;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  String get _displayAdminRoleLabel {
    final trimmed = widget.adminRoleLabel.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    return '${trimmed[0].toUpperCase()}${trimmed.substring(1).toLowerCase()}';
  }

  int _totalJobSeekers = 0;
  int _totalEmployers = 0;
  int _activeJobListings = 0;
  int _totalApplications = 0;
  List<AdminActionLog> _recentLogs = [];

  // Logs tab state
  List<AdminActionLog> _allLogs = [];
  String? _logFilterAction;
  String? _logFilterResource;
  bool _logsLoading = false;

  bool _statsLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final seekers = await widget.adminRepository.getTotalJobSeekerCount();
      final employers = await widget.adminRepository.getTotalEmployerCount();
      final listings = await widget.adminRepository.getAllJobListings();
      final apps = await widget.adminRepository.getAllApplications();

      List<AdminActionLog> logs = const [];
      try {
        logs = await widget.adminRepository.getAdminActionLogs();
      } catch (_) {
        // Audit log support may not be initialized yet; still show counts.
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _totalJobSeekers = seekers;
        _totalEmployers = employers;
        _activeJobListings = listings
            .where((listing) => listing.isActive)
            .length;
        _totalApplications = apps.length;
        _recentLogs = logs.take(10).toList();
        _allLogs = logs;
      });
    } catch (_) {
      // Stats unavailable; keep defaults
    } finally {
      if (mounted) {
        setState(() => _statsLoading = false);
      }
    }
  }

  Future<void> _loadLogs() async {
    setState(() => _logsLoading = true);
    try {
      final logs = await widget.adminRepository.getAdminActionLogs(
        actionType: _logFilterAction,
        resourceType: _logFilterResource,
      );
      if (!mounted) {
        return;
      }
      setState(() => _allLogs = logs);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load audit logs.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _logsLoading = false);
      }
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        title: const Text('Admin Dashboard'),
        actions: [
          PopupMenuButton<AdminInterfaceView>(
            key: const ValueKey('admin-dashboard-profile-switcher'),
            icon: const Icon(Icons.person),
            initialValue: widget.currentView,
            onSelected: (value) => widget.onSwitchView(context, value),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: AdminInterfaceView.jobSeeker,
                child: Text('Job Seeker'),
              ),
              PopupMenuItem(
                value: AdminInterfaceView.employer,
                child: Text('Employer'),
              ),
              PopupMenuItem(
                value: AdminInterfaceView.admin,
                child: Text('Admin'),
              ),
            ],
          ),
          if (kDebugMode && widget.adminRoleLabel.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('acct: $_displayAdminRoleLabel'),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                widget.adminEmail,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: _signOut,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
            Tab(icon: Icon(Icons.gavel), text: 'Moderation'),
            Tab(icon: Icon(Icons.post_add), text: 'External Posts'),
            Tab(icon: Icon(Icons.people), text: 'Users & Data'),
            Tab(icon: Icon(Icons.history), text: 'Audit Logs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DashboardTab(
            statsLoading: _statsLoading,
            totalJobSeekers: _totalJobSeekers,
            totalEmployers: _totalEmployers,
            activeJobListings: _activeJobListings,
            totalApplications: _totalApplications,
            recentLogs: _recentLogs,
            onRefresh: _loadStats,
          ),
          _ModerationTab(
            adminRepository: widget.adminRepository,
            onDataChanged: _loadStats,
          ),
          _ExternalPostingsTab(
            adminRepository: widget.adminRepository,
            onCreated: _loadStats,
          ),
          _UsersDataTab(
            adminRepository: widget.adminRepository,
            appRepository: widget.appRepository,
          ),
          _AuditLogsTab(
            logs: _allLogs,
            loading: _logsLoading,
            filterAction: _logFilterAction,
            filterResource: _logFilterResource,
            onFilterAction: (v) {
              setState(() => _logFilterAction = v);
              _loadLogs();
            },
            onFilterResource: (v) {
              setState(() => _logFilterResource = v);
              _loadLogs();
            },
            onRefresh: _loadLogs,
          ),
        ],
      ),
    );
  }
}

class _ExternalPostingsTab extends StatefulWidget {
  const _ExternalPostingsTab({
    required this.adminRepository,
    required this.onCreated,
  });

  final AdminRepository adminRepository;
  final Future<void> Function() onCreated;

  @override
  State<_ExternalPostingsTab> createState() => _ExternalPostingsTabState();
}

enum _ExternalPostsView { create, view }

class _ExternalPostingsTabState extends State<_ExternalPostingsTab> {
  static const List<String> _availableFaaCertificates =
      availableFaaCertificateOptions;

  static const List<String> _availableInstructorCertificates =
      availableInstructorCertificateOptions;

  static const List<String> _availableFaaRules = availableFaaRuleOptions;

  static const List<String> _availableEmployerFlightHours =
      availableEmployerFlightHourOptions;

  static const List<String> _availableInstructorHours =
      availableInstructorHourOptions;

  static const List<String> _availableSpecialtyExperience =
      availableSpecialtyExperienceOptions;

  static const List<String> _availableJobTypes = availableJobTypeOptions;

  static const List<String> _availablePayRateMetrics =
      availablePayRateMetricOptions;

  static const List<String> _availableRatingSelections =
      availableRatingSelectionOptions;

  final _titleController = TextEditingController();
  final _companyController = TextEditingController();
  final _locationCityController = TextEditingController();
  final _locationStateController = TextEditingController();
  final _locationCountryController = TextEditingController(text: 'USA');
  final _employmentTypeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _startingPayController = TextEditingController();
  final _payForExperienceController = TextEditingController();
  final _typeRatingsController = TextEditingController();
  final _aircraftController = TextEditingController();
  final _sourceNameController = TextEditingController();
  final _sourceUrlController = TextEditingController();
  final _reasonController = TextEditingController();

  _ExternalPostsView _selectedView = _ExternalPostsView.create;
  List<JobListing> _externalListings = const [];
  JobListing? _editingListing;
  final Set<String> _archivingListingIds = <String>{};
  final Set<String> _deletingListingIds = <String>{};
  bool _externalListingsLoading = false;
  bool _isSubmitting = false;
  String? _selectedPositionOption;
  String? _selectedPayRateMetric;
  String _selectedCrewRole = 'Single Pilot';
  String _selectedCrewPosition = 'Captain';
  bool _openListing = true;
  DateTime? _deadlineDate;
  final Set<String> _selectedFaaCertificates = <String>{};
  final Set<String> _selectedFaaRules = <String>{};
  final Map<String, int> _selectedFlightHours = <String, int>{};
  final Set<String> _preferredFlightHours = <String>{};
  final Map<String, int> _selectedInstructorHours = <String, int>{};
  final Set<String> _preferredInstructorHours = <String>{};
  final Map<String, int> _selectedSpecialtyHours = <String, int>{};
  final Set<String> _preferredSpecialtyHours = <String>{};

  @override
  void initState() {
    super.initState();
    _locationCountryController.text = 'USA';
    _loadExternalListings();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _companyController.dispose();
    _locationCityController.dispose();
    _locationStateController.dispose();
    _locationCountryController.dispose();
    _employmentTypeController.dispose();
    _descriptionController.dispose();
    _startingPayController.dispose();
    _payForExperienceController.dispose();
    _typeRatingsController.dispose();
    _aircraftController.dispose();
    _sourceNameController.dispose();
    _sourceUrlController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadExternalListings() async {
    setState(() => _externalListingsLoading = true);
    try {
      final listings = await widget.adminRepository.getExternalJobListings();
      if (!mounted) {
        return;
      }
      setState(() => _externalListings = listings);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load external listings.')),
      );
    } finally {
      if (mounted) {
        setState(() => _externalListingsLoading = false);
      }
    }
  }

  Future<void> _submitExternalListing() async {
    if (_isSubmitting) {
      return;
    }

    final title = _titleController.text.trim();
    final company = _companyController.text.trim();
    final locationError = _validateLocationInput();
    if (locationError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(locationError)));
      return;
    }
    final location = _buildListingLocation();
    final employmentType = _employmentTypeController.text.trim();
    final sourceName = _sourceNameController.text.trim();
    final rawSourceUrl = _sourceUrlController.text.trim();
    final reason = _reasonController.text.trim();
    var sourceUrl = rawSourceUrl;

    if (rawSourceUrl.isNotEmpty) {
      sourceUrl = rawSourceUrl.contains('://')
          ? rawSourceUrl
          : 'https://$rawSourceUrl';
      final parsed = Uri.tryParse(sourceUrl);
      final looksValid =
          parsed != null &&
          (parsed.scheme == 'http' || parsed.scheme == 'https') &&
          (parsed.host.isNotEmpty);
      if (!looksValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Source URL looks invalid. Please check and try again.',
            ),
          ),
        );
        return;
      }
    }

    final descriptionInput = _descriptionController.text.trim();
    final salaryRange = _buildExternalSalaryRange();
    final selectedTypeRatings = _splitCommaSeparatedValues(
      _typeRatingsController.text,
    );
    final selectedAircraft = _splitCommaSeparatedValues(
      _aircraftController.text,
    );

    final selectedFlightHours = {
      for (final entry in _selectedFlightHours.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    final selectedInstructorHours = {
      for (final entry in _selectedInstructorHours.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    final selectedSpecialtyHours = {
      for (final entry in _selectedSpecialtyHours.entries)
        if (entry.value > 0) entry.key: entry.value,
    };

    final preferredFlightHours = _preferredFlightHours
        .where(selectedFlightHours.containsKey)
        .toList();
    final preferredInstructorHours = _preferredInstructorHours
        .where(selectedInstructorHours.containsKey)
        .toList();
    final preferredSpecialtyHours = _preferredSpecialtyHours
        .where(selectedSpecialtyHours.containsKey)
        .toList();

    final minimumHours = _deriveMinimumHours(
      selectedFlightHours: selectedFlightHours,
      selectedInstructorHours: selectedInstructorHours,
      selectedSpecialtyHours: selectedSpecialtyHours,
    );

    final descriptionLines = <String>[
      if (descriptionInput.isNotEmpty) descriptionInput,
      if (descriptionInput.isEmpty)
        'Externally sourced listing posted by admin.',
      '',
      'External listing details:',
      if (sourceName.isNotEmpty) 'Source: $sourceName',
      if (sourceUrl.isNotEmpty) 'Source URL: $sourceUrl',
      'Apply externally. Do not use in-app apply.',
    ];
    final description = descriptionLines.join('\n').trim();

    setState(() => _isSubmitting = true);
    try {
      final activeEditListing = _editingListing;

      if (activeEditListing == null) {
        final created = await widget.adminRepository.createExternalJobListing(
          title: title.isEmpty ? 'External Opportunity' : title,
          company: company.isEmpty ? 'External Company' : company,
          location: location.isEmpty ? 'Location not specified' : location,
          employmentType: employmentType.isEmpty ? 'External' : employmentType,
          crewRole: _selectedCrewRole,
          crewPosition: _selectedCrewRole == 'Crew'
              ? _selectedCrewPosition
              : null,
          faaRules: _selectedFaaRules.toList(),
          faaCertificates: _selectedFaaCertificates.toList(),
          typeRatingsRequired: selectedTypeRatings,
          flightHours: selectedFlightHours,
          preferredFlightHours: preferredFlightHours,
          instructorHours: selectedInstructorHours,
          preferredInstructorHours: preferredInstructorHours,
          specialtyHours: selectedSpecialtyHours,
          preferredSpecialtyHours: preferredSpecialtyHours,
          aircraftFlown: selectedAircraft,
          salaryRange: salaryRange,
          minimumHours: minimumHours,
          deadlineDate: _openListing ? null : _deadlineDate,
          autoRejectThreshold: 0,
          reapplyWindowDays: 30,
          description: description,
          externalApplyUrl: sourceUrl.isEmpty ? null : sourceUrl,
          reason: reason.isEmpty ? 'Admin posted external listing' : reason,
        );

        if (!mounted) {
          return;
        }

        _clearExternalListingForm();

        await widget.onCreated();
        await _loadExternalListings();
        if (!mounted) {
          return;
        }

        setState(() => _selectedView = _ExternalPostsView.view);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('External listing posted: ${created.title}')),
        );
      } else {
        final updated = activeEditListing.copyWith(
          title: title.isEmpty ? 'External Opportunity' : title,
          company: company.isEmpty ? 'External Company' : company,
          location: location.isEmpty ? 'Location not specified' : location,
          type: employmentType.isEmpty ? 'External' : employmentType,
          crewRole: _selectedCrewRole,
          crewPosition: _selectedCrewRole == 'Crew'
              ? _selectedCrewPosition
              : null,
          faaRules: _selectedFaaRules.toList(),
          faaCertificates: _selectedFaaCertificates.toList(),
          typeRatingsRequired: selectedTypeRatings,
          flightExperience: [
            ...selectedFlightHours.keys,
            ...selectedInstructorHours.keys,
          ],
          flightHours: selectedFlightHours,
          preferredFlightHours: preferredFlightHours,
          instructorHours: selectedInstructorHours,
          preferredInstructorHours: preferredInstructorHours,
          specialtyExperience: selectedSpecialtyHours.keys.toList(),
          specialtyHours: selectedSpecialtyHours,
          preferredSpecialtyHours: preferredSpecialtyHours,
          aircraftFlown: selectedAircraft,
          salaryRange: salaryRange,
          minimumHours: minimumHours,
          deadlineDate: _openListing ? null : _deadlineDate,
          autoRejectThreshold: 0,
          reapplyWindowDays: 30,
          description: description,
          externalApplyUrl: sourceUrl.isEmpty ? null : sourceUrl,
          updatedAt: DateTime.now(),
        );

        await widget.adminRepository.updateJobListing(
          activeEditListing.id,
          updated,
          reason.isEmpty ? 'Admin updated external listing' : reason,
        );

        if (!mounted) {
          return;
        }

        _clearExternalListingForm();
        await widget.onCreated();
        await _loadExternalListings();
        if (!mounted) {
          return;
        }

        setState(() => _selectedView = _ExternalPostsView.view);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('External listing updated: ${updated.title}')),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not post external listing: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _clearExternalListingForm() {
    _titleController.clear();
    _companyController.clear();
    _locationCityController.clear();
    _locationStateController.clear();
    _locationCountryController.text = 'USA';
    _employmentTypeController.clear();
    _descriptionController.clear();
    _startingPayController.clear();
    _payForExperienceController.clear();
    _typeRatingsController.clear();
    _aircraftController.clear();
    _sourceNameController.clear();
    _sourceUrlController.clear();
    _reasonController.clear();
    _selectedPositionOption = null;
    _selectedPayRateMetric = null;
    _selectedCrewRole = 'Single Pilot';
    _selectedCrewPosition = 'Captain';
    _openListing = true;
    _deadlineDate = null;
    _selectedFaaCertificates.clear();
    _selectedFaaRules.clear();
    _selectedFlightHours.clear();
    _preferredFlightHours.clear();
    _selectedInstructorHours.clear();
    _preferredInstructorHours.clear();
    _selectedSpecialtyHours.clear();
    _preferredSpecialtyHours.clear();
    _editingListing = null;
  }

  List<String> _splitCommaSeparatedValues(String input) {
    return input
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }

  String? _validateLocationInput() {
    final city = _locationCityController.text.trim();
    final state = _locationStateController.text.trim();

    if (city.isEmpty && state.isEmpty) {
      return null;
    }
    if (city.isEmpty || state.isEmpty) {
      return 'Location must include both city and state / province.';
    }
    if (!isValidStateProvinceForCountry(
      _locationCountryController.text,
      state,
    )) {
      return 'Choose a valid state / province from the dropdown list.';
    }
    return null;
  }

  String _buildListingLocation() {
    return formatCityStateLocation(
      city: _locationCityController.text,
      stateOrProvince: _locationStateController.text,
    );
  }

  int? _parsePositiveInt(String raw) {
    final value = int.tryParse(raw.trim());
    if (value == null || value <= 0) {
      return null;
    }
    return value;
  }

  String? _buildExternalSalaryRange() {
    final startingPay = _parsePositiveInt(_startingPayController.text);
    if (startingPay == null) {
      return null;
    }

    final topEndPay = _parsePositiveInt(_payForExperienceController.text);
    final metricSuffix = _selectedPayRateMetric == null
        ? ''
        : ' / ${_selectedPayRateMetric!}';

    final startLabel = '\$${startingPay.toString()}';
    if (topEndPay == null) {
      return '$startLabel$metricSuffix';
    }

    return '$startLabel - \$${topEndPay.toString()}$metricSuffix';
  }

  int? _deriveMinimumHours({
    required Map<String, int> selectedFlightHours,
    required Map<String, int> selectedInstructorHours,
    required Map<String, int> selectedSpecialtyHours,
  }) {
    final totalTime = selectedFlightHours['Total Time'];
    if (totalTime != null && totalTime > 0) {
      return totalTime;
    }

    final allHours = [
      ...selectedFlightHours.values,
      ...selectedInstructorHours.values,
      ...selectedSpecialtyHours.values,
    ].where((value) => value > 0);

    if (allHours.isEmpty) {
      return null;
    }
    return allHours.reduce((a, b) => a < b ? a : b);
  }

  String _extractSummary(String description) {
    const detailsHeader = '\n\nExternal listing details:';
    final markerIndex = description.indexOf(detailsHeader);
    if (markerIndex < 0) {
      return description.trim();
    }
    return description.substring(0, markerIndex).trim();
  }

  String _extractDetailLine(String description, String prefix) {
    final lines = description.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith(prefix)) {
        return trimmed.substring(prefix.length).trim();
      }
    }
    return '';
  }

  void _beginEditExternalListing(JobListing listing) {
    final summary = _extractSummary(listing.description);
    final sourceName = _extractDetailLine(listing.description, 'Source:');
    final sourceUrl = (listing.externalApplyUrl?.trim().isNotEmpty ?? false)
        ? listing.externalApplyUrl!.trim()
        : _extractDetailLine(listing.description, 'Source URL:');

    final positionOption = listing.crewRole == 'Single Pilot'
        ? 'Single Pilot'
        : (listing.crewPosition == 'Co-Pilot'
              ? 'Crew Member: Co-Pilot'
              : 'Crew Member: Captain');
    final parsedLocation = parseCityStateLocation(listing.location);

    setState(() {
      _editingListing = listing;
      _selectedView = _ExternalPostsView.create;
      _titleController.text = listing.title;
      _companyController.text = listing.company;
      _locationCityController.text = parsedLocation.city;
      _locationStateController.text = parsedLocation.stateOrProvince;
      _locationCountryController.text = parsedLocation.country;
      _employmentTypeController.text = listing.type;
      _descriptionController.text = summary;
      _typeRatingsController.text = listing.typeRatingsRequired.join(', ');
      _aircraftController.text = listing.aircraftFlown.join(', ');
      _sourceNameController.text = sourceName;
      _sourceUrlController.text = sourceUrl;
      _selectedPositionOption = positionOption;
      _selectedCrewRole = listing.crewRole;
      _selectedCrewPosition = listing.crewPosition ?? 'Captain';
      _selectedFaaRules
        ..clear()
        ..addAll(listing.faaRules);
      _selectedFaaCertificates
        ..clear()
        ..addAll(listing.faaCertificates);
      _selectedFlightHours
        ..clear()
        ..addAll(listing.flightHours);
      _preferredFlightHours
        ..clear()
        ..addAll(listing.preferredFlightHours);
      _selectedInstructorHours
        ..clear()
        ..addAll(listing.instructorHours);
      _preferredInstructorHours
        ..clear()
        ..addAll(listing.preferredInstructorHours);
      _selectedSpecialtyHours
        ..clear()
        ..addAll(listing.specialtyHours);
      _preferredSpecialtyHours
        ..clear()
        ..addAll(listing.preferredSpecialtyHours);
      _openListing = listing.deadlineDate == null;
      _deadlineDate = listing.deadlineDate;
      _startingPayController.clear();
      _payForExperienceController.clear();
      _reasonController.text = '';
    });
  }

  void _cancelEditing() {
    setState(_clearExternalListingForm);
  }

  Widget _buildLocationCountryField() {
    final normalizedCountry = normalizeCountryValue(
      _locationCountryController.text,
    );
    return DropdownButtonFormField<String>(
      key: ValueKey('admin-external-country-${normalizedCountry ?? 'none'}'),
      initialValue: normalizedCountry,
      decoration: const InputDecoration(
        labelText: 'Country',
        border: OutlineInputBorder(),
      ),
      items: countryOptions
          .map(
            (country) =>
                DropdownMenuItem<String>(value: country, child: Text(country)),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) {
          return;
        }
        setState(() {
          _locationCountryController.text = value;
          if (!isValidStateProvinceForCountry(
            value,
            _locationStateController.text,
          )) {
            _locationStateController.clear();
          }
        });
      },
    );
  }

  Widget _buildLocationStateField() {
    final countryKey =
        normalizeCountryValue(_locationCountryController.text) ?? 'any';

    return Autocomplete<String>(
      key: ValueKey('admin-external-state-$countryKey'),
      initialValue: TextEditingValue(text: _locationStateController.text),
      optionsBuilder: (textEditingValue) {
        final scopedOptions = stateProvinceOptionsForCountry(
          _locationCountryController.text,
        );
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) {
          return scopedOptions;
        }

        final exactAbbreviationMatches = stateProvinceAbbreviations.entries
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
          final abbreviation = (stateProvinceAbbreviations[option] ?? '')
              .toLowerCase();
          final words = optionLower.split(RegExp(r'[\s-]+'));

          return optionLower.startsWith(query) ||
              words.any((word) => word.startsWith(query)) ||
              abbreviation.startsWith(query);
        });
      },
      onSelected: (selection) {
        _locationStateController.text = selection;
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
                    title: Text(stateProvinceLabel(option)),
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
            if (textEditingController.text != _locationStateController.text) {
              textEditingController.value = TextEditingValue(
                text: _locationStateController.text,
                selection: TextSelection.collapsed(
                  offset: _locationStateController.text.length,
                ),
              );
            }
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: 'State / Province',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                _locationStateController.text = value;
              },
            );
          },
    );
  }

  Future<String?> _promptArchiveReason(JobListing listing) async {
    final controller = TextEditingController();
    String? errorText;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Archive ${listing.title}?'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Enter reason for archiving this external listing.',
              border: const OutlineInputBorder(),
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(() {
                    errorText = 'Reason is required.';
                  });
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmArchive(JobListing listing) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm archive'),
        content: Text(
          'Archive external listing "${listing.title}" from ${listing.company}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _archiveExternalListing(JobListing listing) async {
    if (_archivingListingIds.contains(listing.id) || !listing.isActive) {
      return;
    }

    final reason = await _promptArchiveReason(listing);
    if (reason == null) {
      return;
    }

    final confirmed = await _confirmArchive(listing);
    if (!confirmed) {
      return;
    }

    setState(() {
      _archivingListingIds.add(listing.id);
    });

    try {
      await widget.adminRepository.deleteJobListing(listing.id, reason);
      if (!mounted) {
        return;
      }
      await widget.onCreated();
      await _loadExternalListings();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Archived external listing: ${listing.title}')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not archive listing: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _archivingListingIds.remove(listing.id);
        });
      }
    }
  }

  Future<String?> _promptDeleteReason(JobListing listing) async {
    final controller = TextEditingController();
    String? errorText;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Delete ${listing.title}?'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Enter reason for deleting this external listing.',
              border: const OutlineInputBorder(),
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(() {
                    errorText = 'Reason is required.';
                  });
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(JobListing listing) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm delete'),
        content: Text(
          'Delete external listing "${listing.title}" from ${listing.company}? This permanently deletes the listing and does not archive it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteExternalListing(JobListing listing) async {
    if (_deletingListingIds.contains(listing.id)) {
      return;
    }

    final reason = await _promptDeleteReason(listing);
    if (reason == null) {
      return;
    }

    final confirmed = await _confirmDelete(listing);
    if (!confirmed) {
      return;
    }

    setState(() {
      _deletingListingIds.add(listing.id);
    });

    try {
      await widget.adminRepository.hardDeleteJobListing(listing.id, reason);
      if (!mounted) {
        return;
      }
      await widget.onCreated();
      await _loadExternalListings();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted external listing: ${listing.title}')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete listing: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _deletingListingIds.remove(listing.id);
        });
      }
    }
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Not set';
    }
    return value.toLocal().toString().substring(0, 19);
  }

  String _joinOrNone(Iterable<String> values) {
    final cleaned = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (cleaned.isEmpty) {
      return 'None';
    }
    return cleaned.join(', ');
  }

  String _formatHoursMap(Map<String, int> values) {
    final entries = values.entries.where((entry) => entry.value > 0).toList();
    if (entries.isEmpty) {
      return 'None';
    }
    return entries.map((entry) => '${entry.key}: ${entry.value}').join(', ');
  }

  Future<void> _showExternalListingDetails(JobListing listing) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(listing.title),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${listing.company} • ${listing.location}'),
                const SizedBox(height: 8),
                Text('Type: ${listing.type}'),
                Text('Status: ${listing.isActive ? 'Active' : 'Archived'}'),
                Text(
                  'Crew: ${listing.crewRole == 'Crew' ? 'Crew - ${listing.crewPosition ?? 'Captain'}' : 'Single Pilot'}',
                ),
                Text('External URL: ${listing.externalApplyUrl ?? 'None'}'),
                Text('Created: ${_formatDateTime(listing.createdAt)}'),
                Text('Updated: ${_formatDateTime(listing.updatedAt)}'),
                Text('Deadline: ${_formatDateTime(listing.deadlineDate)}'),
                const SizedBox(height: 12),
                const Text(
                  'Description',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  listing.description.trim().isEmpty
                      ? 'No description provided.'
                      : listing.description,
                ),
                const SizedBox(height: 12),
                Text('FAA Rules: ${_joinOrNone(listing.faaRules)}'),
                Text(
                  'FAA Certificates: ${_joinOrNone(listing.faaCertificates)}',
                ),
                Text(
                  'Type Ratings: ${_joinOrNone(listing.typeRatingsRequired)}',
                ),
                Text('Aircraft: ${_joinOrNone(listing.aircraftFlown)}'),
                Text('Flight Hours: ${_formatHoursMap(listing.flightHours)}'),
                Text(
                  'Preferred Flight Hours: ${_joinOrNone(listing.preferredFlightHours)}',
                ),
                Text(
                  'Instructor Hours: ${_formatHoursMap(listing.instructorHours)}',
                ),
                Text(
                  'Preferred Instructor Hours: ${_joinOrNone(listing.preferredInstructorHours)}',
                ),
                Text(
                  'Specialty Hours: ${_formatHoursMap(listing.specialtyHours)}',
                ),
                Text(
                  'Preferred Specialty Hours: ${_joinOrNone(listing.preferredSpecialtyHours)}',
                ),
                Text('Minimum Hours: ${listing.minimumHours ?? 'Not set'}'),
                Text('Salary Range: ${listing.salaryRange ?? 'Not set'}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('Create New External Listing'),
                selected: _selectedView == _ExternalPostsView.create,
                onSelected: (_) {
                  setState(() {
                    _selectedView = _ExternalPostsView.create;
                  });
                },
              ),
              ChoiceChip(
                label: Text(
                  'View External Listings (${_externalListings.length})',
                ),
                selected: _selectedView == _ExternalPostsView.view,
                onSelected: (_) {
                  setState(() {
                    _selectedView = _ExternalPostsView.view;
                  });
                  _loadExternalListings();
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh external listings',
                onPressed: _loadExternalListings,
              ),
            ],
          ),
        ),
        Expanded(
          child: _selectedView == _ExternalPostsView.create
              ? _buildCreateExternalListingView()
              : _buildExternalListingsView(),
        ),
      ],
    );
  }

  Widget _buildCreateExternalListingView() {
    return Column(
      children: [
        if (_editingListing != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border.all(color: Colors.blue.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.edit_note, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Editing external listing: ${_editingListing!.title}',
                    style: TextStyle(
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _cancelEditing,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.public, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Mirror the standard Create New Listing flow for externally sourced jobs. All fields are optional for incomplete scraped data.',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _companyController,
                decoration: const InputDecoration(
                  labelText: 'Company (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _locationCityController,
                decoration: const InputDecoration(
                  labelText: 'City (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildLocationCountryField()),
                  const SizedBox(width: 12),
                  Expanded(child: _buildLocationStateField()),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue:
                    _availableJobTypes.contains(_employmentTypeController.text)
                    ? _employmentTypeController.text
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Employment Type (optional)',
                  border: OutlineInputBorder(),
                ),
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
                    _employmentTypeController.text = value ?? '';
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedPositionOption,
                decoration: const InputDecoration(
                  labelText: 'Position Selection (optional)',
                  border: OutlineInputBorder(),
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
                  setState(() {
                    _selectedPositionOption = value;
                    if (value == null || value == 'Single Pilot') {
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
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Salary Range (optional)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _startingPayController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Starting Pay',
                              prefixText: r'$',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _payForExperienceController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Top End Starting Pay',
                              prefixText: r'$',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedPayRateMetric,
                      decoration: const InputDecoration(
                        labelText: 'Pay Metric',
                        border: OutlineInputBorder(),
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
                          _selectedPayRateMetric = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description / Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sourceNameController,
                decoration: const InputDecoration(
                  labelText: 'Source Name (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sourceUrlController,
                decoration: const InputDecoration(
                  labelText: 'Source URL (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Admin Reason (audit log)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Application Timeline (optional)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    RadioGroup<bool>(
                      groupValue: _openListing,
                      onChanged: (value) {
                        setState(() {
                          _openListing = value ?? true;
                          if (_openListing) {
                            _deadlineDate = null;
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
                    if (!_openListing)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final initialDate =
                                _deadlineDate ??
                                DateTime.now().add(const Duration(days: 30));
                            final pickedDate = await showDatePicker(
                              context: context,
                              initialDate: initialDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 730),
                              ),
                            );
                            if (pickedDate == null || !mounted) {
                              return;
                            }
                            setState(() {
                              _deadlineDate = pickedDate;
                            });
                          },
                          icon: const Icon(Icons.event),
                          label: Text(
                            _deadlineDate == null
                                ? 'Choose deadline date'
                                : 'Application Deadline: ${_deadlineDate!.toLocal().toString().substring(0, 10)}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildCheckboxCard(
                title: 'FAA Operational Scope (optional)',
                options: _availableFaaRules,
                isSelected: (option) => _selectedFaaRules.contains(option),
                onChanged: (option, selected) {
                  setState(() {
                    if (selected) {
                      _selectedFaaRules
                        ..clear()
                        ..add(option);
                    } else {
                      _selectedFaaRules.remove(option);
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              _buildCheckboxCard(
                title: 'Required FAA Certificates (optional)',
                options: _availableFaaCertificates,
                isSelected: (option) =>
                    _selectedFaaCertificates.contains(option),
                onChanged: (option, selected) {
                  setState(() {
                    if (selected) {
                      _selectedFaaCertificates.add(option);
                    } else {
                      _selectedFaaCertificates.remove(option);
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              _buildCheckboxCard(
                title: 'Instructor Certificates (optional)',
                options: _availableInstructorCertificates,
                isSelected: (option) =>
                    _selectedFaaCertificates.contains(option),
                onChanged: (option, selected) {
                  setState(() {
                    if (selected) {
                      _selectedFaaCertificates.add(option);
                    } else {
                      _selectedFaaCertificates.remove(option);
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              _buildCheckboxCard(
                title: 'Required Ratings (optional)',
                options: _availableRatingSelections,
                isSelected: (option) =>
                    _selectedFaaCertificates.contains(option),
                onChanged: (option, selected) {
                  setState(() {
                    if (selected) {
                      _selectedFaaCertificates.add(option);
                    } else {
                      _selectedFaaCertificates.remove(option);
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              _buildHoursRequirementSection(
                title: 'Flight Hours (optional)',
                options: _availableEmployerFlightHours,
                selectedHours: _selectedFlightHours,
                preferredHours: _preferredFlightHours,
              ),
              const SizedBox(height: 12),
              _buildHoursRequirementSection(
                title: 'Instructor Hours (optional)',
                options: _availableInstructorHours,
                selectedHours: _selectedInstructorHours,
                preferredHours: _preferredInstructorHours,
              ),
              const SizedBox(height: 12),
              _buildHoursRequirementSection(
                title: 'Specialty Hours (optional)',
                options: _availableSpecialtyExperience,
                selectedHours: _selectedSpecialtyHours,
                preferredHours: _preferredSpecialtyHours,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _aircraftController,
                decoration: const InputDecoration(
                  labelText: 'Aircraft Types (optional)',
                  hintText: 'Cessna 172, Boeing 737',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _typeRatingsController,
                decoration: const InputDecoration(
                  labelText: 'Type Ratings (optional)',
                  hintText: 'Boeing 737, Embraer E-175',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (_editingListing == null)
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitExternalListing,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.post_add),
                    label: const Text('Post External Listing'),
                  ),
                ),
              if (_editingListing == null) const SizedBox(height: 16),
              const SizedBox(height: 16),
            ],
          ),
        ),
        if (_editingListing != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 44,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submitExternalListing,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _isSubmitting ? 'Saving...' : 'Save External Listing',
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCheckboxCard({
    required String title,
    required List<String> options,
    required bool Function(String option) isSelected,
    required void Function(String option, bool selected) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...options.map(
            (option) => CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(option),
              value: isSelected(option),
              onChanged: (selected) => onChanged(option, selected == true),
            ),
          ),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...options.map((option) {
            final isChecked = selectedHours.containsKey(option);
            final isPreferred = preferredHours.contains(option);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(option),
                  value: isChecked,
                  onChanged: (selected) {
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
                if (isChecked)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 12,
                      right: 12,
                      bottom: 8,
                    ),
                    child: Column(
                      children: [
                        TextFormField(
                          key: ValueKey('$title-$option'),
                          keyboardType: TextInputType.number,
                          initialValue: (selectedHours[option] ?? 0) > 0
                              ? (selectedHours[option] ?? 0).toString()
                              : '',
                          decoration: InputDecoration(
                            labelText: 'Hours for $option',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (value) {
                            final parsed = int.tryParse(value.trim()) ?? 0;
                            selectedHours[option] = parsed;
                          },
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('Mark as preferred (optional)'),
                          value: isPreferred,
                          onChanged: (preferred) {
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

  Widget _buildExternalListingsView() {
    if (_externalListingsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_externalListings.isEmpty) {
      return const Center(
        child: Text(
          'No external listings found.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadExternalListings,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _externalListings.length,
        itemBuilder: (context, index) {
          final listing = _externalListings[index];
          final createdLabel = listing.createdAt
              ?.toLocal()
              .toString()
              .substring(0, 19);

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showExternalListingDetails(listing),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            listing.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (!listing.isActive)
                          Chip(
                            label: const Text('Archived'),
                            backgroundColor: Colors.grey.shade200,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${listing.company} • ${listing.location}'),
                    const SizedBox(height: 4),
                    Text('Type: ${listing.type}'),
                    if (listing.externalApplyUrl?.trim().isNotEmpty ??
                        false) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Apply URL: ${listing.externalApplyUrl}',
                        style: TextStyle(color: Colors.blueGrey.shade700),
                      ),
                    ],
                    if (createdLabel != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Created $createdLabel',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.open_in_full,
                          size: 14,
                          color: Colors.blueGrey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'View Full Listing',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _beginEditExternalListing(listing),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit'),
                        ),
                        if (listing.isActive)
                          OutlinedButton.icon(
                            onPressed: _archivingListingIds.contains(listing.id)
                                ? null
                                : () => _archiveExternalListing(listing),
                            icon: _archivingListingIds.contains(listing.id)
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.archive_outlined),
                            label: Text(
                              _archivingListingIds.contains(listing.id)
                                  ? 'Archiving...'
                                  : 'Archive',
                            ),
                          ),
                        OutlinedButton.icon(
                          onPressed: _deletingListingIds.contains(listing.id)
                              ? null
                              : () => _deleteExternalListing(listing),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                          ),
                          icon: _deletingListingIds.contains(listing.id)
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_outline),
                          label: Text(
                            _deletingListingIds.contains(listing.id)
                                ? 'Deleting...'
                                : 'Delete',
                          ),
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
}

// ──────────────────────────────────────────────────────────────────────────────
// Dashboard Tab
// ──────────────────────────────────────────────────────────────────────────────

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.statsLoading,
    required this.totalJobSeekers,
    required this.totalEmployers,
    required this.activeJobListings,
    required this.totalApplications,
    required this.recentLogs,
    required this.onRefresh,
  });

  final bool statsLoading;
  final int totalJobSeekers;
  final int totalEmployers;
  final int activeJobListings;
  final int totalApplications;
  final List<AdminActionLog> recentLogs;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Admin banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              border: Border.all(color: Colors.red.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.admin_panel_settings, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Text(
                  'Admin Mode — changes are logged',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Quick stats
          Text('Quick Stats', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (statsLoading)
            const Center(child: CircularProgressIndicator())
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 160,
                  child: _StatCard(
                    label: 'Job Seekers',
                    value: '$totalJobSeekers',
                    icon: Icons.person,
                    color: Colors.blue,
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: _StatCard(
                    label: 'Employers',
                    value: '$totalEmployers',
                    icon: Icons.business,
                    color: Colors.green,
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: _StatCard(
                    label: 'Active Job Listings',
                    value: '$activeJobListings',
                    icon: Icons.work_outline,
                    color: Colors.teal,
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: _StatCard(
                    label: 'Applications',
                    value: '$totalApplications',
                    icon: Icons.assignment,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          // Recent admin actions
          Text(
            'Recent Admin Actions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (recentLogs.isEmpty)
            const Text(
              'No admin actions recorded yet.',
              style: TextStyle(color: Colors.grey),
            )
          else
            ...recentLogs.map((log) => _LogSummaryTile(log: log, onTap: null)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _ModerationTab extends StatefulWidget {
  const _ModerationTab({
    required this.adminRepository,
    required this.onDataChanged,
  });

  final AdminRepository adminRepository;
  final Future<void> Function() onDataChanged;

  @override
  State<_ModerationTab> createState() => _ModerationTabState();
}

class _ModerationTabState extends State<_ModerationTab> {
  bool _loading = false;
  List<JobListingReport> _reports = const [];
  List<EmployerModeration> _employers = const [];
  List<JobSeekerModeration> _jobSeekers = const [];
  String _reportStatusFilter = JobListingReport.statusOpen;

  static const List<(String, String)> _reportStatusOptions = [
    (JobListingReport.statusOpen, 'Open'),
    (JobListingReport.statusDeleted, 'Deleted'),
    (JobListingReport.statusDismissed, 'Dismissed'),
    ('all', 'All'),
  ];

  List<JobListingReport> get _filteredReports {
    if (_reportStatusFilter == 'all') {
      return _reports;
    }
    return _reports
        .where((report) => report.status == _reportStatusFilter)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final reports = await widget.adminRepository.getJobListingReports();
      final employers = await widget.adminRepository
          .getEmployerModerationSummaries();
      final jobSeekers = await widget.adminRepository
          .getJobSeekerModerationSummaries();

      if (!mounted) {
        return;
      }

      employers.sort((a, b) {
        final bannedCompare = (b.isBanned ? 1 : 0).compareTo(
          a.isBanned ? 1 : 0,
        );
        if (bannedCompare != 0) {
          return bannedCompare;
        }
        final deletedCompare = b.adminDeletedJobCount.compareTo(
          a.adminDeletedJobCount,
        );
        if (deletedCompare != 0) {
          return deletedCompare;
        }
        return a.companyName.toLowerCase().compareTo(
          b.companyName.toLowerCase(),
        );
      });

      jobSeekers.sort((a, b) {
        final bannedCompare = (b.isBanned ? 1 : 0).compareTo(
          a.isBanned ? 1 : 0,
        );
        if (bannedCompare != 0) {
          return bannedCompare;
        }
        final deletedCompare = b.adminDeletedApplicationCount.compareTo(
          a.adminDeletedApplicationCount,
        );
        if (deletedCompare != 0) {
          return deletedCompare;
        }
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });

      setState(() {
        _reports = reports;
        _employers = employers;
        _jobSeekers = jobSeekers;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load moderation data.')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<String?> _promptForReason({
    required String title,
    required String hintText,
    bool allowBlank = false,
  }) async {
    final controller = TextEditingController();
    String? errorText;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: hintText,
              border: const OutlineInputBorder(),
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = controller.text.trim();
                if (!allowBlank && value.isEmpty) {
                  setDialogState(() {
                    errorText = 'Reason is required.';
                  });
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  String _actionErrorMessage(Object error) {
    final raw = error.toString();
    const statePrefix = 'Bad state: ';
    if (raw.startsWith(statePrefix)) {
      return raw.substring(statePrefix.length);
    }

    if (raw.contains('employer_owner_is_admin') &&
        raw.contains('does not exist')) {
      return 'Admin protection functions are missing in the database. Run Supabase migrations and try again.';
    }

    if (raw.contains('user_is_admin') && raw.contains('does not exist')) {
      return 'Admin protection functions are missing in the database. Run Supabase migrations and try again.';
    }

    if (raw.toLowerCase().contains('violates foreign key constraint')) {
      return 'This profile cannot be deleted because related records still reference it.';
    }

    if (raw.toLowerCase().contains('permission denied')) {
      return 'This action is not allowed by current database permissions.';
    }

    return 'Action failed. Please try again.';
  }

  Future<void> _deleteReportedListing(JobListingReport report) async {
    final reason = await _promptForReason(
      title: 'Delete reported listing',
      hintText: 'Explain why this listing is being removed.',
    );
    if (reason == null) {
      return;
    }

    final confirmed = await _confirmAction(
      title: 'Confirm delete listing',
      message:
          'Delete "${report.jobTitle}" from ${report.company}? This will archive the listing and close open reports.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) {
      return;
    }

    await widget.adminRepository.deleteJobListing(report.jobListingId, reason);
    await widget.adminRepository.resolveJobListingReport(
      report.id,
      status: JobListingReport.statusDeleted,
      adminNotes: reason,
    );
    await _loadData();
    await widget.onDataChanged();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted reported listing "${report.jobTitle}".')),
    );
  }

  Future<void> _dismissReport(JobListingReport report) async {
    final note = await _promptForReason(
      title: 'Dismiss report',
      hintText: 'Optional note for audit history.',
      allowBlank: true,
    );
    if (note == null) {
      return;
    }

    await widget.adminRepository.resolveJobListingReport(
      report.id,
      status: JobListingReport.statusDismissed,
      adminNotes: note,
    );
    await _loadData();
  }

  Future<void> _toggleEmployerBan(EmployerModeration employer) async {
    final nextIsBanned = !employer.isBanned;
    final reason = nextIsBanned
        ? await _promptForReason(
            title: 'Ban employer',
            hintText: 'Explain why this employer is being banned.',
          )
        : '';
    if (nextIsBanned && reason == null) {
      return;
    }

    if (nextIsBanned) {
      final targetName = employer.companyName.trim().isEmpty
          ? employer.employerId
          : employer.companyName;
      final confirmed = await _confirmAction(
        title: 'Confirm employer ban',
        message: 'Ban $targetName from posting and managing listings?',
        confirmLabel: 'Ban',
      );
      if (!confirmed) {
        return;
      }
    }

    try {
      await widget.adminRepository.setEmployerBan(
        employer.employerId,
        isBanned: nextIsBanned,
        reason: nextIsBanned ? reason : '',
        companyName: employer.companyName,
      );
      await _loadData();
      await widget.onDataChanged();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_actionErrorMessage(error))));
    }
  }

  Future<void> _toggleJobSeekerBan(JobSeekerModeration jobSeeker) async {
    final nextIsBanned = !jobSeeker.isBanned;
    final reason = nextIsBanned
        ? await _promptForReason(
            title: 'Ban job seeker',
            hintText: 'Explain why this job seeker is being banned.',
          )
        : '';
    if (nextIsBanned && reason == null) {
      return;
    }

    if (nextIsBanned) {
      final targetName = jobSeeker.displayName.trim().isNotEmpty
          ? jobSeeker.displayName
          : jobSeeker.email.trim().isNotEmpty
          ? jobSeeker.email
          : jobSeeker.userId;
      final confirmed = await _confirmAction(
        title: 'Confirm job seeker ban',
        message: 'Ban $targetName from applying and managing profile data?',
        confirmLabel: 'Ban',
      );
      if (!confirmed) {
        return;
      }
    }

    try {
      await widget.adminRepository.setJobSeekerBan(
        jobSeeker.userId,
        isBanned: nextIsBanned,
        reason: nextIsBanned ? reason : '',
        displayName: jobSeeker.displayName,
        email: jobSeeker.email,
      );
      await _loadData();
      await widget.onDataChanged();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_actionErrorMessage(error))));
    }
  }

  Future<void> _showEmployerProfileDialog(EmployerModeration employer) async {
    final profile = await widget.adminRepository.getEmployerProfile(
      employer.employerId,
    );
    if (!mounted) {
      return;
    }
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Employer profile not found.')),
      );
      return;
    }

    final targetName = profile.companyName.trim().isNotEmpty
        ? profile.companyName
        : profile.id;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Employer Profile • $targetName'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailRow('ID', profile.id),
              _DetailRow('Company', profile.companyName),
              _DetailRow('Website', profile.website),
              _DetailRow('Contact Name', profile.contactName),
              _DetailRow('Contact Email', profile.contactEmail),
              _DetailRow('Contact Phone', profile.contactPhone),
              _DetailRow(
                'HQ',
                [
                  profile.headquartersAddressLine1,
                  profile.headquartersAddressLine2,
                  profile.headquartersCity,
                  profile.headquartersState,
                  profile.headquartersPostalCode,
                  profile.headquartersCountry,
                ].where((part) => part.trim().isNotEmpty).join(', '),
              ),
              if (profile.companyDescription.trim().isNotEmpty)
                _DetailRow('Description', profile.companyDescription),
              if (profile.companyBenefits.isNotEmpty)
                _DetailRow('Benefits', profile.companyBenefits.join(', ')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _deleteEmployerProfile(
                employerId: employer.employerId,
                companyName: targetName,
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Profile'),
          ),
        ],
      ),
    );
  }

  Future<void> _showJobSeekerProfileDialog(
    JobSeekerModeration jobSeeker,
  ) async {
    final profile = await widget.adminRepository.getJobSeekerProfile(
      jobSeeker.userId,
    );
    if (!mounted) {
      return;
    }
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job seeker profile not found.')),
      );
      return;
    }

    final targetName = profile.fullName.trim().isNotEmpty
        ? profile.fullName
        : profile.email.trim().isNotEmpty
        ? profile.email
        : jobSeeker.userId;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Job Seeker Profile • $targetName'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailRow('User ID', jobSeeker.userId),
              _DetailRow('Name', profile.fullName),
              _DetailRow('Email', profile.email),
              _DetailRow('Phone', profile.phone),
              _DetailRow(
                'Location',
                [
                  profile.city,
                  profile.stateOrProvince,
                  profile.country,
                ].where((part) => part.trim().isNotEmpty).join(', '),
              ),
              _DetailRow('Total Flight Hours', '${profile.totalFlightHours}'),
              if (profile.faaCertificates.isNotEmpty)
                _DetailRow(
                  'FAA Certificates',
                  profile.faaCertificates.join(', '),
                ),
              if (profile.typeRatings.isNotEmpty)
                _DetailRow('Type Ratings', profile.typeRatings.join(', ')),
              if (profile.aircraftFlown.isNotEmpty)
                _DetailRow('Aircraft Flown', profile.aircraftFlown.join(', ')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _deleteJobSeekerProfile(
                userId: jobSeeker.userId,
                displayName: targetName,
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Profile'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEmployerProfile({
    required String employerId,
    required String companyName,
  }) async {
    final reason = await _promptForReason(
      title: 'Delete employer profile',
      hintText: 'Explain why this employer profile is being removed.',
    );
    if (reason == null) {
      return;
    }

    final confirmed = await _confirmAction(
      title: 'Confirm employer delete',
      message:
          'Delete employer profile for $companyName? This permanently removes the profile and related employer data.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) {
      return;
    }

    try {
      await widget.adminRepository.deleteEmployerProfile(employerId, reason);
      await _loadData();
      await widget.onDataChanged();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted employer profile for $companyName.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_actionErrorMessage(error))));
    }
  }

  Future<void> _deleteJobSeekerProfile({
    required String userId,
    required String displayName,
  }) async {
    final reason = await _promptForReason(
      title: 'Delete job seeker profile',
      hintText: 'Explain why this job seeker profile is being removed.',
    );
    if (reason == null) {
      return;
    }

    final confirmed = await _confirmAction(
      title: 'Confirm job seeker delete',
      message:
          'Delete profile for $displayName? This permanently removes the profile and its linked data.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) {
      return;
    }

    try {
      await widget.adminRepository.deleteJobSeekerProfile(userId, reason);
      await _loadData();
      await widget.onDataChanged();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted job seeker profile for $displayName.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_actionErrorMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final bannedEmployerCount = _employers
        .where((item) => item.isBanned)
        .length;
    final bannedJobSeekerCount = _jobSeekers
        .where((item) => item.isBanned)
        .length;
    final openReportCount = _reports
        .where((item) => item.status == JobListingReport.statusOpen)
        .length;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 180,
                child: _StatCard(
                  label: 'Open Reports',
                  value: '$openReportCount',
                  icon: Icons.flag_outlined,
                  color: Colors.red,
                ),
              ),
              SizedBox(
                width: 180,
                child: _StatCard(
                  label: 'Banned Employers',
                  value: '$bannedEmployerCount',
                  icon: Icons.business_center,
                  color: Colors.deepOrange,
                ),
              ),
              SizedBox(
                width: 180,
                child: _StatCard(
                  label: 'Banned Job Seekers',
                  value: '$bannedJobSeekerCount',
                  icon: Icons.person_off_outlined,
                  color: Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Reported Listings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'View:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              ..._reportStatusOptions.map((option) {
                final key = option.$1;
                final label = option.$2;
                return ChoiceChip(
                  label: Text(label),
                  selected: _reportStatusFilter == key,
                  onSelected: (_) {
                    setState(() {
                      _reportStatusFilter = key;
                    });
                  },
                );
              }),
            ],
          ),
          const SizedBox(height: 8),
          if (_filteredReports.isEmpty)
            const Text(
              'No reports match the selected filter.',
              style: TextStyle(color: Colors.grey),
            )
          else
            ..._filteredReports.map((report) {
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.jobTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('${report.company} • ${report.location}'),
                      const SizedBox(height: 8),
                      Text('Reason: ${report.reason}'),
                      const SizedBox(height: 4),
                      Text('Status: ${report.status}'),
                      if (report.details.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(report.details.trim()),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        'Reported ${report.createdAt.toLocal().toString().substring(0, 19)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (report.status == JobListingReport.statusOpen) ...[
                            ElevatedButton.icon(
                              onPressed: () => _deleteReportedListing(report),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete Listing'),
                            ),
                            if ((report.employerId ?? '').isNotEmpty)
                              OutlinedButton.icon(
                                onPressed: () {
                                  final match = _employers.where(
                                    (item) =>
                                        item.employerId == report.employerId,
                                  );
                                  final employer = match.isEmpty
                                      ? EmployerModeration(
                                          employerId: report.employerId!,
                                          companyName: report.company,
                                        )
                                      : match.first;
                                  _toggleEmployerBan(employer);
                                },
                                icon: const Icon(Icons.gavel_outlined),
                                label: const Text('Ban Employer'),
                              ),
                            OutlinedButton.icon(
                              onPressed: () => _dismissReport(report),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Dismiss'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 24),
          Text(
            'Employer Moderation',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ..._employers.map((employer) {
            final summary =
                '${employer.adminDeletedJobCount} admin-deleted listing${employer.adminDeletedJobCount == 1 ? '' : 's'}';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                employer.isBanned ? Icons.block : Icons.business_outlined,
                color: employer.isBanned ? Colors.red : null,
              ),
              title: Text(
                employer.companyName.trim().isEmpty
                    ? employer.employerId
                    : employer.companyName,
              ),
              subtitle: Text(
                employer.isBanned && employer.banReason.trim().isNotEmpty
                    ? '$summary • Banned: ${employer.banReason}'
                    : summary,
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => _showEmployerProfileDialog(employer),
                    child: const Text('View Profile'),
                  ),
                  TextButton(
                    onPressed: () => _toggleEmployerBan(employer),
                    child: Text(employer.isBanned ? 'Unban' : 'Ban'),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 24),
          Text(
            'Job Seeker Moderation',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ..._jobSeekers.map((jobSeeker) {
            final displayName = jobSeeker.displayName.trim().isNotEmpty
                ? jobSeeker.displayName
                : jobSeeker.email.trim().isNotEmpty
                ? jobSeeker.email
                : jobSeeker.userId;
            final summary =
                '${jobSeeker.adminDeletedApplicationCount} admin-deleted application${jobSeeker.adminDeletedApplicationCount == 1 ? '' : 's'}';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                jobSeeker.isBanned
                    ? Icons.person_off_outlined
                    : Icons.person_outline,
                color: jobSeeker.isBanned ? Colors.red : null,
              ),
              title: Text(displayName),
              subtitle: Text(
                jobSeeker.isBanned && jobSeeker.banReason.trim().isNotEmpty
                    ? '$summary • Banned: ${jobSeeker.banReason}'
                    : summary,
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => _showJobSeekerProfileDialog(jobSeeker),
                    child: const Text('View Profile'),
                  ),
                  TextButton(
                    onPressed: () => _toggleJobSeekerBan(jobSeeker),
                    child: Text(jobSeeker.isBanned ? 'Unban' : 'Ban'),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Users & Data Tab
// ──────────────────────────────────────────────────────────────────────────────

class _UsersDataTab extends StatefulWidget {
  const _UsersDataTab({
    required this.adminRepository,
    required this.appRepository,
  });

  final AdminRepository adminRepository;
  final AppRepository appRepository;

  @override
  State<_UsersDataTab> createState() => _UsersDataTabState();
}

class _UsersDataTabState extends State<_UsersDataTab> {
  bool _loading = false;
  List<JobListing> _jobListings = [];
  List<Application> _applications = [];
  String _jobListingSort = 'recent';
  String _applicationSort = 'recent';

  static const List<(String, String)> _jobListingSortOptions = [
    ('recent', 'Most Recent'),
    ('count', 'Most Listings'),
    ('name', 'Employer Name'),
  ];

  static const List<(String, String)> _applicationSortOptions = [
    ('recent', 'Most Recent'),
    ('count', 'Most Applications'),
    ('name', 'Job Seeker Name'),
  ];

  String _employerGroupLabel(JobListing listing) {
    final company = listing.company.trim();
    return company.isNotEmpty ? company : 'Unknown Employer';
  }

  String _jobSeekerGroupLabel(Application application) {
    final applicantName = application.applicantName.trim();
    if (applicantName.isNotEmpty) {
      return applicantName;
    }

    final applicantEmail = application.applicantEmail.trim();
    if (applicantEmail.isNotEmpty) {
      return applicantEmail;
    }

    final seekerId = application.jobSeekerId.trim();
    return seekerId.isNotEmpty ? seekerId : 'Unknown Job Seeker';
  }

  DateTime _jobListingRecency(JobListing listing) {
    return listing.updatedAt ??
        listing.createdAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime _applicationRecency(Application application) {
    return application.updatedAt.isAfter(application.appliedAt)
        ? application.updatedAt
        : application.appliedAt;
  }

  String _formatGroupRecency(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = (local.hour % 12 == 0 ? 12 : local.hour % 12)
        .toString()
        .padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final meridiem = local.hour >= 12 ? 'PM' : 'AM';
    return '$month/$day/$year $hour:$minute $meridiem';
  }

  Widget _buildGroupedSection<T>({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<T> items,
    required String emptyText,
    required String Function(T item) groupLabel,
    required String Function(List<T> items) groupSummary,
    required DateTime Function(T item) itemRecency,
    required String selectedSort,
    required List<(String, String)> sortOptions,
    required ValueChanged<String?> onSortChanged,
    required Widget Function(T item) itemBuilder,
  }) {
    final groupedItems = <String, List<T>>{};
    for (final item in items) {
      groupedItems.putIfAbsent(groupLabel(item), () => []).add(item);
    }

    final groupEntries =
        groupedItems.entries.map((entry) {
          final sortedItems = [...entry.value]
            ..sort((a, b) => itemRecency(b).compareTo(itemRecency(a)));
          return MapEntry(entry.key, sortedItems);
        }).toList()..sort((a, b) {
          switch (selectedSort) {
            case 'count':
              final countCompare = b.value.length.compareTo(a.value.length);
              if (countCompare != 0) {
                return countCompare;
              }
              break;
            case 'name':
              return a.key.toLowerCase().compareTo(b.key.toLowerCase());
            case 'recent':
            default:
              final recentCompare = itemRecency(
                b.value.first,
              ).compareTo(itemRecency(a.value.first));
              if (recentCompare != 0) {
                return recentCompare;
              }
              break;
          }
          return a.key.toLowerCase().compareTo(b.key.toLowerCase());
        });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 700;
            final sortDropdown = DropdownButtonFormField<String>(
              initialValue: selectedSort,
              isDense: true,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Sort',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
              items: sortOptions
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option.$1,
                      child: Text(
                        option.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              selectedItemBuilder: (context) {
                return sortOptions
                    .map(
                      (option) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          option.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList();
              },
              onChanged: onSortChanged,
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 20, color: Colors.blueGrey.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: sortDropdown),
                ],
              );
            }

            return Row(
              children: [
                Icon(icon, size: 20, color: Colors.blueGrey.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(width: 190, child: sortDropdown),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text(emptyText, style: const TextStyle(color: Colors.grey))
        else
          ...groupEntries.map((entry) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
                color: Colors.white,
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                title: Text(
                  '${entry.key} (${entry.value.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      groupSummary(entry.value),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Last updated ${_formatGroupRecency(itemRecency(entry.value.first))}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                children: entry.value.map(itemBuilder).toList(),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildAdminJobListingTile(JobListing listing) {
    final isVeryNarrow = MediaQuery.sizeOf(context).width < 430;
    final subtitleSegments = <String>[listing.location, listing.type];
    if (!listing.isActive && isVeryNarrow) {
      subtitleSegments.add('Archived');
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 30,
      horizontalTitleGap: 8,
      leading: const Icon(Icons.work_outline),
      title: Text(listing.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitleSegments.join(' • '),
        maxLines: isVeryNarrow ? 2 : 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: !listing.isActive && !isVeryNarrow
          ? Chip(
              label: const Text('Archived'),
              backgroundColor: Colors.grey.shade200,
            )
          : null,
    );
  }

  Widget _buildAdminApplicationTile(Application application) {
    final isVeryNarrow = MediaQuery.sizeOf(context).width < 430;
    final locationParts = [
      application.applicantCity.trim(),
      application.applicantStateOrProvince.trim(),
      application.applicantCountry.trim(),
    ].where((part) => part.isNotEmpty).toList();
    final subtitleParts = <String>[
      'Status: ${application.status}',
      if (locationParts.isNotEmpty) locationParts.join(', '),
      if (isVeryNarrow)
        application.isArchived
            ? 'Archived'
            : 'Match: ${application.matchPercentage}%',
    ];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 30,
      horizontalTitleGap: 8,
      leading: const Icon(Icons.assignment_ind_outlined),
      title: Text(
        application.applicantEmail.trim().isNotEmpty
            ? application.applicantEmail
            : application.jobId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitleParts.join(' • '),
        maxLines: isVeryNarrow ? 2 : 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isVeryNarrow
          ? null
          : application.isArchived
          ? const Icon(Icons.archive, color: Colors.grey)
          : Text(
              '${application.matchPercentage}%',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final listings = await widget.adminRepository.getAllJobListings();
      final apps = await widget.adminRepository.getAllApplications();
      final activeListings = listings
          .where((listing) => listing.isActive)
          .toList();
      if (!mounted) {
        return;
      }
      setState(() {
        _jobListings = activeListings;
        _applications = apps;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not load data.')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildGroupedSection<JobListing>(
            context: context,
            title: 'Job Listings (${_jobListings.length})',
            icon: Icons.business_center_outlined,
            items: _jobListings,
            emptyText: 'No job listings found.',
            groupLabel: _employerGroupLabel,
            groupSummary: (items) {
              final activeCount = items.where((item) => item.isActive).length;
              final archivedCount = items.length - activeCount;
              if (archivedCount <= 0) {
                return '$activeCount active listing${activeCount == 1 ? '' : 's'}';
              }
              return '$activeCount active • $archivedCount archived';
            },
            itemRecency: _jobListingRecency,
            selectedSort: _jobListingSort,
            sortOptions: _jobListingSortOptions,
            onSortChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _jobListingSort = value;
              });
            },
            itemBuilder: _buildAdminJobListingTile,
          ),
          const SizedBox(height: 24),
          _buildGroupedSection<Application>(
            context: context,
            title: 'Applications (${_applications.length})',
            icon: Icons.groups_outlined,
            items: _applications,
            emptyText: 'No applications found.',
            groupLabel: _jobSeekerGroupLabel,
            groupSummary: (items) {
              final activeCount = items
                  .where((item) => !item.isArchived)
                  .length;
              final archivedCount = items.length - activeCount;
              final highestMatch = items.isEmpty
                  ? 0
                  : items
                        .map((item) => item.matchPercentage)
                        .reduce((a, b) => a > b ? a : b);
              if (archivedCount <= 0) {
                return '$activeCount active • best match $highestMatch%';
              }
              return '$activeCount active • $archivedCount archived • best match $highestMatch%';
            },
            itemRecency: _applicationRecency,
            selectedSort: _applicationSort,
            sortOptions: _applicationSortOptions,
            onSortChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _applicationSort = value;
              });
            },
            itemBuilder: _buildAdminApplicationTile,
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Audit Logs Tab
// ──────────────────────────────────────────────────────────────────────────────

class _AuditLogsTab extends StatelessWidget {
  const _AuditLogsTab({
    required this.logs,
    required this.loading,
    required this.filterAction,
    required this.filterResource,
    required this.onFilterAction,
    required this.onFilterResource,
    required this.onRefresh,
  });

  final List<AdminActionLog> logs;
  final bool loading;
  final String? filterAction;
  final String? filterResource;
  final ValueChanged<String?> onFilterAction;
  final ValueChanged<String?> onFilterResource;
  final VoidCallback onRefresh;

  static const _actionOptions = [
    null,
    AdminActionLog.actionCreate,
    AdminActionLog.actionUpdate,
    AdminActionLog.actionDelete,
    AdminActionLog.actionView,
  ];

  static const _resourceOptions = [
    null,
    AdminActionLog.resourceApplication,
    AdminActionLog.resourceJobListing,
    AdminActionLog.resourceJobSeekerProfile,
    AdminActionLog.resourceEmployerProfile,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter row
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: filterAction,
                  decoration: const InputDecoration(
                    labelText: 'Action',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    isDense: true,
                  ),
                  items: _actionOptions
                      .map(
                        (a) => DropdownMenuItem<String?>(
                          value: a,
                          child: Text(a ?? 'All'),
                        ),
                      )
                      .toList(),
                  onChanged: onFilterAction,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: filterResource,
                  decoration: const InputDecoration(
                    labelText: 'Resource',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    isDense: true,
                  ),
                  items: _resourceOptions
                      .map(
                        (r) => DropdownMenuItem<String?>(
                          value: r,
                          child: Text(r ?? 'All'),
                        ),
                      )
                      .toList(),
                  onChanged: onFilterResource,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: onRefresh,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (logs.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'No audit log entries.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: logs.length,
              separatorBuilder: (_, index) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final log = logs[i];
                return _LogSummaryTile(
                  log: log,
                  onTap: () => _showLogDetail(context, log),
                );
              },
            ),
          ),
      ],
    );
  }

  void _showLogDetail(BuildContext context, AdminActionLog log) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${log.actionType.toUpperCase()} — ${log.resourceType}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailRow('Resource ID', log.resourceId),
              _DetailRow('Admin', log.adminUserId),
              _DetailRow(
                'Timestamp',
                log.timestamp.toLocal().toString().substring(0, 19),
              ),
              if (log.reason != null) _DetailRow('Reason', log.reason!),
              if (log.changesBefore != null) ...[
                const SizedBox(height: 8),
                const Text(
                  'Before:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  log.changesBefore.toString(),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ],
              if (log.changesAfter != null) ...[
                const SizedBox(height: 8),
                const Text(
                  'After:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  log.changesAfter.toString(),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _LogSummaryTile extends StatelessWidget {
  const _LogSummaryTile({required this.log, this.onTap});

  final AdminActionLog log;
  final VoidCallback? onTap;

  Color _actionColor(String action) {
    switch (action) {
      case AdminActionLog.actionDelete:
        return Colors.red;
      case AdminActionLog.actionUpdate:
        return Colors.orange;
      case AdminActionLog.actionCreate:
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = log.timestamp.toLocal();
    final dateStr =
        '${ts.month}/${ts.day} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

    return ListTile(
      dense: true,
      onTap: onTap,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: _actionColor(log.actionType),
        child: Text(
          log.actionType[0].toUpperCase(),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      title: Text('${log.resourceType} — ${log.resourceId}'),
      subtitle: Text(log.reason ?? 'No reason recorded'),
      trailing: Text(dateStr, style: const TextStyle(fontSize: 11)),
    );
  }
}
