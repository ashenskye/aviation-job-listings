drop policy if exists job_listings_admin_all on public.job_listings;
create policy job_listings_admin_all
  on public.job_listings
  for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists job_applications_admin_all on public.job_applications;
create policy job_applications_admin_all
  on public.job_applications
  for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists job_seeker_profiles_admin_all on public.job_seeker_profiles;
create policy job_seeker_profiles_admin_all
  on public.job_seeker_profiles
  for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists employer_profiles_admin_all on public.employer_profiles;
create policy employer_profiles_admin_all
  on public.employer_profiles
  for all
  using (public.is_admin())
  with check (public.is_admin());
