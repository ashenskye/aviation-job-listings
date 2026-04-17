-- Step 1: Core schema + RLS for Aviation Job Listings
-- Designed to map current Dart models in lib/models/*.dart.
-- IDs are text where the app currently uses string IDs.

-- ============================================================================
-- Extensions
-- ============================================================================
create extension if not exists pgcrypto;

-- ============================================================================
-- Utility: updated_at trigger
-- ============================================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================================
-- Profiles
-- ============================================================================

-- Job seeker profile maps JobSeekerProfile model.
create table if not exists public.job_seeker_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null default '',
  phone text not null default '',
  city text not null default '',
  state_or_province text not null default '',
  country text not null default '',
  faa_certificates text[] not null default '{}',
  type_ratings text[] not null default '{}',
  flight_hours jsonb not null default '{}'::jsonb,
  flight_hours_types text[] not null default '{}',
  specialty_flight_hours text[] not null default '{}',
  specialty_flight_hours_map jsonb not null default '{}'::jsonb,
  aircraft_flown text[] not null default '{}',
  total_flight_hours integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_job_seeker_profiles_updated_at
before update on public.job_seeker_profiles
for each row execute function public.set_updated_at();

-- Employer profile maps EmployerProfile model.
create table if not exists public.employer_profiles (
  id text primary key,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  company_name text not null,
  headquarters_address_line1 text not null default '',
  headquarters_address_line2 text not null default '',
  headquarters_city text not null default '',
  headquarters_state text not null default '',
  headquarters_postal_code text not null default '',
  headquarters_country text not null default '',
  website text not null default '',
  contact_name text not null default '',
  contact_email text not null default '',
  contact_phone text not null default '',
  company_description text not null default '',
  company_benefits text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_employer_profiles_updated_at
before update on public.employer_profiles
for each row execute function public.set_updated_at();

-- Tracks currently selected employer profile per user for multi-employer UX.
create table if not exists public.user_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  selected_employer_profile_id text null references public.employer_profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_user_preferences_updated_at
before update on public.user_preferences
for each row execute function public.set_updated_at();

-- ============================================================================
-- Jobs + User actions
-- ============================================================================

-- Job listing maps JobListing model, including dedicated instructor_hours bucket.
create table if not exists public.job_listings (
  id text primary key,
  employer_id text null references public.employer_profiles(id) on delete set null,
  title text not null,
  company text not null,
  location text not null,
  employment_type text not null,
  crew_role text not null,
  crew_position text null,
  faa_rules text[] not null default '{}',
  description text not null default '',
  faa_certificates text[] not null default '{}',
  type_ratings_required text[] not null default '{}',
  flight_experience text[] not null default '{}',
  flight_hours jsonb not null default '{}'::jsonb,
  preferred_flight_hours text[] not null default '{}',
  instructor_hours jsonb not null default '{}'::jsonb,
  preferred_instructor_hours text[] not null default '{}',
  specialty_experience text[] not null default '{}',
  specialty_hours jsonb not null default '{}'::jsonb,
  preferred_specialty_hours text[] not null default '{}',
  aircraft_flown text[] not null default '{}',
  salary_range text null,
  minimum_hours integer null,
  benefits text[] not null default '{}',
  auto_reject_threshold integer not null default 0,
  reapply_window_days integer not null default 30,
  deadline_date timestamptz null,
  status text not null default 'active' check (status in ('active', 'draft', 'archived', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_job_listings_updated_at
before update on public.job_listings
for each row execute function public.set_updated_at();

-- Saved jobs maps favorite IDs behavior.
create table if not exists public.saved_jobs (
  user_id uuid not null references auth.users(id) on delete cascade,
  job_listing_id text not null references public.job_listings(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, job_listing_id)
);

-- Job applications table - stores full Application model data as JSONB.
create table if not exists public.job_applications (
  id text primary key,
  job_listing_id text not null references public.job_listings(id) on delete cascade,
  employer_id text not null references public.employer_profiles(id) on delete cascade,
  applicant_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'applied' check (status in ('applied', 'reviewed', 'rejected', 'interested')),
  match_percentage integer not null default 0,
  data jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (job_listing_id, applicant_user_id)
);

create trigger trg_job_applications_updated_at
before update on public.job_applications
for each row execute function public.set_updated_at();

-- ============================================================================
-- Indexes
-- ============================================================================

create index if not exists idx_employer_profiles_owner_user_id
  on public.employer_profiles(owner_user_id);

create index if not exists idx_job_listings_employer_id
  on public.job_listings(employer_id);

create index if not exists idx_job_listings_status
  on public.job_listings(status);

create index if not exists idx_job_listings_deadline_date
  on public.job_listings(deadline_date);

create index if not exists idx_job_listings_faa_rules_gin
  on public.job_listings using gin(faa_rules);

create index if not exists idx_job_listings_faa_certificates_gin
  on public.job_listings using gin(faa_certificates);

create index if not exists idx_job_listings_type_ratings_required_gin
  on public.job_listings using gin(type_ratings_required);

create index if not exists idx_job_listings_flight_hours_gin
  on public.job_listings using gin(flight_hours);

create index if not exists idx_job_listings_instructor_hours_gin
  on public.job_listings using gin(instructor_hours);

create index if not exists idx_job_listings_specialty_hours_gin
  on public.job_listings using gin(specialty_hours);

create index if not exists idx_saved_jobs_job_listing_id
  on public.saved_jobs(job_listing_id);

create index if not exists idx_job_applications_job_listing_id
  on public.job_applications(job_listing_id);

create index if not exists idx_job_applications_employer_id
  on public.job_applications(employer_id);

create index if not exists idx_job_applications_applicant_user_id
  on public.job_applications(applicant_user_id);

-- ============================================================================
-- Row Level Security
-- ============================================================================

alter table public.job_seeker_profiles enable row level security;
alter table public.employer_profiles enable row level security;
alter table public.user_preferences enable row level security;
alter table public.job_listings enable row level security;
alter table public.saved_jobs enable row level security;
alter table public.job_applications enable row level security;

-- Job seeker profiles: owner-only CRUD.
drop policy if exists job_seeker_profiles_select_own on public.job_seeker_profiles;
create policy job_seeker_profiles_select_own
  on public.job_seeker_profiles
  for select
  using (auth.uid() = user_id);

drop policy if exists job_seeker_profiles_insert_own on public.job_seeker_profiles;
create policy job_seeker_profiles_insert_own
  on public.job_seeker_profiles
  for insert
  with check (auth.uid() = user_id);

drop policy if exists job_seeker_profiles_update_own on public.job_seeker_profiles;
create policy job_seeker_profiles_update_own
  on public.job_seeker_profiles
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists job_seeker_profiles_delete_own on public.job_seeker_profiles;
create policy job_seeker_profiles_delete_own
  on public.job_seeker_profiles
  for delete
  using (auth.uid() = user_id);

-- Employer profiles: any authenticated user can view, only owner can write.
drop policy if exists employer_profiles_select_authenticated on public.employer_profiles;
create policy employer_profiles_select_authenticated
  on public.employer_profiles
  for select
  using (auth.uid() is not null);

drop policy if exists employer_profiles_insert_own on public.employer_profiles;
create policy employer_profiles_insert_own
  on public.employer_profiles
  for insert
  with check (auth.uid() = owner_user_id);

drop policy if exists employer_profiles_update_own on public.employer_profiles;
create policy employer_profiles_update_own
  on public.employer_profiles
  for update
  using (auth.uid() = owner_user_id)
  with check (auth.uid() = owner_user_id);

drop policy if exists employer_profiles_delete_own on public.employer_profiles;
create policy employer_profiles_delete_own
  on public.employer_profiles
  for delete
  using (auth.uid() = owner_user_id);

-- User preferences: owner-only CRUD; selected employer must belong to owner.
drop policy if exists user_preferences_select_own on public.user_preferences;
create policy user_preferences_select_own
  on public.user_preferences
  for select
  using (auth.uid() = user_id);

drop policy if exists user_preferences_insert_own on public.user_preferences;
create policy user_preferences_insert_own
  on public.user_preferences
  for insert
  with check (
    auth.uid() = user_id
    and (
      selected_employer_profile_id is null
      or exists (
        select 1
        from public.employer_profiles ep
        where ep.id = selected_employer_profile_id
          and ep.owner_user_id = auth.uid()
      )
    )
  );

drop policy if exists user_preferences_update_own on public.user_preferences;
create policy user_preferences_update_own
  on public.user_preferences
  for update
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and (
      selected_employer_profile_id is null
      or exists (
        select 1
        from public.employer_profiles ep
        where ep.id = selected_employer_profile_id
          and ep.owner_user_id = auth.uid()
      )
    )
  );

drop policy if exists user_preferences_delete_own on public.user_preferences;
create policy user_preferences_delete_own
  on public.user_preferences
  for delete
  using (auth.uid() = user_id);

-- Job listings: read by authenticated users, write only by owning employer.
drop policy if exists job_listings_select_authenticated on public.job_listings;
create policy job_listings_select_authenticated
  on public.job_listings
  for select
  using (auth.uid() is not null and status = 'active');

drop policy if exists job_listings_insert_own_employer on public.job_listings;
create policy job_listings_insert_own_employer
  on public.job_listings
  for insert
  with check (
    employer_id is not null
    and exists (
      select 1
      from public.employer_profiles ep
      where ep.id = employer_id
        and ep.owner_user_id = auth.uid()
    )
  );

drop policy if exists job_listings_update_own_employer on public.job_listings;
create policy job_listings_update_own_employer
  on public.job_listings
  for update
  using (
    employer_id is not null
    and exists (
      select 1
      from public.employer_profiles ep
      where ep.id = employer_id
        and ep.owner_user_id = auth.uid()
    )
  )
  with check (
    employer_id is not null
    and exists (
      select 1
      from public.employer_profiles ep
      where ep.id = employer_id
        and ep.owner_user_id = auth.uid()
    )
  );

drop policy if exists job_listings_delete_own_employer on public.job_listings;
create policy job_listings_delete_own_employer
  on public.job_listings
  for delete
  using (
    employer_id is not null
    and exists (
      select 1
      from public.employer_profiles ep
      where ep.id = employer_id
        and ep.owner_user_id = auth.uid()
    )
  );

-- Saved jobs: owner-only CRUD.
drop policy if exists saved_jobs_select_own on public.saved_jobs;
create policy saved_jobs_select_own
  on public.saved_jobs
  for select
  using (auth.uid() = user_id);

drop policy if exists saved_jobs_insert_own on public.saved_jobs;
create policy saved_jobs_insert_own
  on public.saved_jobs
  for insert
  with check (auth.uid() = user_id);

drop policy if exists saved_jobs_delete_own on public.saved_jobs;
create policy saved_jobs_delete_own
  on public.saved_jobs
  for delete
  using (auth.uid() = user_id);

-- Job applications:
-- - Applicant can create/read own applications.
-- - Employer owner can read/update applications for jobs they own.
drop policy if exists job_applications_select_participant on public.job_applications;
create policy job_applications_select_participant
  on public.job_applications
  for select
  using (
    auth.uid() = applicant_user_id
    or exists (
      select 1
      from public.employer_profiles ep
      where ep.id = employer_id
        and ep.owner_user_id = auth.uid()
    )
  );

drop policy if exists job_applications_insert_applicant on public.job_applications;
create policy job_applications_insert_applicant
  on public.job_applications
  for insert
  with check (auth.uid() = applicant_user_id);

drop policy if exists job_applications_update_employer_owner on public.job_applications;
create policy job_applications_update_employer_owner
  on public.job_applications
  for update
  using (
    exists (
      select 1
      from public.employer_profiles ep
      where ep.id = employer_id
        and ep.owner_user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.employer_profiles ep
      where ep.id = employer_id
        and ep.owner_user_id = auth.uid()
    )
  );

-- Optional: applicant may delete/withdraw own application.
drop policy if exists job_applications_delete_applicant on public.job_applications;
create policy job_applications_delete_applicant
  on public.job_applications
  for delete
  using (auth.uid() = applicant_user_id);

-- ============================================================================
-- Admin Access Policies
-- ============================================================================

-- Helper: returns true when the calling user's JWT contains role = 'admin'
-- in either app_metadata or user_metadata.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from auth.users u
    where u.id = auth.uid()
      and (
        coalesce(u.raw_app_meta_data ->> 'role', '') = 'admin'
        or coalesce(u.raw_user_meta_data ->> 'role', '') = 'admin'
      )
  );
$$;

-- job_listings: admins may read/update/delete all listings (including inactive).
drop policy if exists job_listings_admin_all on public.job_listings;
create policy job_listings_admin_all
  on public.job_listings
  for all
  using (public.is_admin())
  with check (public.is_admin());

-- job_applications: admins may read/update/delete all applications.
drop policy if exists job_applications_admin_all on public.job_applications;
create policy job_applications_admin_all
  on public.job_applications
  for all
  using (public.is_admin())
  with check (public.is_admin());

-- job_seeker_profiles: admins may read/update all profiles.
drop policy if exists job_seeker_profiles_admin_all on public.job_seeker_profiles;
create policy job_seeker_profiles_admin_all
  on public.job_seeker_profiles
  for all
  using (public.is_admin())
  with check (public.is_admin());

-- employer_profiles: admins may read/update all employer profiles.
drop policy if exists employer_profiles_admin_all on public.employer_profiles;
create policy employer_profiles_admin_all
  on public.employer_profiles
  for all
  using (public.is_admin())
  with check (public.is_admin());

-- user_preferences: admins may read/update all preferences.
drop policy if exists user_preferences_admin_all on public.user_preferences;
create policy user_preferences_admin_all
  on public.user_preferences
  for all
  using (public.is_admin())
  with check (public.is_admin());

-- saved_jobs: admins may read/update all saved jobs.
drop policy if exists saved_jobs_admin_all on public.saved_jobs;
create policy saved_jobs_admin_all
  on public.saved_jobs
  for all
  using (public.is_admin())
  with check (public.is_admin());

-- ============================================================================
-- Admin Action Logs Table
-- ============================================================================

create table if not exists public.admin_action_logs (
  id                text primary key default gen_random_uuid()::text,
  admin_user_id     uuid not null references auth.users(id),
  action_type       text not null,
  resource_type     text not null,
  resource_id       text not null,
  changes_before    jsonb,
  changes_after     jsonb,
  reason            text,
  timestamp         timestamp with time zone default now(),
  ip_address        text,
  created_at        timestamp with time zone default now(),

  constraint valid_action_type check (
    action_type in ('create', 'update', 'delete', 'view')
  )
);

-- Indexes for efficient queries
create index if not exists idx_admin_action_logs_admin_user_id
  on public.admin_action_logs(admin_user_id);

create index if not exists idx_admin_action_logs_resource
  on public.admin_action_logs(resource_type, resource_id);

create index if not exists idx_admin_action_logs_timestamp
  on public.admin_action_logs(timestamp);

-- RLS: only admins can read logs; inserts allowed for admin users.
alter table public.admin_action_logs enable row level security;

drop policy if exists admin_action_logs_admin_select on public.admin_action_logs;
create policy admin_action_logs_admin_select
  on public.admin_action_logs
  for select
  using (public.is_admin());

drop policy if exists admin_action_logs_admin_insert on public.admin_action_logs;
create policy admin_action_logs_admin_insert
  on public.admin_action_logs
  for insert
  with check (public.is_admin());

drop policy if exists admin_action_logs_admin_all on public.admin_action_logs;
create policy admin_action_logs_admin_all
  on public.admin_action_logs
  for all
  using (public.is_admin())
  with check (public.is_admin());

-- ============================================================================
-- Notes for Step 2 repository integration
-- ============================================================================
-- 1) Keep Dart model key naming in repository mapping layer:
--    - employment_type <-> type
--    - instructor_hours <-> instructorHours
--    - preferred_instructor_hours <-> preferredInstructorHours
-- 2) Existing test IDs like '1' and 'test-all-criteria-job' are supported (text PK).
-- 3) status='active' is required for user-facing reads under current RLS.
