-- Supabase schema for MediFlow
-- Generated from lib/models/*.dart

create extension if not exists pgcrypto;

-- USERS
-- Note: This is your app-level profile table. It references auth.users.
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  -- Username is the PRIMARY user-facing identifier (used for username login).
  -- Stored as entered, but uniqueness should be enforced case-insensitively via an index on lower(trim(username)).
  username text not null,

  -- Auth email (may be synthetic for username-only accounts). Do not show synthetic auth emails in UI.
  -- NOTE: historically this column was used as the app's "email".
  email text not null,

  -- Optional real contact email address. For normal users, this should match `email`.
  -- For username-only accounts, this should be NULL.
  contactEmail text null,

  -- True when `email` is a synthetic internal auth email like <uuid>@auth.local.invalid.
  isSyntheticAuthEmail boolean not null default false,
  role text not null,
  approvalStatus text not null default 'pending',
  approvedAt timestamptz null,
  approvedBy uuid null references public.users(id) on delete set null,
  adminScope text not null default 'none',
  facilityName text null,
  providerType text null,
  businessAddress text null,
  ward text null,
  lga text null,
  state text null,
  latitude double precision null,
  longitude double precision null,
  forcePasswordChange boolean not null default false,
  lastLogin timestamptz null,
  createdAt timestamptz not null default now(),
  updatedAt timestamptz not null default now(),
  -- Audit: who last modified this profile row.
  -- Note: for service-role updates, the Edge Function should set this explicitly.
  updatedBy uuid null references public.users(id) on delete set null
);

create unique index if not exists idx_users_email_unique on public.users (email);

-- Production-safe uniqueness helpers (case-insensitive).
-- NOTE: If you already have duplicates (case variants) these indexes will fail to create.
-- In that case, normalize existing rows first, then create indexes.
create unique index if not exists idx_users_username_normalized_unique on public.users ((lower(trim(username))));
create unique index if not exists idx_users_email_lower_unique on public.users ((lower(trim(email))));

-- Analytics/performance indexes (safe, additive)
create index if not exists idx_users_role on public.users (role);
create index if not exists idx_users_state on public.users (state);
create index if not exists idx_users_provider_type on public.users (providerType);
create index if not exists idx_users_approval_status on public.users (approvalStatus);
create index if not exists idx_users_created_at on public.users (createdAt);

create index if not exists idx_users_updated_by on public.users (updatedBy);

-- =========================================================
-- BUSINESS ADDRESS (separate table; Supabase source-of-truth)
--
-- Reason: allows adding fields (Ward, geocodes, audit) without bloating users.
-- App uses local cache + this table as remote source-of-truth.
-- =========================================================
create table if not exists public.user_business_addresses (
  user_id uuid primary key references public.users(id) on delete cascade,
  business_address text not null,
  ward text null,
  state text not null,
  lga text not null,
  latitude double precision null,
  longitude double precision null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_user_business_addresses_state on public.user_business_addresses (state);
create index if not exists idx_user_business_addresses_lga on public.user_business_addresses (lga);

-- =========================================================
-- ADMIN: Super Admin profile-only edits for Field Providers
--
-- IMPORTANT: This function is SECURITY DEFINER so it can be used even when
-- RLS blocks direct updates. It enforces authorization server-side by checking
-- the caller's role/scope from public.users (never from client claims).
--
-- Use this ONLY for profile/business fields that do not affect authentication
-- identity or approval side effects.
-- =========================================================

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
        or coalesce(nullif(trim(u."adminScope"), ''), 'none') = 'full'
        or lower(trim(u.email)) = lower(trim('tundeoyelana@gmail.com'))
      )
  );
$$;

create or replace function public.admin_update_fieldprovider_profile(
  target_user_id uuid,
  patch jsonb
)
returns public.users
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid;
  target public.users;
  v_state text;
  v_lga text;
  v_facility text;
  v_provider_type text;
  v_business_address text;
  v_contact_email text;
  v_lat double precision;
  v_lng double precision;
begin
  me := auth.uid();
  if me is null then
    raise exception 'Not authenticated';
  end if;

  if not public._is_superadmin_full(me) then
    raise exception 'Forbidden';
  end if;

  select * into target from public.users where id = target_user_id;
  if target.id is null then
    raise exception 'Target user not found';
  end if;
  if coalesce(nullif(trim(target.role), ''), 'unknown') <> 'fieldProvider' then
    raise exception 'Target user is not a fieldProvider';
  end if;

  v_state := nullif(trim(coalesce(patch->>'state', target.state)), '');
  v_lga := nullif(trim(coalesce(patch->>'lga', target.lga)), '');
  v_facility := nullif(trim(coalesce(patch->>'facilityName', target."facilityName")), '');
  v_business_address := nullif(trim(coalesce(patch->>'businessAddress', target."businessAddress")), '');
  v_contact_email := nullif(trim(coalesce(patch->>'contactEmail', target."contactEmail")), '');

  v_provider_type := nullif(trim(coalesce(patch->>'providerType', target."providerType")), '');
  if v_provider_type is not null then
    v_provider_type := lower(v_provider_type);
    if v_provider_type not in ('ppmv','cp','chp') then
      raise exception 'Invalid providerType';
    end if;
  end if;

  v_lat := null;
  v_lng := null;
  if patch ? 'latitude' then
    v_lat := nullif(trim(patch->>'latitude'), '')::double precision;
  else
    v_lat := target.latitude;
  end if;
  if patch ? 'longitude' then
    v_lng := nullif(trim(patch->>'longitude'), '')::double precision;
  else
    v_lng := target.longitude;
  end if;

  update public.users u
  set
    state = v_state,
    lga = v_lga,
    "facilityName" = v_facility,
    "providerType" = v_provider_type,
    "businessAddress" = v_business_address,
    "contactEmail" = v_contact_email,
    latitude = v_lat,
    longitude = v_lng,
    "updatedAt" = now(),
    "updatedBy" = me
  where u.id = target_user_id
  returning * into target;

  return target;
end;
$$;

-- Ensure authenticated callers can execute the RPC.
grant execute on function public.admin_update_fieldprovider_profile(uuid, jsonb) to authenticated;

-- =========================================================
-- FIELD PROVIDER ANALYTICS (backend source-of-truth)
--
-- Canonical profile table: public.users
--
-- Scope rule (production-safe default):
-- - superAdmin OR adminScope in ('full','viewOnly') => global visibility
-- - admin/stateMalaria/stateHIVTB => state-scoped visibility (matches their own state)
-- - everyone else => no access
--
-- NOTE: If your real Admin scope model is different (e.g., admin_id linkage,
-- organization_id, region, etc.) adjust the scope derivation in
-- public._fieldprovider_scope() only; all RPCs will stay consistent.
-- =========================================================

create or replace view public.fieldprovider_analytics_base as
select
  u.id as profile_id,
  u.role as role,
  coalesce(nullif(trim(u.state), ''), 'Unknown') as state,
  (
    case
      when regexp_replace(lower(coalesce(u.providerType, '')), '[^a-z]', '', 'g') = 'ppmv' then 'PPMV'
      when regexp_replace(lower(coalesce(u.providerType, '')), '[^a-z]', '', 'g') = 'cp' then 'CP'
      when regexp_replace(lower(coalesce(u.providerType, '')), '[^a-z]', '', 'g') = 'chp' then 'CHP'
      else 'Unknown'
    end
  ) as provider_type,
  -- Stable scope key used by analytics functions; currently state-based.
  coalesce(nullif(trim(u.state), ''), 'Unknown') as admin_scope_key,
  u."createdAt" as created_at
from public.users u
where
  -- Only FieldProvider accounts.
  u.role = 'fieldProvider'
  -- Include legacy/existing accounts too.
  --
  -- Why: older deployments commonly did not have `approvalStatus` or used a
  -- different approval mechanism. When `approvalStatus` was introduced with a
  -- NOT NULL default of 'pending', pre-existing FieldProvider rows can appear as
  -- 'pending' even though they are operationally active.
  --
  -- Production-safe rule: exclude only explicitly rejected accounts.
  and coalesce(nullif(trim(u."approvalStatus"), ''), 'approved') <> 'rejected';

-- Helper: resolve caller scope server-side. Do NOT trust client-passed role/admin id.
create or replace function public._fieldprovider_scope()
returns table(
  effective_role text,
  is_global boolean,
  scope_state text
)
language sql
stable
as $$
  with me as (
    select
      coalesce(nullif(trim(role), ''), 'unknown') as role,
      coalesce(nullif(trim("adminScope"), ''), 'none') as admin_scope,
      coalesce(nullif(trim(state), ''), 'Unknown') as state
    from public.users
    where id = auth.uid()
  )
  select
    case
      when admin_scope = 'full' then 'superAdmin'
      when admin_scope = 'viewOnly' then 'sfhTeam'
      else role
    end as effective_role,
    (
      admin_scope in ('full','viewOnly')
      or role in ('superAdmin','sfhTeam')
    ) as is_global,
    state as scope_state
  from me;
$$;

create or replace function public.get_fieldprovider_total()
returns bigint
language plpgsql
stable
as $$
declare
  s record;
begin
  select * into s from public._fieldprovider_scope();

  if s.is_global then
    return (select count(*)::bigint from public.fieldprovider_analytics_base);
  end if;

  if s.effective_role in ('admin','stateMalaria','stateHIVTB') then
    return (
      select count(*)::bigint
      from public.fieldprovider_analytics_base b
      where b.admin_scope_key = s.scope_state
    );
  end if;

  return 0;
end;
$$;

create or replace function public.get_fieldprovider_breakdown_by_state(selected_provider_type text default null)
returns table(state text, total_count bigint)
language plpgsql
stable
as $$
declare
  s record;
  pt text;
begin
  select * into s from public._fieldprovider_scope();
  pt := nullif(trim(coalesce(selected_provider_type, '')), '');

  if not s.is_global and s.effective_role not in ('admin','stateMalaria','stateHIVTB') then
    return;
  end if;

  return query
  select
    b.state,
    count(*)::bigint as total_count
  from public.fieldprovider_analytics_base b
  where
    (s.is_global or b.admin_scope_key = s.scope_state)
    and (pt is null or b.provider_type = pt)
  group by b.state
  order by total_count desc, b.state asc;
end;
$$;

create or replace function public.get_fieldprovider_breakdown_by_type(selected_state text default null)
returns table(provider_type text, total_count bigint)
language plpgsql
stable
as $$
declare
  s record;
  st text;
begin
  select * into s from public._fieldprovider_scope();
  st := nullif(trim(coalesce(selected_state, '')), '');

  if not s.is_global and s.effective_role not in ('admin','stateMalaria','stateHIVTB') then
    return;
  end if;

  return query
  select
    b.provider_type,
    count(*)::bigint as total_count
  from public.fieldprovider_analytics_base b
  where
    (s.is_global or b.admin_scope_key = s.scope_state)
    and (st is null or b.state = st)
  group by b.provider_type
  order by total_count desc, b.provider_type asc;
end;
$$;

create or replace function public.get_fieldprovider_filtered_list(
  selected_state text default null,
  selected_provider_type text default null
)
returns table(
  profile_id uuid,
  username text,
  email text,
  contact_email text,
  state text,
  provider_type text,
  created_at timestamptz
)
language plpgsql
stable
as $$
declare
  s record;
  st text;
  pt text;
begin
  select * into s from public._fieldprovider_scope();
  st := nullif(trim(coalesce(selected_state, '')), '');
  pt := nullif(trim(coalesce(selected_provider_type, '')), '');

  if not s.is_global and s.effective_role not in ('admin','stateMalaria','stateHIVTB') then
    return;
  end if;

  return query
  select
    u.id as profile_id,
    u.username,
    u.email,
    u."contactEmail" as contact_email,
    b.state,
    b.provider_type,
    b.created_at
  from public.fieldprovider_analytics_base b
  join public.users u on u.id = b.profile_id
  where
    (s.is_global or b.admin_scope_key = s.scope_state)
    and (st is null or b.state = st)
    and (pt is null or b.provider_type = pt)
  order by b.created_at desc;
end;
$$;

-- COMMODITIES
create table if not exists public.commodities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  program text not null,
  unit text not null,
  -- Optional standardized unit for quantity display.
  -- Allowed values: EA, PC, PCK, Carton
  unit_of_expression text null,
  currentQuantity integer not null default 0,
  minThreshold integer not null default 0,
  createdAt timestamptz not null default now(),
  updatedAt timestamptz not null default now()
);

create index if not exists idx_commodities_program on public.commodities (program);

-- STOCK MOVEMENTS
create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  commodityId uuid not null references public.commodities(id) on delete restrict,
  userId uuid not null references public.users(id) on delete restrict,
  type text not null,
  quantity integer not null,
  reason text not null,
  notes text null,
  syncStatus text not null default 'pending',
  createdAt timestamptz not null default now()
);

create index if not exists idx_stock_movements_commodity_id on public.stock_movements (commodityId);
create index if not exists idx_stock_movements_user_id on public.stock_movements (userId);

-- TEST RECORDS
create table if not exists public.test_records (
  id uuid primary key default gen_random_uuid(),
  userId uuid not null references public.users(id) on delete restrict,
  program text not null,
  clientName text not null,
  clientId text not null,
  ageBand text not null,
  testDate timestamptz not null,
  sex text not null,
  pregnant boolean null,
  visitType text not null,

  -- Malaria
  feverPresented boolean null,
  mRDTTested boolean null,
  mRDTPositive boolean null,
  actGiven boolean null,

  -- HIV
  hivCounselling boolean null,
  hivstType text null,
  determineTest text null,
  artLinkage text null,
  referralFacility text null,
  prepAssessed boolean null,
  prepEligible boolean null,
  prepOffered boolean null,
  prepAccepted boolean null,
  prepStarted boolean null,
  prepContinued boolean null,
  prepRefSource text null,

  -- TB
  tbScreening text null,
  notes text null,

  syncStatus text not null default 'pending',
  createdAt timestamptz not null default now(),
  updatedAt timestamptz not null default now()
);

create index if not exists idx_test_records_user_id on public.test_records (userId);
create index if not exists idx_test_records_program on public.test_records (program);
create index if not exists idx_test_records_test_date on public.test_records (testDate);

-- Aggregation-performance indexes (lifetime counts, day filters, per-user totals)
create index if not exists idx_test_records_created_at on public.test_records (createdAt);
create index if not exists idx_test_records_user_created_at on public.test_records (userId, createdAt);

-- Canonical, RLS-respecting lifetime count RPC.
-- IMPORTANT: This function runs with SECURITY INVOKER semantics (default),
-- so it will only count rows the current caller can SELECT via RLS.
create or replace function public.count_test_records_lifetime()
returns bigint
language sql
stable
as $$
  select count(*)::bigint from public.test_records;
$$;

-- DELIVERIES
-- The model stores line items as a list; we persist them as JSONB for simplicity.
create table if not exists public.deliveries (
  id uuid primary key default gen_random_uuid(),
  supplierId uuid not null references public.users(id) on delete restrict,
  supplierName text not null,
  providerId uuid not null references public.users(id) on delete restrict,
  deliveryDate timestamptz not null,
  reference text null,
  items jsonb not null default '[]'::jsonb,
  status text not null default 'pending',
  syncStatus text not null default 'pending',
  createdAt timestamptz not null default now(),
  updatedAt timestamptz not null default now()
);

create index if not exists idx_deliveries_provider_id on public.deliveries (providerId);
create index if not exists idx_deliveries_supplier_id on public.deliveries (supplierId);
create index if not exists idx_deliveries_delivery_date on public.deliveries (deliveryDate);

-- STOCK REQUESTS
-- Provider requests stock from a supplier; items stored as JSONB for simplicity.
create table if not exists public.stock_requests (
  id uuid primary key default gen_random_uuid(),
  providerId uuid not null references public.users(id) on delete restrict,
  providerName text not null,
  providerEmail text not null,
  providerFacilityName text null,
  providerBusinessAddress text null,
  providerState text null,
  providerLga text null,
  providerLatitude double precision null,
  providerLongitude double precision null,
  supplierId uuid not null references public.users(id) on delete restrict,
  supplierName text not null,
  status text not null default 'pending',
  items jsonb not null default '[]'::jsonb,
  notes text null,
  createdAt timestamptz not null default now(),
  updatedAt timestamptz not null default now()
);

create index if not exists idx_stock_requests_provider_id on public.stock_requests (providerId);
create index if not exists idx_stock_requests_supplier_id on public.stock_requests (supplierId);
create index if not exists idx_stock_requests_created_at on public.stock_requests (createdAt);

-- PRODUCT REQUESTS
-- Field providers can request a new product to be added to the master commodities list.
create table if not exists public.product_requests (
  id uuid primary key default gen_random_uuid(),
  requestedBy uuid not null references public.users(id) on delete restrict,
  facilityName text null,
  requestedName text not null,
  unit text null,
  program text null,
  notes text null,
  status text not null default 'pending',
  createdAt timestamptz not null default now(),
  updatedAt timestamptz not null default now()
);

create index if not exists idx_product_requests_requested_by on public.product_requests (requestedBy);
create index if not exists idx_product_requests_created_at on public.product_requests (createdAt);
