alter table if exists public.job_seeker_profiles
  add column if not exists new_job_alert_minimum_match_percent integer not null default 100;

alter table if exists public.job_seeker_profiles
  drop constraint if exists job_seeker_profiles_new_job_alert_minimum_match_percent_check;

alter table if exists public.job_seeker_profiles
  add constraint job_seeker_profiles_new_job_alert_minimum_match_percent_check
  check (new_job_alert_minimum_match_percent >= 0 and new_job_alert_minimum_match_percent <= 100);
