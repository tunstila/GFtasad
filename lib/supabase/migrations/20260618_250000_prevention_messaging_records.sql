begin;

create extension if not exists pgcrypto;

-- =========================================================
-- Prevention Messaging: first-class intervention workflow
-- Stored in a dedicated table so it does NOT affect diagnostic test metrics
-- (e.g. "Tests Today" which is based on public.test_records).
-- =========================================================

create table if not exists public.prevention_messaging_records (
  id uuid primary key default gen_random_uuid(),
  userId uuid not null references public.users(id) on delete restrict,

  clientName text not null,
  age integer not null,
  phoneNumber text not null,
  clientId text not null,

  sex text not null,
  clientGroups text[] not null,
  firstTimeVisit boolean not null,
  referredFrom text not null,

  educatedOnHivPrevention boolean not null,
  educatedOnHivTestingOptions boolean not null,
  educatedOnMalariaPreventionTreatment boolean not null,

  createdAt timestamptz not null default now(),
  updatedAt timestamptz not null default now()
);

create index if not exists idx_pmr_user_id on public.prevention_messaging_records (userId);
create index if not exists idx_pmr_created_at on public.prevention_messaging_records (createdAt);
create index if not exists idx_pmr_user_created_at on public.prevention_messaging_records (userId, createdAt);
create index if not exists idx_pmr_client_id on public.prevention_messaging_records (clientId);

-- RLS: provider-scoped write, adminish read
alter table public.prevention_messaging_records enable row level security;

drop policy if exists pmr_select_scoped on public.prevention_messaging_records;
create policy pmr_select_scoped
on public.prevention_messaging_records
for select
to authenticated
using (
  userId = auth.uid()
  or exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and u.role in ('admin','sfhTeam','superAdmin')
  )
);

drop policy if exists pmr_insert_own on public.prevention_messaging_records;
create policy pmr_insert_own
on public.prevention_messaging_records
for insert
to authenticated
with check (
  userId = auth.uid()
  and exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and u.role in ('fieldProvider','superAdmin')
  )
);

-- Intentionally no UPDATE/DELETE policies from the client.

-- Keep updatedAt fresh.
create or replace function public._touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new."updatedAt" := now();
  return new;
end;
$$;

drop trigger if exists trg_pmr_touch_updated_at on public.prevention_messaging_records;
create trigger trg_pmr_touch_updated_at
before update on public.prevention_messaging_records
for each row execute function public._touch_updated_at();

-- =========================================================
-- RPC: create a prevention messaging record (server-validated owner)
-- =========================================================
create or replace function public.create_prevention_messaging_record(
  p_client_id text,
  p_client_name text,
  p_age integer,
  p_phone_number text,
  p_sex text,
  p_client_groups text[],
  p_first_time_visit boolean,
  p_referred_from text,
  p_educated_on_hiv_prevention boolean,
  p_educated_on_hiv_testing_options boolean,
  p_educated_on_malaria_prevention_treatment boolean
)
returns public.prevention_messaging_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_role text;
  v_row public.prevention_messaging_records;
  v_client_id text;
  v_client_name text;
  v_phone text;
  v_sex text;
  v_ref text;
  v_groups text[];
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select role into v_role from public.users where id = v_uid;
  if coalesce(v_role,'') not in ('fieldProvider','superAdmin') then
    raise exception 'Only fieldProvider can create prevention messaging records';
  end if;

  v_client_id := upper(trim(coalesce(p_client_id,'')));
  v_client_name := trim(coalesce(p_client_name,''));
  v_phone := trim(coalesce(p_phone_number,''));
  v_sex := trim(coalesce(p_sex,''));
  v_ref := trim(coalesce(p_referred_from,''));
  v_groups := p_client_groups;

  if v_client_id = '' then raise exception 'Client code is required'; end if;
  if v_client_name = '' then raise exception 'Client name is required'; end if;
  if p_age is null or p_age < 0 or p_age > 120 then raise exception 'Age must be between 0 and 120'; end if;
  if v_phone = '' then raise exception 'Client telephone number is required'; end if;
  if v_sex = '' then raise exception 'Sex is required'; end if;
  if v_groups is null or array_length(v_groups, 1) is null then raise exception 'Select at least one client group'; end if;
  if v_ref = '' then raise exception 'Referred from is required'; end if;

  insert into public.prevention_messaging_records(
    userId,
    clientName,
    age,
    phoneNumber,
    clientId,
    sex,
    clientGroups,
    firstTimeVisit,
    referredFrom,
    educatedOnHivPrevention,
    educatedOnHivTestingOptions,
    educatedOnMalariaPreventionTreatment
  )
  values(
    v_uid,
    v_client_name,
    p_age,
    v_phone,
    v_client_id,
    v_sex,
    v_groups,
    p_first_time_visit,
    v_ref,
    p_educated_on_hiv_prevention,
    p_educated_on_hiv_testing_options,
    p_educated_on_malaria_prevention_treatment
  )
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.create_prevention_messaging_record(
  text, text, integer, text, text, text[], boolean, text, boolean, boolean, boolean
) to authenticated;

-- =========================================================
-- RPC: count my Prevention Messaging records today (for Home tile)
-- =========================================================
create or replace function public.count_my_prevention_messaging_today()
returns bigint
language sql
stable
as $$
  select count(*)::bigint
  from public.prevention_messaging_records
  where "userId" = auth.uid()
    and "createdAt"::date = current_date;
$$;

grant execute on function public.count_my_prevention_messaging_today() to authenticated;

commit;
