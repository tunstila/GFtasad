-- Strict business location gate (State/LGA/Ward) for fieldProvider recording
--
-- Goals:
-- 1) Prevent new client code allocation from silently using ward fallback values (ALL)
-- 2) Prevent fieldProvider inserts into operational record tables when their Business profile is incomplete
--
-- Safe-by-default:
-- - Does NOT modify existing historical rows
-- - Applies only to INSERTs (new rows)
-- - Allows superAdmin/admin/national roles to read dashboards/reports unaffected

begin;

-- =========================================================
-- 1) Make allocate_client_code ward-aware and strict
-- =========================================================
-- Keep signature for backwards compatibility, but treat blank type_segment as:
--   derive from provider Business ward, else error.
create or replace function public.allocate_client_code(
  provider_user_id uuid,
  type_segment text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_state text;
  v_lga text;
  v_ward text;
  v_type text;
begin
  if provider_user_id is null then
    raise exception 'provider_user_id is required';
  end if;

  -- Source-of-truth: business address table when present, fallback to users.
  select uba.state, uba.lga, uba.ward into v_state, v_lga, v_ward
  from public.user_business_addresses uba
  where uba.user_id = provider_user_id;

  if v_state is null or v_lga is null or v_ward is null then
    select u.state, u.lga, u.ward into v_state, v_lga, v_ward
    from public.users u
    where u.id = provider_user_id;
  end if;

  if v_state is null or nullif(trim(v_state), '') is null then
    raise exception 'Cannot allocate code: provider state is missing';
  end if;
  if v_lga is null or nullif(trim(v_lga), '') is null then
    raise exception 'Cannot allocate code: provider LGA is missing';
  end if;

  v_type := nullif(trim(coalesce(type_segment, '')), '');
  if v_type is null then
    v_type := nullif(trim(coalesce(v_ward, '')), '');
  end if;
  if v_type is null then
    raise exception 'Cannot allocate code: provider ward is missing';
  end if;

  return public.next_generated_code(v_state, v_lga, v_type);
end;
$$;

-- If a clients auto-generator trigger exists, ensure it no longer hardcodes ALL.
-- (Some installs create clients lazily; we guard by to_regclass).
do $$
begin
  if to_regclass('public.clients') is null then return; end if;

  create or replace function public._clients_set_generated_code()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
  as $$
  begin
    if new.clientid is null
      or nullif(trim(new.clientid), '') is null
      or new.clientid !~ '^[A-Z]{3}-[A-Z]{3}-[A-Z]{3}-\\d{7}$'
    then
      -- Strict: allow allocator to derive ward from provider Business profile.
      new.clientid := public.allocate_client_code(new.provideruserid, null);
    else
      new.clientid := upper(trim(new.clientid));
    end if;
    return new;
  end;
  $$;

  drop trigger if exists trg_clients_set_generated_code on public.clients;
  create trigger trg_clients_set_generated_code
  before insert on public.clients
  for each row
  execute function public._clients_set_generated_code();
end;
$$;

-- =========================================================
-- 2) Enforce fieldProvider business location completeness on INSERT (backend-safe)
-- =========================================================
create or replace function public._enforce_fieldprovider_business_location_complete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_role text;
  v_ok boolean;
  v_has_biz boolean;
begin
  v_uid := auth.uid();
  if v_uid is null then
    return new;
  end if;

  select u.role into v_role from public.users u where u.id = v_uid;
  v_role := coalesce(nullif(trim(v_role), ''), 'unknown');

  -- Only enforce for fieldProvider. superAdmin should remain unblocked.
  if v_role <> 'fieldProvider' then
    return new;
  end if;

  select to_regclass('public.user_business_addresses') is not null into v_has_biz;

  if v_has_biz then
    select exists(
      select 1
      from public.user_business_addresses uba
      where uba.user_id = v_uid
        and nullif(trim(coalesce(uba.state, '')), '') is not null
        and nullif(trim(coalesce(uba.lga, '')), '') is not null
        and nullif(trim(coalesce(uba.ward, '')), '') is not null
    ) into v_ok;
  else
    -- Back-compat: if the Business table isn't present, fall back to users columns.
    select exists(
      select 1
      from public.users u
      where u.id = v_uid
        and nullif(trim(coalesce(u.state, '')), '') is not null
        and nullif(trim(coalesce(u.lga, '')), '') is not null
        and nullif(trim(coalesce(u.ward, '')), '') is not null
    ) into v_ok;
  end if;

  if not v_ok then
    raise exception 'Please complete your Business Profile State, LGA, and Ward before recording tests.';
  end if;

  return new;
end;
$$;

-- Attach triggers only if tables exist.
do $$
begin
  if to_regclass('public.test_records') is not null then
    drop trigger if exists trg_test_records_require_business_location on public.test_records;
    create trigger trg_test_records_require_business_location
    before insert on public.test_records
    for each row
    execute function public._enforce_fieldprovider_business_location_complete();
  end if;

  if to_regclass('public.prevention_messaging_records') is not null then
    drop trigger if exists trg_prevention_records_require_business_location on public.prevention_messaging_records;
    create trigger trg_prevention_records_require_business_location
    before insert on public.prevention_messaging_records
    for each row
    execute function public._enforce_fieldprovider_business_location_complete();
  end if;
end;
$$;

commit;
