-- Production-safe hardening for offline test record sync.
--
-- Goals:
-- 1) Make malaria test records creatable without client_groups.
-- 2) Add client_generated_id idempotency key to prevent duplicate inserts on retries.

begin;

-- 1) Add idempotency key column (nullable for backwards compatibility)
DO $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'test_records' and column_name = 'client_generated_id'
  ) then
    alter table public.test_records add column client_generated_id text;
  end if;
end $$;

-- Unique constraint (partial index so existing nulls don't collide)
DO $$
begin
  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'test_records_client_generated_id_key'
  ) then
    create unique index test_records_client_generated_id_key
      on public.test_records (client_generated_id)
      where client_generated_id is not null;
  end if;
end $$;

-- Best-effort backfill: if your primary key is already a client UUID, make client_generated_id match it.
DO $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'test_records' and column_name = 'id'
  ) then
    update public.test_records
      set client_generated_id = coalesce(client_generated_id, id::text)
      where client_generated_id is null;
  end if;
end $$;

-- 2) Ensure client_groups is optional (kept for historical rows; not required for new malaria submissions)
DO $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'test_records' and column_name = 'client_groups'
  ) then
    -- Drop NOT NULL if present.
    begin
      alter table public.test_records alter column client_groups drop not null;
    exception when others then
      -- Ignore if it's already nullable.
      null;
    end;
  end if;
end $$;

commit;
