alter table public.job_listings
  add column if not exists is_external boolean not null default false,
  add column if not exists external_apply_url text null;
