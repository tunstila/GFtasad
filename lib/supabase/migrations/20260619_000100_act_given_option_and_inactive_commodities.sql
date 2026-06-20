begin;

-- 1) Malaria: ACT Given options (TopMal | Others | None)
-- Keep legacy boolean column `actGiven` for backwards compatibility with existing code/reports.
-- New writes should prefer `actGivenOption`.

do $$
begin
  if to_regclass('public.test_records') is not null then
    alter table public.test_records add column if not exists "actGivenOption" text null;
    alter table public.test_records add column if not exists actgivenoption text null;
  end if;
end $$;

-- 2) Inventory: deactivate specific catalog item (do not delete history)
-- Add a soft-delete flag on commodities and enforce it in RPCs.

do $$
begin
  if to_regclass('public.commodities') is not null then
    alter table public.commodities add column if not exists is_active boolean not null default true;
    alter table public.commodities add column if not exists isactive boolean not null default true;

    -- Deactivate TB Screening Form (case-insensitive match). Historical movements remain intact.
    update public.commodities
      set is_active = false,
          isactive = false,
          "updatedAt" = now(),
          updatedat = now()
      where lower(name) = lower('TB Screening Form');
  end if;
end $$;

commit;
