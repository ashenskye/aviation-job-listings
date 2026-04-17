create table if not exists public.job_listing_templates (
  id text primary key,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  employer_id text not null,
  template_name text not null,
  listing jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_job_listing_templates_owner
  on public.job_listing_templates(owner_user_id);
create index if not exists idx_job_listing_templates_employer
  on public.job_listing_templates(employer_id);
alter table public.job_listing_templates enable row level security;
drop policy if exists "Owners can read templates" on public.job_listing_templates;
create policy "Owners can read templates"
  on public.job_listing_templates
  for select
  using (auth.uid() = owner_user_id);
drop policy if exists "Owners can insert templates" on public.job_listing_templates;
create policy "Owners can insert templates"
  on public.job_listing_templates
  for insert
  with check (auth.uid() = owner_user_id);
drop policy if exists "Owners can update templates" on public.job_listing_templates;
create policy "Owners can update templates"
  on public.job_listing_templates
  for update
  using (auth.uid() = owner_user_id)
  with check (auth.uid() = owner_user_id);
drop policy if exists "Owners can delete templates" on public.job_listing_templates;
create policy "Owners can delete templates"
  on public.job_listing_templates
  for delete
  using (auth.uid() = owner_user_id);
