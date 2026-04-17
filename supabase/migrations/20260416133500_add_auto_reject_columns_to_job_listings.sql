-- Persist employer auto-reject configuration on job listings.
alter table if exists public.job_listings
  add column if not exists auto_reject_threshold integer not null default 0;

alter table if exists public.job_listings
  add column if not exists reapply_window_days integer not null default 30;
