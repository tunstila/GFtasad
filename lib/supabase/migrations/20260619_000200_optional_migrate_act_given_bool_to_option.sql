-- OPTIONAL (run only after business sign-off): migrate legacy boolean actGiven into actGivenOption.
--
-- IMPORTANT: actGiven=true does NOT specify which ACT brand was given.
-- This script therefore maps:
--   actGiven=false -> 'None' (unambiguous)
--   actGiven=true  -> 'Others' (best-effort default; adjust if you prefer 'TopMal')
--
-- This preserves the legacy boolean column for audits and historical dashboards.

begin;

do $$
begin
  if to_regclass('public.test_records') is null then
    return;
  end if;

  -- Ensure column exists (idempotent)
  alter table public.test_records add column if not exists "actGivenOption" text null;
  alter table public.test_records add column if not exists actgivenoption text null;

  -- Unambiguous migration: only fill where option is currently null/blank.
  update public.test_records
    set "actGivenOption" = 'None'
  where ("actGivenOption" is null or nullif(trim("actGivenOption"), '') is null)
    and coalesce(actGiven, false) = false
    and actGiven is not null;

  update public.test_records
    set "actGivenOption" = 'Others'
  where ("actGivenOption" is null or nullif(trim("actGivenOption"), '') is null)
    and actGiven = true;

  -- Lowercase schema variant
  update public.test_records
    set actgivenoption = 'None'
  where (actgivenoption is null or nullif(trim(actgivenoption), '') is null)
    and coalesce(actgiven, false) = false
    and actgiven is not null;

  update public.test_records
    set actgivenoption = 'Others'
  where (actgivenoption is null or nullif(trim(actgivenoption), '') is null)
    and actgiven = true;
end $$;

commit;
