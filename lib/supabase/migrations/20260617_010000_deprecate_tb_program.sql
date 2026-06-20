begin;

-- TB program deprecation (safe production cleanup)
--
-- Goal: prevent *new* TB test records while preserving any historical TB rows.
-- We do this with a NOT VALID CHECK constraint so existing rows are not scanned
-- (and are not rejected), but future INSERT/UPDATE attempts are blocked.

-- Postgres does not support `ADD CONSTRAINT IF NOT EXISTS`.
-- We therefore guard the constraint creation so the migration can be safely
-- re-run (e.g., from Supabase Dashboard SQL Editor).
--
-- NOTE: Supabase SQL Editor runs the whole script; this DO block is safe.
do $$
begin
  -- Only attempt if the table exists
  if to_regclass('public.test_records') is null then
    return;
  end if;

  -- If the constraint already exists, do nothing.
  if exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'test_records'
      and c.conname = 'test_records_program_not_tb'
  ) then
    return;
  end if;

  -- Create the constraint as NOT VALID so historical rows are preserved.
  execute 'alter table public.test_records add constraint test_records_program_not_tb check (program <> ''tb'') not valid';
end $$;

-- Optional hardening: make sure the same rule also blocks common variants.
-- Uncomment if you want to disallow these too.
-- do $$
-- begin
--   if to_regclass('public.test_records') is null then return; end if;
--   if exists (
--     select 1
--     from pg_constraint c
--     join pg_class t on t.oid = c.conrelid
--     join pg_namespace n on n.oid = t.relnamespace
--     where n.nspname = 'public'
--       and t.relname = 'test_records'
--       and c.conname = 'test_records_program_not_tb'
--   ) then
--     execute 'alter table public.test_records drop constraint test_records_program_not_tb';
--   end if;
--   execute 'alter table public.test_records add constraint test_records_program_not_tb check (lower(program) not in (''tb'',''tuberculosis'')) not valid';
-- end $$;

commit;
