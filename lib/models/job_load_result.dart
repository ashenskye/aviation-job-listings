import 'job_listing.dart';

class JobLoadResult {
  final List<JobListing> jobs;
  final String? warningMessage;

  const JobLoadResult({
    required this.jobs,
    this.warningMessage,
  });
}
