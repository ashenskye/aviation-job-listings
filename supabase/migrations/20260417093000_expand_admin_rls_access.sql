create or replace function public.is_admin()
returns boolean
language sql
stable
as $$
	select coalesce(
		(auth.jwt() -> 'app_metadata' ->> 'role') = 'admin',
		(auth.jwt() -> 'user_metadata' ->> 'role') = 'admin',
		false
	);
$$;

drop policy if exists user_preferences_admin_all on public.user_preferences;
create policy user_preferences_admin_all
	on public.user_preferences
	for all
	using (public.is_admin())
	with check (public.is_admin());

drop policy if exists saved_jobs_admin_all on public.saved_jobs;
create policy saved_jobs_admin_all
	on public.saved_jobs
	for all
	using (public.is_admin())
	with check (public.is_admin());

do $$
begin
	if to_regclass('public.application_feedback') is not null then
		execute 'drop policy if exists application_feedback_admin_all on public.application_feedback';
		execute $policy$
			create policy application_feedback_admin_all
				on public.application_feedback
				for all
				using (public.is_admin())
				with check (public.is_admin())
		$policy$;
	end if;
end
$$;

do $$
begin
	if to_regclass('public.admin_action_logs') is not null then
		execute 'drop policy if exists admin_action_logs_admin_all on public.admin_action_logs';
		execute $policy$
			create policy admin_action_logs_admin_all
				on public.admin_action_logs
				for all
				using (public.is_admin())
				with check (public.is_admin())
		$policy$;
	end if;
end
$$;
