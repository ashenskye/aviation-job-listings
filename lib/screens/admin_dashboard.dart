import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_action_log.dart';
import '../models/application.dart';
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
  final ValueChanged<AdminInterfaceView> onSwitchView;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

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
    _tabController = TabController(length: 4, vsync: this);
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
            icon: const Icon(Icons.person),
            initialValue: widget.currentView,
            onSelected: widget.onSwitchView,
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
                  label: Text('acct: ${widget.adminRoleLabel}'),
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
          _ModerationTab(adminRepository: widget.adminRepository),
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
  const _ModerationTab({required this.adminRepository});

  final AdminRepository adminRepository;

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

  Future<void> _deleteReportedListing(JobListingReport report) async {
    final reason = await _promptForReason(
      title: 'Delete reported listing',
      hintText: 'Explain why this listing is being removed.',
    );
    if (reason == null) {
      return;
    }

    await widget.adminRepository.deleteJobListing(report.jobListingId, reason);
    await widget.adminRepository.resolveJobListingReport(
      report.id,
      status: JobListingReport.statusDeleted,
      adminNotes: reason,
    );
    await _loadData();

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

    await widget.adminRepository.setEmployerBan(
      employer.employerId,
      isBanned: nextIsBanned,
      reason: nextIsBanned ? reason : '',
      companyName: employer.companyName,
    );
    await _loadData();
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

    await widget.adminRepository.setJobSeekerBan(
      jobSeeker.userId,
      isBanned: nextIsBanned,
      reason: nextIsBanned ? reason : '',
      displayName: jobSeeker.displayName,
      email: jobSeeker.email,
    );
    await _loadData();
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
              trailing: TextButton(
                onPressed: () => _toggleEmployerBan(employer),
                child: Text(employer.isBanned ? 'Unban' : 'Ban'),
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
              trailing: TextButton(
                onPressed: () => _toggleJobSeekerBan(jobSeeker),
                child: Text(jobSeeker.isBanned ? 'Unban' : 'Ban'),
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
            final isNarrow = constraints.maxWidth < 620;
            final sortDropdown = DropdownButtonFormField<String>(
              value: selectedSort,
              isDense: true,
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
                      child: Text(option.$2),
                    ),
                  )
                  .toList(),
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
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(width: 170, child: sortDropdown),
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
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Last updated ${_formatGroupRecency(itemRecency(entry.value.first))}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.work_outline),
      title: Text(listing.title),
      subtitle: Text('${listing.location} • ${listing.type}'),
      trailing: !listing.isActive
          ? Chip(
              label: const Text('Archived'),
              backgroundColor: Colors.grey.shade200,
            )
          : null,
    );
  }

  Widget _buildAdminApplicationTile(Application application) {
    final locationParts = [
      application.applicantCity.trim(),
      application.applicantStateOrProvince.trim(),
      application.applicantCountry.trim(),
    ].where((part) => part.isNotEmpty).toList();
    final subtitleParts = <String>[
      'Status: ${application.status}',
      if (locationParts.isNotEmpty) locationParts.join(', '),
    ];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.assignment_ind_outlined),
      title: Text(
        application.applicantEmail.trim().isNotEmpty
            ? application.applicantEmail
            : application.jobId,
      ),
      subtitle: Text(subtitleParts.join(' • ')),
      trailing: application.isArchived
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
      if (!mounted) {
        return;
      }
      setState(() {
        _jobListings = listings;
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
                  value: filterAction,
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
                  value: filterResource,
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
              separatorBuilder: (_, __) => const Divider(height: 1),
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
