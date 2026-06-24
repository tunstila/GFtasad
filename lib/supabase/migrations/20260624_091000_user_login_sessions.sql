-- SuperAdmin login/session auditing
--
-- Adds an audit table for login sessions and minimal RLS.
-- Session rows are created/updated via the login_tracker edge function.

begin;

create extension if not exists pgcrypto;

-- Ensure the helper exists (used by policies).
create or replace function public._is_superadmin_full(requester_id uuid default auth.uid())
returns boolean
language sql
stable
as $$
  select exists(
    select 1
    from public.users u
    where u.id = requester_id
      and (
        u.role = 'superAdmin'
        -- NOTE: Postgres folds unquoted identifiers to lowercase. In this project the column
        -- exists as `adminscope` (lowercase). Using "adminScope" would look for a quoted,
        -- case-sensitive column that doesn't exist.
        or coalesce(nullif(trim(u.adminscope), ''), 'none') = 'full'
        or lower(trim(u.email)) = lower(trim('tundeoyelana@gmail.com'))
      )
  );
$$;

create table if not exists public.user_login_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,

  signed_in_at timestamptz not null default now(),
  signed_out_at timestamptz null,
  last_seen_at timestamptz not null default now(),

  status text not null default 'active',
  end_reason text null, -- e.g. 'signed_out', 'last_seen_based', 'unknown'

  app_platform text null,
  app_version text null,
  device_id text null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_user_login_sessions_user_id on public.user_login_sessions (user_id);
create index if not exists idx_user_login_sessions_signed_in_at on public.user_login_sessions (signed_in_at);
create index if not exists idx_user_login_sessions_last_seen_at on public.user_login_sessions (last_seen_at);

alter table public.user_login_sessions enable row level security;

-- SuperAdmin-only read access.
drop policy if exists user_login_sessions_select_superadmin on public.user_login_sessions;
create policy user_login_sessions_select_superadmin on public.user_login_sessions
for select to authenticated
using (public._is_superadmin_full());

-- Users can insert their own rows if we ever choose to use PostgREST directly.
drop policy if exists user_login_sessions_insert_own on public.user_login_sessions;
create policy user_login_sessions_insert_own on public.user_login_sessions
for insert to authenticated
with check (user_id = auth.uid());

-- Users can update their own rows (heartbeat/sign-out).
drop policy if exists user_login_sessions_update_own on public.user_login_sessions;
create policy user_login_sessions_update_own on public.user_login_sessions
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

commit;
