-- Fix: stock_alerts generation failing under RLS when field providers write stock_movements.
--
-- Symptom:
--   PostgrestException: new row violates row-level security policy for table "stock_alerts"
--
-- Root cause:
--   `public.stock_alerts` intentionally has NO INSERT policy.
--   Alerts are created by DB functions triggered by `stock_movements` and settings changes.
--   Those trigger functions must run as a privileged role; otherwise inserts into `stock_alerts`
--   are evaluated under the calling user and are blocked by RLS.
--
-- This migration makes the trigger functions SECURITY DEFINER and fixes search_path.
-- It is safe to run multiple times.

begin;

create or replace function public._on_stock_movement_change_stock_alerts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid;
  c uuid;
  old_u uuid;
  old_c uuid;
  old_b text;
  new_b text;
  b text;
begin
  -- Support: userId/userid/user_id
  u := coalesce(
    nullif(to_jsonb(new)->>'userId', '')::uuid,
    nullif(to_jsonb(new)->>'userid', '')::uuid,
    nullif(to_jsonb(new)->>'user_id', '')::uuid,
    nullif(to_jsonb(old)->>'userId', '')::uuid,
    nullif(to_jsonb(old)->>'userid', '')::uuid,
    nullif(to_jsonb(old)->>'user_id', '')::uuid
  );

  -- Support: commodityId/commodityid/commodity_id
  c := coalesce(
    nullif(to_jsonb(new)->>'commodityId', '')::uuid,
    nullif(to_jsonb(new)->>'commodityid', '')::uuid,
    nullif(to_jsonb(new)->>'commodity_id', '')::uuid,
    nullif(to_jsonb(old)->>'commodityId', '')::uuid,
    nullif(to_jsonb(old)->>'commodityid', '')::uuid,
    nullif(to_jsonb(old)->>'commodity_id', '')::uuid
  );

  old_u := coalesce(
    nullif(to_jsonb(old)->>'userId', '')::uuid,
    nullif(to_jsonb(old)->>'userid', '')::uuid,
    nullif(to_jsonb(old)->>'user_id', '')::uuid
  );

  old_c := coalesce(
    nullif(to_jsonb(old)->>'commodityId', '')::uuid,
    nullif(to_jsonb(old)->>'commodityid', '')::uuid,
    nullif(to_jsonb(old)->>'commodity_id', '')::uuid
  );

  -- If ownership changed, re-evaluate old pair too
  if old_u is not null and old_c is not null and (old_u <> u or old_c <> c) then
    perform public._evaluate_stock_levels(old_u, old_c);
  end if;

  if u is not null and c is not null then
    perform public._evaluate_stock_levels(u, c);
  end if;

  -- Near-expiry: evaluate best-effort when batch fields change.
  old_b := nullif(trim(coalesce(
    to_jsonb(old)->>'batchNumber',
    to_jsonb(old)->>'batchnumber',
    to_jsonb(old)->>'batch_number'
  )), '');

  new_b := nullif(trim(coalesce(
    to_jsonb(new)->>'batchNumber',
    to_jsonb(new)->>'batchnumber',
    to_jsonb(new)->>'batch_number'
  )), '');

  b := coalesce(new_b, old_b);

  if u is not null and c is not null and b is not null then
    perform public._evaluate_near_expiry(u, c, b);
  end if;

  if u is not null and c is not null and old_b is not null and new_b is not null and old_b <> new_b then
    perform public._evaluate_near_expiry(u, c, old_b);
  end if;

  return coalesce(new, old);
end;
$$;

create or replace function public._on_minimum_threshold_change_stock_alerts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._evaluate_stock_levels(new.field_provider_id, new.commodity_id);
  return new;
end;
$$;

-- Re-bind triggers to ensure they reference the patched functions.
drop trigger if exists trg_stock_movements_stock_alerts on public.stock_movements;
create trigger trg_stock_movements_stock_alerts
after insert or update or delete on public.stock_movements
for each row execute function public._on_stock_movement_change_stock_alerts();

drop trigger if exists trg_fp_settings_stock_alerts on public.field_provider_commodity_settings;
create trigger trg_fp_settings_stock_alerts
after insert or update of minimum_quantity on public.field_provider_commodity_settings
for each row execute function public._on_minimum_threshold_change_stock_alerts();

commit;
