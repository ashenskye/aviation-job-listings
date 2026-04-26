create or replace function public.admin_set_user_profile_type(
  target_email text,
  new_profile_type text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  normalized_email text := lower(trim(coalesce(target_email, '')));
  normalized_profile_type text := lower(trim(coalesce(new_profile_type, '')));
  target_id uuid;
  previous_profile_type text;
begin
  if not public.is_admin() then
    raise exception 'permission denied';
  end if;

  if normalized_email = '' then
    raise exception 'Email is required.';
  end if;

  if normalized_profile_type not in ('job_seeker', 'employer') then
    raise exception 'Invalid profile_type. Allowed values: job_seeker, employer.';
  end if;

  select
    u.id,
    coalesce(nullif(lower(trim(u.raw_user_meta_data ->> 'profile_type')), ''), 'job_seeker')
  into target_id, previous_profile_type
  from auth.users u
  where lower(trim(coalesce(u.email, ''))) = normalized_email
  limit 1;

  if target_id is null then
    raise exception 'No user found for email %.', normalized_email;
  end if;

  if public.user_is_admin(target_id) then
    raise exception 'Cannot modify role for admin account.';
  end if;

  update auth.users
  set
    raw_user_meta_data =
      coalesce(raw_user_meta_data, '{}'::jsonb) ||
      jsonb_build_object('profile_type', normalized_profile_type),
    updated_at = now()
  where id = target_id;

  return jsonb_build_object(
    'user_id', target_id,
    'email', normalized_email,
    'before_profile_type', previous_profile_type,
    'after_profile_type', normalized_profile_type
  );
end;
$$;

revoke all on function public.admin_set_user_profile_type(text, text) from public;
grant execute on function public.admin_set_user_profile_type(text, text) to authenticated;
