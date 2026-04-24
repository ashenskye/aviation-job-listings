alter table public.job_listings
  drop constraint if exists job_listings_status_check;

alter table public.job_listings
  add constraint job_listings_status_check
  check (status in ('active', 'draft', 'expired', 'archived', 'closed'));

drop policy if exists job_listings_select_authenticated on public.job_listings;

create policy job_listings_select_authenticated
  on public.job_listings
  for select
  using (
    auth.uid() is not null
    and (
      status = 'active'
      or (
        employer_id is not null
        and exists (
          select 1
          from public.employer_profiles ep
          where ep.id = job_listings.employer_id
            and ep.owner_user_id = auth.uid()
        )
      )
    )
  );