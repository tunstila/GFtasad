-- Stock Alerts patch: support camelCase/legacy stock_movements columns
--
-- Fixes cases where stock_movements columns are named "userId"/"commodityId" (camelCase)
-- instead of userid/commodityid (lowercase). Without this, triggers may not fire and
-- quantity calculations may always read 0.

-- =========================================================
-- 1) Quantity + batch helper functions (make them column-name resilient)
-- =========================================================

create or replace function public._stock_quantity(p_field_provider_id uuid, p_commodity_id uuid)
returns integer
language sql
stable
as $$
  select coalesce(sum(
    case
      when lower(coalesce(type, '')) = 'add' then quantity
      else -quantity
    end
  ), 0)::integer
  from public.stock_movements sm
  where coalesce(
      (nullif(to_jsonb(sm)->>'userId', '')::uuid),
      (nullif(to_jsonb(sm)->>'userid', '')::uuid),
      (nullif(to_jsonb(sm)->>'user_id', '')::uuid)
    ) = p_field_provider_id
    and coalesce(
      (nullif(to_jsonb(sm)->>'commodityId', '')::uuid),
      (nullif(to_jsonb(sm)->>'commodityid', '')::uuid),
      (nullif(to_jsonb(sm)->>'commodity_id', '')::uuid)
    ) = p_commodity_id;
$$;

create or replace function public._batch_expiry_date(p_field_provider_id uuid, p_commodity_id uuid, p_batch_number text)
returns date
language sql
stable
as $$
  select max(coalesce(
    nullif(to_jsonb(sm)->>'expiryDate', '')::date,
    nullif(to_jsonb(sm)->>'expirydate', '')::date,
    nullif(to_jsonb(sm)->>'expiry_date', '')::date
  ))::date
  from public.stock_movements sm
  where coalesce(
      (nullif(to_jsonb(sm)->>'userId', '')::uuid),
      (nullif(to_jsonb(sm)->>'userid', '')::uuid),
      (nullif(to_jsonb(sm)->>'user_id', '')::uuid)
    ) = p_field_provider_id
    and coalesce(
      (nullif(to_jsonb(sm)->>'commodityId', '')::uuid),
      (nullif(to_jsonb(sm)->>'commodityid', '')::uuid),
      (nullif(to_jsonb(sm)->>'commodity_id', '')::uuid)
    ) = p_commodity_id
    and coalesce(
        nullif(trim(coalesce(
          to_jsonb(sm)->>'batchNumber',
          to_jsonb(sm)->>'batchnumber',
          to_jsonb(sm)->>'batch_number'
        )), ''),
        ''
      ) = coalesce(nullif(trim(p_batch_number), ''), '')
    and coalesce(
      nullif(to_jsonb(sm)->>'expiryDate', '')::date,
      nullif(to_jsonb(sm)->>'expirydate', '')::date,
      nullif(to_jsonb(sm)->>'expiry_date', '')::date
    ) is not null;
$$;

-- =========================================================
-- 2) Trigger function: read IDs from either casing
-- =========================================================

create or replace function public._on_stock_movement_change_stock_alerts()
returns trigger
language plpgsql
as $$
declare
  u uuid;
  c uuid;
  b text;
  old_u uuid;
  old_c uuid;
  old_b text;
  new_b text;
begin
  -- Field provider + commodity IDs (support multiple schemas)
  u := coalesce(
    nullif(to_jsonb(new)->>'userId', '')::uuid,
    nullif(to_jsonb(new)->>'userid', '')::uuid,
    nullif(to_jsonb(new)->>'user_id', '')::uuid,
    nullif(to_jsonb(old)->>'userId', '')::uuid,
    nullif(to_jsonb(old)->>'userid', '')::uuid,
    nullif(to_jsonb(old)->>'user_id', '')::uuid
  );

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

  -- Near-expiry (batch fields)
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

-- Ensure the trigger is bound to the (patched) function
drop trigger if exists trg_stock_movements_stock_alerts on public.stock_movements;
create trigger trg_stock_movements_stock_alerts
after insert or update or delete on public.stock_movements
for each row execute function public._on_stock_movement_change_stock_alerts();

-- =========================================================
-- 3) Reconcile RPC: scan provider+commodity pairs across schemas
-- =========================================================

create or replace function public.reconcile_stock_alerts()
returns void
language plpgsql
as $$
declare
  r record;
  b record;
  v_batch text;
begin
  -- 1) Low/out of stock: scan all provider+commodity pairs with any movement or settings.
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
      ) is not null
      and coalesce(
        nullif(to_jsonb(sm)->>'commodityId', '')::uuid,
        nullif(to_jsonb(sm)->>'commodityid', '')::uuid,
        nullif(to_jsonb(sm)->>'commodity_id', '')::uuid
      ) is not null
    union
    select distinct s.field_provider_id, s.commodity_id
    from public.field_provider_commodity_settings s
  ) loop
    perform public._evaluate_stock_levels(r.field_provider_id, r.commodity_id);
  end loop;

  -- 2) Near expiry: scan known batches with expiry dates.
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
        nullif(to_jsonb(sm)->>'expiryDate', '')::date,
        nullif(to_jsonb(sm)->>'expirydate', '')::date,
        nullif(to_jsonb(sm)->>'expiry_date', '')::date
      ) is not null
      and nullif(trim(coalesce(
        to_jsonb(sm)->>'batchNumber',
        to_jsonb(sm)->>'batchnumber',
        to_jsonb(sm)->>'batch_number'
      )), '') is not null
      and coalesce(
        nullif(to_jsonb(sm)->>'userId', '')::uuid,
        nullif(to_jsonb(sm)->>'userid', '')::uuid,
        nullif(to_jsonb(sm)->>'user_id', '')::uuid
      ) is not null
      and coalesce(
        nullif(to_jsonb(sm)->>'commodityId', '')::uuid,
        nullif(to_jsonb(sm)->>'commodityid', '')::uuid,
        nullif(to_jsonb(sm)->>'commodity_id', '')::uuid
      ) is not null
  ) loop
    v_batch := b.batch_number;
    if v_batch is not null then
      perform public._evaluate_near_expiry(b.field_provider_id, b.commodity_id, v_batch);
    end if;
  end loop;
end;
$$;

-- Optional: run a one-time reconciliation after patching.
select public.reconcile_stock_alerts();
