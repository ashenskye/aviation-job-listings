-- Persist employer/applicant feedback in Supabase.
create table if not exists public.application_feedback (
  id text primary key,
  application_id text not null references public.job_applications(id) on delete cascade,
  message text not null default '',
  feedback_type text not null default 'custom' check (feedback_type in ('interested', 'not_fit', 'custom')),
  sent_by_employer boolean not null default true,
  sent_at timestamptz not null default now(),
  is_auto_generated boolean not null default false,
  created_at timestamptz not null default now(),
  unique (application_id)
);
create index if not exists idx_application_feedback_application_id
  on public.application_feedback(application_id);
alter table public.application_feedback enable row level security;
-- Participants in an application can read feedback.
drop policy if exists application_feedback_select_participant on public.application_feedback;
create policy application_feedback_select_participant
  on public.application_feedback
  for select
  using (
    exists (
      select 1
      from public.job_applications ja
      left join public.employer_profiles ep
        on ep.id = ja.employer_id
      where ja.id = application_feedback.application_id
        and (
          ja.applicant_user_id = auth.uid()
          or ep.owner_user_id = auth.uid()
        )
    )
  );
-- Employer owner can send/update feedback.
drop policy if exists application_feedback_write_employer_owner on public.application_feedback;
create policy application_feedback_write_employer_owner
  on public.application_feedback
  for all
  using (
    exists (
      select 1
      from public.job_applications ja
      join public.employer_profiles ep
        on ep.id = ja.employer_id
      where ja.id = application_feedback.application_id
        and ep.owner_user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.job_applications ja
      join public.employer_profiles ep
        on ep.id = ja.employer_id
      where ja.id = application_feedback.application_id
        and ep.owner_user_id = auth.uid()
    )
  );
