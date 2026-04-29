alter table if exists public.job_seeker_profiles
  add column if not exists notify_on_application_status_change boolean not null default true;
