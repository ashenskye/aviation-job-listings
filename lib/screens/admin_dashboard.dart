import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_action_log.dart';
import '../models/application.dart';
import '../models/job_listing.dart';
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
    _tabController = TabController(length: 3, vsync: this);
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
            totalApplications: _totalApplications,
            recentLogs: _recentLogs,
            onRefresh: _loadStats,
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

// ──────────────────────────────────────────────────────────────────────────────
// Dashboard Tab
// ──────────────────────────────────────────────────────────────────────────────

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.statsLoading,
    required this.totalJobSeekers,
    required this.totalEmployers,
    required this.totalApplications,
    required this.recentLogs,
    required this.onRefresh,
  });

  final bool statsLoading;
  final int totalJobSeekers;
  final int totalEmployers;
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
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Job Seekers',
                    value: '$totalJobSeekers',
                    icon: Icons.person,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    label: 'Employers',
                    value: '$totalEmployers',
                    icon: Icons.business,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
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
          Text(
            'Job Listings (${_jobListings.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_jobListings.isEmpty)
            const Text(
              'No job listings found.',
              style: TextStyle(color: Colors.grey),
            )
          else
            ..._jobListings.take(20).map((j) {
              return ListTile(
                leading: const Icon(Icons.work_outline),
                title: Text(j.title),
                subtitle: Text(j.company),
                trailing: !j.isActive
                    ? Chip(
                        label: const Text('Archived'),
                        backgroundColor: Colors.grey.shade200,
                      )
                    : null,
              );
            }),
          const SizedBox(height: 24),
          Text(
            'Applications (${_applications.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_applications.isEmpty)
            const Text(
              'No applications found.',
              style: TextStyle(color: Colors.grey),
            )
          else
            ..._applications.take(20).map((a) {
              return ListTile(
                leading: const Icon(Icons.assignment_ind_outlined),
                title: Text(a.applicantName),
                subtitle: Text('Status: ${a.status}'),
                trailing: a.isArchived
                    ? const Icon(Icons.archive, color: Colors.grey)
                    : null,
              );
            }),
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
