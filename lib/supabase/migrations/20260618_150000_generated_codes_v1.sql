-- Production-safe generated code allocator (STATECODE-LGACODE-TYPECODE-SEQUENCE)
-- Example: LAG-IKE-ALL-0000001
--
-- Key properties:
-- - Concurrency-safe (single-row upsert increments sequence per prefix)
-- - Uppercase-only
-- - 7-digit padded sequence
-- - Sequence resets per (state,lga,type)
-- - Idempotent backfill for existing client/test records

begin;

create extension if not exists pgcrypto;

-- =========================================================
-- 1) Sequences table (one row per prefix)
-- =========================================================
create table if not exists public.generated_code_sequences (
  state_code text not null,
  lga_code text not null,
  type_code text not null,
  last_value bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (state_code, lga_code, type_code)
);

-- =========================================================
-- 2) Helpers
-- =========================================================
create or replace function public._letters3_or_error(raw text, label text)
returns text
language plpgsql
immutable
as $$
declare
  cleaned text;
begin
  cleaned := regexp_replace(upper(coalesce(raw, '')), '[^A-Z]', '', 'g');
  if length(cleaned) < 3 then
    raise exception '% code is missing/invalid: "%"', label, coalesce(raw, '');
  end if;
  return substring(cleaned from 1 for 3);
end;
$$;

create or replace function public._state_code3_or_error(state_name text)
returns text
language plpgsql
stable
as $$
declare
  s text;
  code text;
begin
  s := nullif(trim(coalesce(state_name, '')), '');
  if s is null then
    raise exception 'State is required to generate code';
  end if;

  if s = 'FCT' then s := 'Abuja FCT'; end if;

  -- Explicit mapping for unambiguous abbreviations.
  code := (case s
    when 'Abia' then 'ABI'
    when 'Adamawa' then 'ADA'
    when 'Akwa Ibom' then 'AKI'
    when 'Anambra' then 'ANB'
    when 'Bauchi' then 'BAU'
    when 'Bayelsa' then 'BAY'
    when 'Benue' then 'BEN'
    when 'Borno' then 'BOR'
    when 'Cross River' then 'CRS'
    when 'Delta' then 'DEL'
    when 'Ebonyi' then 'EBO'
    when 'Edo' then 'EDO'
    when 'Ekiti' then 'EKI'
    when 'Enugu' then 'ENU'
    when 'Abuja FCT' then 'ABU'
    when 'Gombe' then 'GMB'
    when 'Imo' then 'IMO'
    when 'Jigawa' then 'JIG'
    when 'Kaduna' then 'KAD'
    when 'Kano' then 'KAN'
    when 'Katsina' then 'KAT'
    when 'Kebbi' then 'KEB'
    when 'Kogi' then 'KOG'
    when 'Kwara' then 'KWA'
    when 'Lagos' then 'LAG'
    when 'Nasarawa' then 'NAS'
    when 'Niger' then 'NIG'
    when 'Ogun' then 'OGU'
    when 'Ondo' then 'OND'
    when 'Osun' then 'OSU'
    when 'Oyo' then 'OYO'
    when 'Plateau' then 'PLA'
    when 'Rivers' then 'RIV'
    when 'Sokoto' then 'SOK'
    when 'Taraba' then 'TAR'
    when 'Yobe' then 'YOB'
    when 'Zamfara' then 'ZAM'
    else null
  end);

  if code is null then
    raise exception 'Missing state abbreviation mapping for: %', s;
  end if;

  return code;
end;
$$;

create or replace function public._format_generated_code(state_code text, lga_code text, type_code text, seq bigint)
returns text
language sql
immutable
as $$
  select upper(state_code) || '-' || upper(lga_code) || '-' || upper(type_code) || '-' || lpad(seq::text, 7, '0');
$$;

-- =========================================================
-- 3) Concurrency-safe allocator (per state/lga/type)
-- =========================================================
create or replace function public.next_generated_code(
  state_name text,
  lga_name text,
  type_segment text default 'ALL'
)
returns text
language plpgsql
as $$
declare
  state_code text;
  lga_code text;
  type_code text;
  next_val bigint;
begin
  state_code := public._state_code3_or_error(state_name);

  -- LGA code: strict 3-letter extraction (errors if not possible).
  -- If you need explicit/official abbreviations per LGA, add a mapping table and swap this.
  lga_code := public._letters3_or_error(lga_name, 'LGA');

  type_code := public._letters3_or_error(coalesce(nullif(trim(type_segment), ''), 'ALL'), 'TYPE');

  insert into public.generated_code_sequences(state_code, lga_code, type_code, last_value, updated_at)
  values (state_code, lga_code, type_code, 1, now())
  on conflict (state_code, lga_code, type_code)
  do update set last_value = public.generated_code_sequences.last_value + 1, updated_at = now()
  returning last_value into next_val;

  return public._format_generated_code(state_code, lga_code, type_code, next_val);
end;
$$;

-- =========================================================
-- 4) Client-specific allocator (derives state/lga from provider profile)
-- =========================================================
create or replace function public.allocate_client_code(
  provider_user_id uuid,
  type_segment text default 'ALL'
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_state text;
  v_lga text;
begin
  if provider_user_id is null then
    raise exception 'provider_user_id is required';
  end if;

  -- Source-of-truth: business address table when present, fallback to users.
  select uba.state, uba.lga into v_state, v_lga
  from public.user_business_addresses uba
  where uba.user_id = provider_user_id;

  if v_state is null or v_lga is null then
    select u.state, u.lga into v_state, v_lga
    from public.users u
    where u.id = provider_user_id;
  end if;

  if v_state is null or nullif(trim(v_state), '') is null then
    raise exception 'Cannot allocate code: provider state is missing';
  end if;
  if v_lga is null or nullif(trim(v_lga), '') is null then
    raise exception 'Cannot allocate code: provider LGA is missing';
  end if;

  return public.next_generated_code(v_state, v_lga, type_segment);
end;
$$;

grant execute on function public.allocate_client_code(uuid, text) to authenticated;

-- =========================================================
-- 5) Enforce format/uniqueness and auto-generate on insert
-- =========================================================
do $$
begin
  if to_regclass('public.clients') is null then
    -- Some installs create `clients` lazily from the edge function.
    -- If it doesn't exist yet, we'll skip triggers/indexes.
    return;
  end if;

  -- Ensure uniqueness (raw + normalized). These are safe if already present.
  execute 'create unique index if not exists clients_clientid_uniq on public.clients (clientid)';
  execute 'create unique index if not exists clients_clientid_norm_uniq on public.clients ((lower(trim(clientid))))';

  -- Optional strict format validation (do not block historical rows during migration).
  -- If you want hard enforcement, switch to NOT VALID then validate.
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    where t.relname = 'clients'
      and c.conname = 'clients_clientid_format'
  ) then
    execute $$
      alter table public.clients
      add constraint clients_clientid_format
      check (clientid ~ '^[A-Z]{3}-[A-Z]{3}-[A-Z]{3}-\\d{7}$')
      not valid
    $$;
  end if;

  create or replace function public._clients_set_generated_code()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
  as $$
  begin
    -- Only allocate if missing or clearly a placeholder.
    if new.clientid is null
      or nullif(trim(new.clientid), '') is null
      or new.clientid !~ '^[A-Z]{3}-[A-Z]{3}-[A-Z]{3}-\\d{7}$'
    then
      new.clientid := public.allocate_client_code(new.provideruserid, 'ALL');
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
-- 6) One-time backfill (idempotent): update old client IDs + propagate to test_records
-- =========================================================
do $$
declare
  r record;
  old_id text;
  new_id text;
begin
  if to_regclass('public.clients') is null then return; end if;
  if to_regclass('public.test_records') is null then return; end if;

  -- Only touch rows that are NOT already in the required format.
  create temporary table if not exists _clientid_backfill_map(
    old_clientid text primary key,
    new_clientid text not null
  ) on commit drop;

  for r in
    select c.id, c.provideruserid, c.clientid
    from public.clients c
    where c.clientid is null
      or nullif(trim(c.clientid), '') is null
      or c.clientid !~ '^[A-Z]{3}-[A-Z]{3}-[A-Z]{3}-\\d{7}$'
    order by c.createdat asc nulls last
  loop
    old_id := coalesce(r.clientid, '');
    new_id := public.allocate_client_code(r.provideruserid, 'ALL');

    update public.clients
    set clientid = new_id,
        updatedat = now()
    where id = r.id;

    if old_id is not null and nullif(trim(old_id), '') is not null then
      insert into _clientid_backfill_map(old_clientid, new_clientid)
      values (old_id, new_id)
      on conflict (old_clientid) do nothing;
    end if;
  end loop;

  -- Propagate code changes to test_records.clientid so history remains linked.
  update public.test_records tr
  set clientid = m.new_clientid
  from _clientid_backfill_map m
  where tr.clientid = m.old_clientid;
end;
$$;

commit;
