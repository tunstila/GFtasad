-- Prevention Messaging records (offline-first capture + sync)
--
-- This migration is idempotent and follows the project's lowercase column style
-- used by `clients` and the id_management edge function.

begin;

create extension if not exists pgcrypto;

create table if not exists public.prevention_messaging_records (
  id uuid primary key default gen_random_uuid(),
  userid uuid not null references public.users(id) on delete restrict,

  clientname text not null,
  age integer not null,
  phonenumber text not null,
  clientid text not null,
  sex text not null,

  clientgroups text[] not null default '{}'::text[],
  firsttimevisit boolean not null,

  referredfrom text not null,
  otherreferredfrom text null,

  educatedonhivprevention boolean not null,
  educatedonhivtestingoptions boolean not null,
  educatedonmalariaprevention boolean not null,

  referralservices text[] not null default '{}'::text[],
  otherreferralservice text null,
  referralfacility text null,

  syncstatus text not null default 'pending',
  createdat timestamptz not null default now(),
  updatedat timestamptz not null default now()
);

create index if not exists idx_prevention_messaging_userid on public.prevention_messaging_records (userid);
create index if not exists idx_prevention_messaging_createdat on public.prevention_messaging_records (createdat);
create index if not exists idx_prevention_messaging_clientid on public.prevention_messaging_records (clientid);

-- RLS
alter table public.prevention_messaging_records enable row level security;

-- Helper functions (safe to re-create; used across multiple tables in this repo).
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

drop policy if exists prevention_messaging_select_scoped on public.prevention_messaging_records;
create policy prevention_messaging_select_scoped on public.prevention_messaging_records
for select to authenticated
using (public.is_adminish() or userid = auth.uid());

drop policy if exists prevention_messaging_insert_own on public.prevention_messaging_records;
create policy prevention_messaging_insert_own on public.prevention_messaging_records
for insert to authenticated
with check (public.app_role() in ('fieldProvider','superAdmin') and userid = auth.uid());

drop policy if exists prevention_messaging_update_own on public.prevention_messaging_records;
create policy prevention_messaging_update_own on public.prevention_messaging_records
for update to authenticated
using (public.app_role() in ('fieldProvider','superAdmin') and userid = auth.uid())
with check (public.app_role() in ('fieldProvider','superAdmin') and userid = auth.uid());

commit;
