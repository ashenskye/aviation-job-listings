create table if not exists public.job_listing_reports (
  id text primary key default gen_random_uuid()::text,
  job_listing_id text not null,
  reporter_user_id uuid not null references auth.users(id) on delete cascade,
  employer_id text null references public.employer_profiles(id) on delete set null,
  reason text not null,
  details text not null default '',
  status text not null default 'open' check (status in ('open', 'reviewed', 'deleted', 'dismissed')),
  job_title text not null default '',
  company text not null default '',
  location text not null default '',
  admin_notes text null,
  reviewed_at timestamptz null,
  reviewed_by_admin_user_id uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_job_listing_reports_job_listing_id
  on public.job_listing_reports(job_listing_id);

create index if not exists idx_job_listing_reports_status
  on public.job_listing_reports(status);

create table if not exists public.employer_moderation (
  employer_id text primary key references public.employer_profiles(id) on delete cascade,
  company_name text not null default '',
  admin_deleted_job_count integer not null default 0,
  is_banned boolean not null default false,
  banned_at timestamptz null,
  ban_reason text not null default '',
  updated_at timestamptz not null default now()
);

create trigger trg_employer_moderation_updated_at
before update on public.employer_moderation
for each row execute function public.set_updated_at();

create table if not exists public.job_seeker_moderation (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  email text not null default '',
  admin_deleted_application_count integer not null default 0,
  is_banned boolean not null default false,
  banned_at timestamptz null,
  ban_reason text not null default '',
  updated_at timestamptz not null default now()
);

create trigger trg_job_seeker_moderation_updated_at
before update on public.job_seeker_moderation
for each row execute function public.set_updated_at();

alter table public.job_listing_reports enable row level security;
alter table public.employer_moderation enable row level security;
alter table public.job_seeker_moderation enable row level security;

drop policy if exists job_listing_reports_insert_own on public.job_listing_reports;
create policy job_listing_reports_insert_own
  on public.job_listing_reports
  for insert
  with check (auth.uid() = reporter_user_id);

drop policy if exists job_listing_reports_select_own on public.job_listing_reports;
create policy job_listing_reports_select_own
  on public.job_listing_reports
  for select
  using (auth.uid() = reporter_user_id);

drop policy if exists job_listing_reports_admin_all on public.job_listing_reports;
create policy job_listing_reports_admin_all
  on public.job_listing_reports
  for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists employer_moderation_owner_select on public.employer_moderation;
create policy employer_moderation_owner_select
  on public.employer_moderation
  for select
  using (
    public.is_admin()
    or exists (
      select 1
      from public.employer_profiles ep
      where ep.id = employer_id
        and ep.owner_user_id = auth.uid()
    )
  );

drop policy if exists employer_moderation_admin_all on public.employer_moderation;
create policy employer_moderation_admin_all
  on public.employer_moderation
  for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists job_seeker_moderation_select_own on public.job_seeker_moderation;
create policy job_seeker_moderation_select_own
  on public.job_seeker_moderation
  for select
  using (public.is_admin() or auth.uid() = user_id);

drop policy if exists job_seeker_moderation_admin_all on public.job_seeker_moderation;
create policy job_seeker_moderation_admin_all
  on public.job_seeker_moderation
  for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists job_listings_insert_own_employer on public.job_listings;
create policy job_listings_insert_own_employer
  on public.job_listings
  for insert
  with check (
    employer_id is not null
    and not exists (
      select 1
      from public.employer_moderation moderation
      where moderation.employer_id = job_listings.employer_id
        and moderation.is_banned = true
    )
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
    and not exists (
      select 1
      from public.employer_moderation moderation
      where moderation.employer_id = job_listings.employer_id
        and moderation.is_banned = true
    )
    and exists (
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
  with check (
    auth.uid() = applicant_user_id
    and not exists (
      select 1
      from public.job_seeker_moderation moderation
      where moderation.user_id = auth.uid()
        and moderation.is_banned = true
    )
  );