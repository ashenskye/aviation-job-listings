alter table if exists public.job_seeker_profiles
  add column if not exists new_job_alert_enabled boolean not null default false,
  add column if not exists new_job_alert_state_only boolean not null default false,
  add column if not exists new_job_alert_airframe_match boolean not null default true,
  add column if not exists new_job_alert_certificate_match boolean not null default false;
