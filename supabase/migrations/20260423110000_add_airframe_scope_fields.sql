alter table if exists public.job_seeker_profiles
  add column if not exists airframe_scope text not null default 'Fixed Wing';

alter table if exists public.job_listings
  add column if not exists airframe_scope text not null default 'Fixed Wing';
