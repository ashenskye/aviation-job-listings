alter table if exists public.employer_profiles
  add column if not exists notify_on_new_non_rejected_application boolean not null default true,
  add column if not exists notify_on_application_status_changes boolean not null default false,
  add column if not exists notify_daily_digest boolean not null default false;
