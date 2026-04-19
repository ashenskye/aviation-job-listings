alter table if exists public.job_listings
  add column if not exists company_phone text null,
  add column if not exists company_url text null;
