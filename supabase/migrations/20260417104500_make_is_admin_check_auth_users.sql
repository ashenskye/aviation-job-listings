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
