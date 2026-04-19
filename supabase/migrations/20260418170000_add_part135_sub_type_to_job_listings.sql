alter table public.job_listings
  add column if not exists part135_sub_type text null
  check (part135_sub_type in ('ifr', 'vfr'));
