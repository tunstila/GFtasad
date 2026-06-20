-- Stock Alerts generation hardening (production-safe)
--
-- Fixes:
-- - stock_movements / field_provider_commodity_settings column casing differences
-- - reconcile_my_stock_alerts() failing when stock_movements uses camelCase
--
-- This migration is idempotent and safe to re-run.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------
-- 1) Patch stock_alerts trigger to not reference columns directly
-- ---------------------------------------------------------
create or replace function public._on_stock_movement_change_stock_alerts()
returns trigger
language plpgsql
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

drop trigger if exists trg_stock_movements_stock_alerts on public.stock_movements;
create trigger trg_stock_movements_stock_alerts
after insert or update or delete on public.stock_movements
for each row execute function public._on_stock_movement_change_stock_alerts();

-- ---------------------------------------------------------
-- 2) Patch reconcile_my_stock_alerts() to be casing-safe
-- ---------------------------------------------------------
create or replace function public.reconcile_my_stock_alerts()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  b record;
  v_uid uuid;
  v_batch text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    return;
  end if;

  -- Low/out of stock: scan provider+commodity pairs for this user.
  for r in (
    select distinct
      coalesce(
        nullif(to_jsonb(sm)->>'userId', '')::uuid,
        nullif(to_jsonb(sm)->>'userid', '')::uuid,
        nullif(to_jsonb(sm)->>'user_id', '')::uuid
      ) as field_provider_id,
      coalesce(
        nullif(to_jsonb(sm)->>'commodityId', '')::uuid,
        nullif(to_jsonb(sm)->>'commodityid', '')::uuid,
        nullif(to_jsonb(sm)->>'commodity_id', '')::uuid
      ) as commodity_id
    from public.stock_movements sm
    where coalesce(
        nullif(to_jsonb(sm)->>'userId', '')::uuid,
        nullif(to_jsonb(sm)->>'userid', '')::uuid,
        nullif(to_jsonb(sm)->>'user_id', '')::uuid
      ) = v_uid
      and coalesce(
        nullif(to_jsonb(sm)->>'commodityId', '')::uuid,
        nullif(to_jsonb(sm)->>'commodityid', '')::uuid,
        nullif(to_jsonb(sm)->>'commodity_id', '')::uuid
      ) is not null
    union
    select distinct s.field_provider_id, s.commodity_id
    from public.field_provider_commodity_settings s
    where s.field_provider_id = v_uid
  ) loop
    if r.field_provider_id is not null and r.commodity_id is not null then
      perform public._evaluate_stock_levels(r.field_provider_id, r.commodity_id);
    end if;
  end loop;

  -- Near expiry: scan known batches for this user.
  for b in (
    select distinct
      coalesce(
        nullif(to_jsonb(sm)->>'userId', '')::uuid,
        nullif(to_jsonb(sm)->>'userid', '')::uuid,
        nullif(to_jsonb(sm)->>'user_id', '')::uuid
      ) as field_provider_id,
      coalesce(
        nullif(to_jsonb(sm)->>'commodityId', '')::uuid,
        nullif(to_jsonb(sm)->>'commodityid', '')::uuid,
        nullif(to_jsonb(sm)->>'commodity_id', '')::uuid
      ) as commodity_id,
      nullif(trim(coalesce(
        to_jsonb(sm)->>'batchNumber',
        to_jsonb(sm)->>'batchnumber',
        to_jsonb(sm)->>'batch_number'
      )), '') as batch_number
    from public.stock_movements sm
    where coalesce(
        nullif(to_jsonb(sm)->>'userId', '')::uuid,
        nullif(to_jsonb(sm)->>'userid', '')::uuid,
        nullif(to_jsonb(sm)->>'user_id', '')::uuid
      ) = v_uid
      and coalesce(
        nullif(to_jsonb(sm)->>'expiryDate', '')::date,
        nullif(to_jsonb(sm)->>'expirydate', '')::date,
        nullif(to_jsonb(sm)->>'expiry_date', '')::date
      ) is not null
      and nullif(trim(coalesce(
        to_jsonb(sm)->>'batchNumber',
        to_jsonb(sm)->>'batchnumber',
        to_jsonb(sm)->>'batch_number'
      )), '') is not null
  ) loop
    v_batch := b.batch_number;
    if b.field_provider_id is not null and b.commodity_id is not null and v_batch is not null then
      perform public._evaluate_near_expiry(b.field_provider_id, b.commodity_id, v_batch);
    end if;
  end loop;
end;
$$;

revoke all on function public.reconcile_my_stock_alerts() from public;
grant execute on function public.reconcile_my_stock_alerts() to authenticated;

-- Optional: one-time backfill for the current caller only (safe to re-run).
-- Note: When run from migration, auth.uid() is null, so this is a no-op.
select public.reconcile_my_stock_alerts();
