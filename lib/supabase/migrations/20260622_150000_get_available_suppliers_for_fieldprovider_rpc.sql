-- FieldProvider-safe supplier listing RPC (least-privilege)
--
-- Fixes: "permission denied for table users" when client cannot SELECT from public.users.
-- Approach: SECURITY DEFINER + return TABLE of only safe fields (NOT setof public.users).
--
-- Security:
-- - Derives caller from auth.uid()
-- - Verifies caller role is fieldProvider (or privileged admin roles)
-- - Applies approval filter and optional state/LGA scoping server-side
-- - Returns only minimal columns needed by the Request Restock UI

begin;

create or replace function public.get_available_suppliers_for_fieldprovider()
returns table(
  id uuid,
  username text,
  name text,
  email text,
  contact_email text,
  facility_name text,
  ward text,
  lga text,
  state text,
  role text,
  approvalstatus text,
  created_at timestamptz,
  updated_at timestamptz
)
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
  -- Ensure we have a profile row for auth.uid()
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

  -- FieldProvider is the intended caller. We also allow admin/superadmin for troubleshooting.
  if v_my_role not in ('fieldprovider', 'admin', 'superadmin', 'sfhteam') then
    raise exception 'not_authorized';
  end if;

  return query
  select
    u.id,
    u.username,
    u.name,
    u.email,
    u.contact_email,
    u.facilityName,
    u.ward,
    u.lga,
    u.state,
    u.role,
    u.approvalstatus,
    u.createdAt,
    u.updatedAt
  from public.users u
  where (
    lower(trim(coalesce(u.role::text, ''))) = 'supplier'
    or lower(trim(coalesce(u.role::text, ''))) = 'vendor'
    or lower(trim(coalesce(u.role::text, ''))) like '%supplier%'
  )
  and lower(trim(coalesce(u.approvalstatus::text, ''))) in ('approved', 'active')
  and (
    -- If caller has no state set, don't scope.
    v_my_state is null
    -- Global suppliers (no state) are visible to everyone.
    or nullif(lower(trim(coalesce(u.state::text, ''))), '') is null
    or nullif(lower(trim(coalesce(u.state::text, ''))), '') = v_my_state
  )
  and (
    -- If caller has no LGA set, don't scope by LGA.
    v_my_lga is null
    -- Global suppliers (no LGA) are visible to everyone.
    or nullif(lower(trim(coalesce(u.lga::text, ''))), '') is null
    or nullif(lower(trim(coalesce(u.lga::text, ''))), '') = v_my_lga
  )
  order by u.username asc nulls last;
end;
$$;

revoke all on function public.get_available_suppliers_for_fieldprovider() from public;
grant execute on function public.get_available_suppliers_for_fieldprovider() to authenticated;

-- Diagnostics function returning only counts + caller scope (no PII).
create or replace function public.get_available_suppliers_for_fieldprovider_diagnostics()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_my_role text;
  v_my_state text;
  v_my_lga text;
  v_total_suppliers bigint;
  v_total_suppliers_approved bigint;
  v_after_state bigint;
  v_after_lga bigint;
  v_me_exists boolean;
begin
  select count(*) > 0 into v_me_exists from public.users u where u.id = auth.uid();
  if not v_me_exists then
    return jsonb_build_object('ok', false, 'error', 'profile_not_found', 'myId', auth.uid());
  end if;

  select lower(trim(coalesce(u.role::text, ''))),
         nullif(lower(trim(coalesce(u.state::text, ''))), ''),
         nullif(lower(trim(coalesce(u.lga::text, ''))), '')
    into v_my_role, v_my_state, v_my_lga
  from public.users u
  where u.id = auth.uid();

  if v_my_role not in ('fieldprovider', 'admin', 'superadmin', 'sfhteam') then
    return jsonb_build_object('ok', false, 'error', 'not_authorized', 'myRole', v_my_role, 'myId', auth.uid());
  end if;

  select count(*) into v_total_suppliers
  from public.users u
  where (
    lower(trim(coalesce(u.role::text, ''))) = 'supplier'
    or lower(trim(coalesce(u.role::text, ''))) = 'vendor'
    or lower(trim(coalesce(u.role::text, ''))) like '%supplier%'
  );

  select count(*) into v_total_suppliers_approved
  from public.users u
  where (
    lower(trim(coalesce(u.role::text, ''))) = 'supplier'
    or lower(trim(coalesce(u.role::text, ''))) = 'vendor'
    or lower(trim(coalesce(u.role::text, ''))) like '%supplier%'
  )
  and lower(trim(coalesce(u.approvalstatus::text, ''))) in ('approved', 'active');

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

  return jsonb_build_object(
    'ok', true,
    'myProfile', jsonb_build_object('id', auth.uid(), 'role_norm', v_my_role, 'state_norm', v_my_state, 'lga_norm', v_my_lga),
    'counts', jsonb_build_object(
      'supplier_like', v_total_suppliers,
      'approved', v_total_suppliers_approved,
      'after_state', v_after_state,
      'after_lga', v_after_lga
    )
  );
end;
$$;

revoke all on function public.get_available_suppliers_for_fieldprovider_diagnostics() from public;
grant execute on function public.get_available_suppliers_for_fieldprovider_diagnostics() to authenticated;

commit;
