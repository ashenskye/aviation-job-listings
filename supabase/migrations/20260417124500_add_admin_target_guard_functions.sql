create or replace function public.user_is_admin(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from auth.users u
    where u.id = target_user_id
      and (
        coalesce(u.raw_app_meta_data ->> 'role', '') = 'admin'
        or coalesce(u.raw_user_meta_data ->> 'role', '') = 'admin'
      )
  );
$$;

create or replace function public.employer_owner_is_admin(target_employer_id text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.employer_profiles ep
    join auth.users u on u.id = ep.owner_user_id
    where ep.id = target_employer_id
      and (
        coalesce(u.raw_app_meta_data ->> 'role', '') = 'admin'
        or coalesce(u.raw_user_meta_data ->> 'role', '') = 'admin'
      )
  );
$$;
