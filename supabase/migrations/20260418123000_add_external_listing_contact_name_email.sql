alter table public.job_listings
  add column if not exists contact_name text,
  add column if not exists contact_email text;