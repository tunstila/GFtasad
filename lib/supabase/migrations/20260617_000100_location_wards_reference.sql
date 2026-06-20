-- Location reference: Wards (cascaded from State + LGA)
--
-- Adds:
-- - public.ng_wards: reference table (state, lga, ward_name)
-- - Validation trigger on public.user_business_addresses to prevent saving a ward
--   that does not belong to the selected LGA (when ward is provided)
--
-- Notes:
-- - We keep user profiles backwards-compatible by continuing to store state/lga/ward as TEXT.
-- - Validation is enforced only when a ward value is non-null/non-empty.
-- - If the reference table has no rows for a given state+lga yet, ward can be NULL.

create extension if not exists pgcrypto;

-- Some environments may not have the baseline tables applied yet.
-- Ensure the business address table exists before adding triggers/policies.
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

create table if not exists public.ng_wards (
  id uuid primary key default gen_random_uuid(),
  state text not null,
  lga text not null,
  ward_name text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_ng_wards_state_lga on public.ng_wards (state, lga);
create index if not exists idx_ng_wards_ward_name on public.ng_wards (ward_name);

-- Avoid duplicates (case/whitespace-insensitive) for the same State+LGA.
create unique index if not exists uq_ng_wards_state_lga_ward_norm
on public.ng_wards (state, lga, (lower(trim(ward_name))));

alter table public.ng_wards enable row level security;

-- Any signed-in user can read wards.
drop policy if exists ng_wards_select_all on public.ng_wards;
create policy ng_wards_select_all
on public.ng_wards
for select
to authenticated
using (true);

-- Optional: only super admins can manage ward reference data.
-- If you want to allow your own admin roles, adjust this predicate.
drop policy if exists ng_wards_write_superadmin_only on public.ng_wards;
create policy ng_wards_write_superadmin_only
on public.ng_wards
for all
to authenticated
using (
  exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and (u.role = 'superAdmin' or coalesce(nullif(trim(u.adminscope), ''), 'none') = 'full')
  )
)
with check (
  exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and (u.role = 'superAdmin' or coalesce(nullif(trim(u.adminscope), ''), 'none') = 'full')
  )
);

-- -----------------------------
-- Validation: user_business_addresses.ward must belong to selected LGA.
-- -----------------------------
create or replace function public._validate_business_address_ward()
returns trigger
language plpgsql
as $$
declare
  v_ward text;
  v_exists boolean;
begin
  v_ward := nullif(trim(coalesce(new.ward, '')), '');
  if v_ward is null then
    return new;
  end if;

  select exists(
    select 1
    from public.ng_wards w
    where w.state = new.state
      and w.lga = new.lga
      and lower(trim(w.ward_name)) = lower(trim(v_ward))
  ) into v_exists;

  if not v_exists then
    raise exception 'Invalid ward for selected LGA';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validate_business_address_ward on public.user_business_addresses;
create trigger trg_validate_business_address_ward
before insert or update on public.user_business_addresses
for each row
execute function public._validate_business_address_ward();

-- -----------------------------
-- RLS hardening: user_business_addresses should be user-scoped.
-- (If your project already has these policies, this is idempotent.)
-- -----------------------------
alter table public.user_business_addresses enable row level security;

drop policy if exists user_business_addresses_select_own on public.user_business_addresses;
create policy user_business_addresses_select_own
on public.user_business_addresses
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists user_business_addresses_insert_own on public.user_business_addresses;
create policy user_business_addresses_insert_own
on public.user_business_addresses
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists user_business_addresses_update_own on public.user_business_addresses;
create policy user_business_addresses_update_own
on public.user_business_addresses
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());
