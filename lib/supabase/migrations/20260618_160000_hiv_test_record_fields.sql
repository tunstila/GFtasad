begin;

-- Extend test_records to support the expanded HIV recording form.
-- All columns are nullable for backwards compatibility with existing records.
-- NOTE: This migration intentionally DOES NOT touch client code generation logic.

do $$
begin
  if to_regclass('public.test_records') is null then
    return;
  end if;

  -- HIV client intake / history
  alter table public.test_records add column if not exists hivPreviousTesting text null;
  alter table public.test_records add column if not exists htsType text null;

  -- HIVST details (shown only when HTS Type = HIVST)
  alter table public.test_records add column if not exists hivstKitType text null;
  alter table public.test_records add column if not exists hivstServiceDeliveryModel text null;

  -- HIV result (Reactive / Non-reactive)
  alter table public.test_records add column if not exists hivTestResult text null;

  -- TB screening (structured, multi-select)
  alter table public.test_records add column if not exists tbSymptomsPresented text[] null;

  -- Referral (structured, multi-select)
  alter table public.test_records add column if not exists referralServices text[] null;
  alter table public.test_records add column if not exists otherReferralService text null;
end $$;

commit;
