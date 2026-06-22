-- Supplier visibility debugging + v2 supplier listing RPC
-- Production-safe: CREATE OR REPLACE only. No schema drops.

begin;

-- Returns stepwise counts + discovered distinct values to help diagnose why suppliers are filtered out.
-- SECURITY DEFINER so it can see rows even when `public.users` has restrictive RLS.
create or replace function public.supplier_visibility_diagnostics()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_my_role text;
  v_my_state text;
  v_my_lga text;

  v_total_users bigint;
  v_supplier_like bigint;
  v_supplier_like_approved bigint;
  v_after_state bigint;
  v_after_lga bigint;

  v_distinct_roles jsonb;
  v_distinct_approvals jsonb;
  v_user_columns jsonb;
  v_sample_suppliers jsonb;

  v_me_exists boolean;
begin
  select count(*) > 0 into v_me_exists from public.users u where u.id = auth.uid();
  if not v_me_exists then
    return jsonb_build_object(
      'ok', false,
      'error', 'profile_not_found',
      'hint', 'No row in public.users matches auth.uid(). Supplier visibility RPCs derive scope from public.users.'
    );
  end if;

  select lower(trim(coalesce(u.role::text, ''))),
         nullif(lower(trim(coalesce(u.state::text, ''))), ''),
         nullif(lower(trim(coalesce(u.lga::text, ''))), '')
    into v_my_role, v_my_state, v_my_lga
  from public.users u
  where u.id = auth.uid();

  if v_my_role not in ('fieldprovider', 'supplier', 'admin', 'superadmin') then
    return jsonb_build_object('ok', false, 'error', 'not_authorized', 'myRole', v_my_role);
  end if;

  select count(*) into v_total_users from public.users;

  -- Supplier-like definition (role normalization).
  select count(*) into v_supplier_like
  from public.users u
  where (
    lower(trim(coalesce(u.role::text, ''))) = 'supplier'
    or lower(trim(coalesce(u.role::text, ''))) = 'vendor'
    or lower(trim(coalesce(u.role::text, ''))) like '%supplier%'
  );

  -- Approval-like definition (approvalstatus normalization).
  select count(*) into v_supplier_like_approved
  from public.users u
  where (
    lower(trim(coalesce(u.role::text, ''))) = 'supplier'
    or lower(trim(coalesce(u.role::text, ''))) = 'vendor'
    or lower(trim(coalesce(u.role::text, ''))) like '%supplier%'
  )
  and lower(trim(coalesce(u.approvalstatus::text, ''))) in ('approved', 'active');

  -- Optional geographic scoping: allow global suppliers (null/blank state/lga).
  select count(*) into v_after_state
  from public.users u
  where (
    lower(trim(coalesce(u.role::text, ''))) = 'supplier'
    or lower(trim(coalesce(u.role::text, ''))) = 'vendor'
    or lower(trim(coalesce(u.role::text, ''))) like '%supplier%'
  )
  and lower(trim(coalesce(u.approvalstatus::text, ''))) in ('approved', 'active')
  and (
    v_my_state is null
    or nullif(lower(trim(coalesce(u.state::text, ''))), '') is null
    or nullif(lower(trim(coalesce(u.state::text, ''))), '') = v_my_state
  );

  select count(*) into v_after_lga
  from public.users u
  where (
    lower(trim(coalesce(u.role::text, ''))) = 'supplier'
    or lower(trim(coalesce(u.role::text, ''))) = 'vendor'
    or lower(trim(coalesce(u.role::text, ''))) like '%supplier%'
  )
  and lower(trim(coalesce(u.approvalstatus::text, ''))) in ('approved', 'active')
  and (
    v_my_state is null
    or nullif(lower(trim(coalesce(u.state::text, ''))), '') is null
    or nullif(lower(trim(coalesce(u.state::text, ''))), '') = v_my_state
  )
  and (
    v_my_lga is null
    or nullif(lower(trim(coalesce(u.lga::text, ''))), '') is null
    or nullif(lower(trim(coalesce(u.lga::text, ''))), '') = v_my_lga
  );

  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_distinct_roles
  from (
    select jsonb_build_object(
      'role_norm', lower(trim(coalesce(u.role::text, ''))),
      'count', count(*)
    ) as x
    from public.users u
    group by lower(trim(coalesce(u.role::text, '')))
    order by count(*) desc
    limit 50
  ) t;

  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_distinct_approvals
  from (
    select jsonb_build_object(
      'approval_norm', lower(trim(coalesce(u.approvalstatus::text, ''))),
      'count', count(*)
    ) as x
    from public.users u
    group by lower(trim(coalesce(u.approvalstatus::text, '')))
    order by count(*) desc
    limit 50
  ) t;

  select coalesce(jsonb_agg(column_name order by ordinal_position), '[]'::jsonb) into v_user_columns
  from information_schema.columns
  where table_schema = 'public' and table_name = 'users';

  -- Sample rows (safe-ish: no phone numbers; keep email as-is because it already exists in app UI).
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_sample_suppliers
  from (
    select jsonb_build_object(
      'id', u.id,
      'username', u.username,
      'email', u.email,
      'role_raw', u.role,
      'approval_raw', u.approvalstatus,
      'state', u.state,
      'lga', u.lga,
      'facilityName', u.facilityName
    ) as x
    from public.users u
    where (
      lower(trim(coalesce(u.role::text, ''))) = 'supplier'
      or lower(trim(coalesce(u.role::text, ''))) = 'vendor'
      or lower(trim(coalesce(u.role::text, ''))) like '%supplier%'
    )
    order by u.createdAt desc nulls last
    limit 15
  ) s;

  return jsonb_build_object(
    'ok', true,
    'myProfile', jsonb_build_object('id', auth.uid(), 'role_norm', v_my_role, 'state_norm', v_my_state, 'lga_norm', v_my_lga),
    'counts', jsonb_build_object(
      'total_users', v_total_users,
      'supplier_like', v_supplier_like,
      'supplier_like_approved', v_supplier_like_approved,
      'after_state', v_after_state,
      'after_lga', v_after_lga
    ),
    'distinct', jsonb_build_object(
      'roles', v_distinct_roles,
      'approvalstatus', v_distinct_approvals
    ),
    'users_table_columns', v_user_columns,
    'sample_supplier_rows', v_sample_suppliers
  );
end;
$$;

revoke all on function public.supplier_visibility_diagnostics() from public;
grant execute on function public.supplier_visibility_diagnostics() to authenticated;

-- V2 supplier list: normalized role/approval + optional scope derived from auth.uid() profile.
create or replace function public.list_available_suppliers_for_me()
returns setof public.users
language plpgsql
security definer
set search_path = public
as $$
declare
  v_my_role text;
  v_my_state text;
  v_my_lga text;
  v_me_exists boolean;
begin
  select count(*) > 0 into v_me_exists from public.users u where u.id = auth.uid();
  if not v_me_exists then
    raise exception 'profile_not_found';
  end if;

  select lower(trim(coalesce(u.role::text, ''))),
         nullif(lower(trim(coalesce(u.state::text, ''))), ''),
         nullif(lower(trim(coalesce(u.lga::text, ''))), '')
    into v_my_role, v_my_state, v_my_lga
  from public.users u
  where u.id = auth.uid();

  if v_my_role not in ('fieldprovider', 'supplier', 'admin', 'superadmin') then
    raise exception 'not_authorized';
  end if;

  return query
  select u.*
  from public.users u
  where (
    lower(trim(coalesce(u.role::text, ''))) = 'supplier'
    or lower(trim(coalesce(u.role::text, ''))) = 'vendor'
    or lower(trim(coalesce(u.role::text, ''))) like '%supplier%'
  )
  and lower(trim(coalesce(u.approvalstatus::text, ''))) in ('approved', 'active')
  and (
    v_my_state is null
    or nullif(lower(trim(coalesce(u.state::text, ''))), '') is null
    or nullif(lower(trim(coalesce(u.state::text, ''))), '') = v_my_state
  )
  and (
    v_my_lga is null
    or nullif(lower(trim(coalesce(u.lga::text, ''))), '') is null
    or nullif(lower(trim(coalesce(u.lga::text, ''))), '') = v_my_lga
  )
  order by u.username asc nulls last;
end;
$$;

revoke all on function public.list_available_suppliers_for_me() from public;
grant execute on function public.list_available_suppliers_for_me() to authenticated;

commit;
