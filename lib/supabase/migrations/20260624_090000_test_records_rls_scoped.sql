-- Enforce fieldProvider isolation on test_records (schema-tolerant)
--
-- Goal: prevent cross-fieldProvider record leakage while preserving admin/superAdmin
-- aggregate visibility.
--
-- This migration is idempotent.

begin;

-- Helper: read current user's app role from public.users (never trust client claims).
create or replace function public.app_role()
returns text
language sql
stable
as $$
  select coalesce((select role from public.users where id = auth.uid()), 'unknown');
$$;

create or replace function public.is_adminish()
returns boolean
language sql
stable
as $$
  select public.app_role() in ('admin','superAdmin','sfhTeam');
$$;

create or replace function public.can_global_read()
returns boolean
language sql
stable
as $$
  select public.app_role() in ('admin','superAdmin','sfhTeam','nationalMalaria','nationalHIVTB');
$$;

alter table public.test_records enable row level security;

-- Drop any permissive/legacy policies.
drop policy if exists "test_records_all_authenticated" on public.test_records;
drop policy if exists test_records_all_authenticated on public.test_records;
drop policy if exists test_records_select_scoped on public.test_records;
drop policy if exists test_records_insert_own on public.test_records;
drop policy if exists test_records_update_own on public.test_records;
drop policy if exists test_records_delete_own on public.test_records;

do $$
declare
  has_userid boolean;
  has_user_id boolean;
  has_user_id_camel boolean;
  owner_expr text;
begin
  select exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'test_records' and column_name = 'userid'
  ) into has_userid;

  select exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'test_records' and column_name = 'user_id'
  ) into has_user_id;

  select exists(
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'test_records' and column_name = 'userId'
  ) into has_user_id_camel;

  if has_userid then
    owner_expr := 'userid = auth.uid()';
  elsif has_user_id then
    owner_expr := 'user_id = auth.uid()';
  elsif has_user_id_camel then
    owner_expr := '"userId" = auth.uid()';
  else
    -- If the table doesn't have a recognizable ownership column, we must deny access.
    -- This is safer than allowing leakage.
    owner_expr := 'false';
  end if;

  execute format($sql$
    create policy test_records_select_scoped on public.test_records
    for select to authenticated
    using (public.can_global_read() or (%s));
  $sql$, owner_expr);

  execute format($sql$
    create policy test_records_insert_own on public.test_records
    for insert to authenticated
    with check (public.app_role() in ('fieldProvider','superAdmin') and (%s));
  $sql$, owner_expr);

  execute format($sql$
    create policy test_records_update_own on public.test_records
    for update to authenticated
    using (public.app_role() in ('fieldProvider','superAdmin') and (%s))
    with check (public.app_role() in ('fieldProvider','superAdmin') and (%s));
  $sql$, owner_expr, owner_expr);

  execute format($sql$
    create policy test_records_delete_own on public.test_records
    for delete to authenticated
    using (public.app_role() in ('fieldProvider','superAdmin') and (%s));
  $sql$, owner_expr);
end $$;

commit;
