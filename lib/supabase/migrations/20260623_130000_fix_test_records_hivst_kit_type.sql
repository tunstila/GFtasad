begin;

-- Fix: ensure the column used by the live sync payload exists.
--
-- IMPORTANT CONTEXT
-- In Postgres, unquoted identifiers are folded to lowercase. Earlier migrations added
-- `hivstKitType` (camelCase) without quotes, which becomes the actual column:
--   hivstkittype
--
-- The Flutter offline sync uses the lowercased payload variant (`hivstkittype`).
-- If this column is missing in the deployed project, PostgREST throws:
--   Could not find the `hivstkittype` column of `test_records` in the schema cache
--
-- This migration is idempotent and safe to re-run.

do $$
declare
  v_has_lowercase boolean;
  v_has_snake boolean;
begin
  if to_regclass('public.test_records') is null then
    return;
  end if;

  select exists(
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'test_records'
      and column_name = 'hivstkittype'
  ) into v_has_lowercase;

  select exists(
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'test_records'
      and column_name = 'hivst_kit_type'
  ) into v_has_snake;

  -- Prefer the lowercased concatenated convention used by the existing production schema
  -- (e.g., clientId -> clientid, createdAt -> createdat), and by the app's sync payload.
  if not v_has_lowercase then
    -- If the project already has a snake_case column, do NOT create a competing duplicate.
    -- Instead, create a lightweight compatibility column that mirrors the snake_case value.
    if v_has_snake then
      alter table public.test_records add column hivstkittype text null;
      -- Backfill from snake_case when present.
      update public.test_records set hivstkittype = hivst_kit_type where hivstkittype is null;
    else
      alter table public.test_records add column hivstkittype text null;
    end if;
  end if;

  -- If the project only has the lowercased column but not snake_case, we intentionally
  -- do NOT create hivst_kit_type to avoid duplicate sources of truth.

  -- Best-effort: ask PostgREST to reload schema cache so the new column is visible immediately.
  perform pg_notify('pgrst', 'reload schema');
end $$;

commit;
