create table if not exists public.admin_action_logs (
  id text primary key default gen_random_uuid()::text,
  admin_user_id uuid not null references auth.users(id),
  action_type text not null,
  resource_type text not null,
  resource_id text not null,
  changes_before jsonb,
  changes_after jsonb,
  reason text,
  timestamp timestamptz not null default now(),
  ip_address text,
  created_at timestamptz not null default now(),
  constraint valid_action_type check (
    action_type in ('create', 'update', 'delete', 'view')
  )
);

create index if not exists idx_admin_action_logs_admin_user_id
  on public.admin_action_logs(admin_user_id);

create index if not exists idx_admin_action_logs_resource
  on public.admin_action_logs(resource_type, resource_id);

create index if not exists idx_admin_action_logs_timestamp
  on public.admin_action_logs(timestamp);

alter table public.admin_action_logs enable row level security;

drop policy if exists admin_action_logs_admin_select on public.admin_action_logs;
create policy admin_action_logs_admin_select
  on public.admin_action_logs
  for select
  using (public.is_admin());

drop policy if exists admin_action_logs_admin_insert on public.admin_action_logs;
create policy admin_action_logs_admin_insert
  on public.admin_action_logs
  for insert
  with check (public.is_admin());

drop policy if exists admin_action_logs_admin_all on public.admin_action_logs;
create policy admin_action_logs_admin_all
  on public.admin_action_logs
  for all
  using (public.is_admin())
  with check (public.is_admin());
