alter table if exists public.job_applications
  drop constraint if exists job_applications_status_check;

alter table if exists public.job_applications
  add constraint job_applications_status_check
  check (
    status in (
      'applied',
      'viewed',
      'reviewed',
      'future_consideration',
      'rejected',
      'interested'
    )
  );
