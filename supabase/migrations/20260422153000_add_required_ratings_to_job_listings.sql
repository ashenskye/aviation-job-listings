alter table if exists public.job_listings
  add column if not exists required_ratings text[] not null default '{}';

create index if not exists idx_job_listings_required_ratings_gin
  on public.job_listings using gin(required_ratings);
