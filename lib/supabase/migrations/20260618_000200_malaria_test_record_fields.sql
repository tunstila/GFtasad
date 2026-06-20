begin;

-- Extend test_records to support the expanded Malaria form fields.
-- All columns are nullable for backwards compatibility with existing records.

do $$
begin
  if to_regclass('public.test_records') is null then
    return;
  end if;

  alter table public.test_records add column if not exists age integer null;
  alter table public.test_records add column if not exists phoneNumber text null;
  alter table public.test_records add column if not exists clientAddress text null;

  -- Malaria form additions
  alter table public.test_records add column if not exists clientGroups text[] null;
  alter table public.test_records add column if not exists symptomsPresented text[] null;
  alter table public.test_records add column if not exists firstTimeVisit boolean null;
  alter table public.test_records add column if not exists referredFrom text null;
  alter table public.test_records add column if not exists otherReferralSource text null;
  alter table public.test_records add column if not exists mRDTResult text null;
  alter table public.test_records add column if not exists referralForDangerSigns boolean null;
  alter table public.test_records add column if not exists dangerSignsReferralFacility text null;
end $$;

commit;
