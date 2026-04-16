alter table if exists public.employer_profiles
add column if not exists company_logo_url text;
