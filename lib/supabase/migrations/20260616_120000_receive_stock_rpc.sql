-- FieldProvider inventory: atomic stock receipt against existing catalog products
-- Adds a transaction-safe RPC:
--   public.receive_fieldprovider_inventory_stock(product_id, quantity_received, expiry_date, batch_number, unit_override)
--
-- Canonical tables in this app:
-- - public.commodities (master/system product catalog)
-- - public.stock_movements (source-of-truth transaction history; inventory qty is derived by SUM)
-- - public.field_provider_commodity_settings (per-provider settings like minimum threshold)

create extension if not exists pgcrypto;

-- Ensure traceability columns exist on stock_movements (idempotent)
alter table if exists public.stock_movements add column if not exists "batchNumber" text null;
alter table if exists public.stock_movements add column if not exists "expiryDate" date null;
alter table if exists public.stock_movements add column if not exists "createdBy" uuid null references public.users(id) on delete set null;

-- Most environments in this repo use lowercase (unquoted) column names.
-- PostgREST will error at runtime if we reference a column that does not exist.
-- So we also ensure lowercase variants exist.
alter table if exists public.stock_movements add column if not exists batchnumber text null;
alter table if exists public.stock_movements add column if not exists expirydate date null;
alter table if exists public.stock_movements add column if not exists createdby uuid null references public.users(id) on delete set null;

-- Optional: allow per-provider unit override without mutating the global catalog
alter table if exists public.field_provider_commodity_settings add column if not exists unit_override text null;
create index if not exists idx_fp_commodity_settings_unit_override on public.field_provider_commodity_settings (unit_override);

-- RPC: receive stock (atomic, scoped to auth.uid())
create or replace function public.receive_fieldprovider_inventory_stock(
  product_id uuid,
  quantity_received integer,
  expiry_date date,
  batch_number text,
  unit_override text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_uid uuid;
  v_role text;
  v_exists boolean;
  v_sm public.stock_movements%rowtype;
  v_qty integer;
  v_batch text;
  v_unit text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select role into v_role from public.users where id = v_uid;
  if coalesce(v_role, '') <> 'fieldProvider' then
    raise exception 'Only fieldProvider can receive inventory stock';
  end if;

  if quantity_received is null or quantity_received <= 0 then
    raise exception 'quantity_received must be > 0';
  end if;

  v_batch := nullif(trim(coalesce(batch_number, '')), '');
  if v_batch is null then
    raise exception 'batch_number is required';
  end if;

  if expiry_date is null then
    raise exception 'expiry_date is required';
  end if;

  select exists(select 1 from public.commodities c where c.id = product_id) into v_exists;
  if not v_exists then
    raise exception 'Selected product does not exist in system catalog';
  end if;

  v_unit := nullif(trim(coalesce(unit_override, '')), '');

  -- Ensure settings row exists (this also supports low-stock notification engine).
  insert into public.field_provider_commodity_settings(field_provider_id, commodity_id, unit_override)
  values (v_uid, product_id, v_unit)
  on conflict (field_provider_id, commodity_id)
  do update set unit_override = coalesce(excluded.unit_override, public.field_provider_commodity_settings.unit_override);

  -- Record stock movement as the canonical source-of-truth.
  insert into public.stock_movements(
    id,
    commodityid,
    userid,
    type,
    quantity,
    reason,
    notes,
    batchnumber,
    expirydate,
    createdby,
    syncstatus,
    createdat
  )
  values (
    gen_random_uuid(),
    product_id,
    v_uid,
    'add',
    quantity_received,
    'receive',
    'Received via Inventory',
    v_batch,
    expiry_date,
    v_uid,
    'synced',
    now()
  )
  returning * into v_sm;

  -- Return the updated quantity (derived) after inserting the movement.
  -- Prefer the canonical helper if present.
  begin
    v_qty := public._stock_quantity(v_uid, product_id);
  exception when undefined_function then
    select coalesce(sum(case when lower(coalesce(type,''))='add' then quantity else -quantity end),0)::integer
    into v_qty
    from public.stock_movements
    where userid = v_uid and commodityid = product_id;
  end;

  return jsonb_build_object(
    'movement', row_to_json(v_sm),
    'new_quantity', v_qty,
    'field_provider_id', v_uid,
    'commodity_id', product_id
  );
end;
$$;

grant execute on function public.receive_fieldprovider_inventory_stock(uuid, integer, date, text, text) to authenticated;
