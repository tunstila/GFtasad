begin;

-- Add optional Malaria “Others” capture fields.
-- All nullable for backwards compatibility with existing records and offline queue payloads.

do $$
begin
  if to_regclass('public.test_records') is null then
    return;
  end if;

  alter table public.test_records add column if not exists other_symptoms_presented text null;
  alter table public.test_records add column if not exists act_given_option text null;
  alter table public.test_records add column if not exists other_act_given text null;
end $$;

commit;
