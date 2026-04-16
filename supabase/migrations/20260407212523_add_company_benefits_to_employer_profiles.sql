alter table if exists public.employer_profiles
add column if not exists company_benefits text[] not null default '{}';
