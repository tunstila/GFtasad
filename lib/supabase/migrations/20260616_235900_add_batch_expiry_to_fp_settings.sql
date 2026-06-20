-- Adds batch_number + expiry_date to per-fieldProvider product settings
-- Canonical per-provider "product record" table: public.field_provider_commodity_settings
-- Safe for existing data (nullable columns).

alter table if exists public.field_provider_commodity_settings
  add column if not exists batch_number text null;

alter table if exists public.field_provider_commodity_settings
  add column if not exists expiry_date date null;

-- Basic consistency: trim whitespace in batch_number via a generated normalized column would be overkill.
-- We enforce trimming in the Flutter client and allow duplicates (manufacturer batch IDs can repeat).

create index if not exists idx_fp_commodity_settings_expiry_date
  on public.field_provider_commodity_settings (expiry_date);
