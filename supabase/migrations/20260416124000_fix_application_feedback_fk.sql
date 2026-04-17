-- Ensure application_feedback keeps a valid FK to job_applications
-- after job_applications table recreation migrations.

do $$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'application_feedback'
  ) then
    alter table public.application_feedback
      drop constraint if exists application_feedback_application_id_fkey;

    alter table public.application_feedback
      add constraint application_feedback_application_id_fkey
      foreign key (application_id)
      references public.job_applications(id)
      on delete cascade;
  end if;
end $$;
