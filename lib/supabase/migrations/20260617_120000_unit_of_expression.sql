-- Add product unit of expression support (production-safe, re-runnable)
--
-- Adds:
-- 1) public.commodities.unit_of_expression (nullable)
-- 2) check constraint limiting allowed values
-- 3) public.field_provider_commodity_settings.unit_override (nullable) + constraint (if table exists)
-- 4) Updates low-stock notification engine to include unit in message + metadata

begin;

-- 1) Canonical product catalog column
alter table public.commodities
  add column if not exists unit_of_expression text null;

-- Enforce allowed units (or NULL).
-- Postgres doesn't support "add constraint if not exists", so guard it.
do $$
begin
  if to_regclass('public.commodities') is not null then
    if not exists (
      select 1 from pg_constraint
      where conname = 'commodities_unit_of_expression_allowed'
    ) then
      alter table public.commodities
        add constraint commodities_unit_of_expression_allowed
        check (unit_of_expression is null or unit_of_expression in ('EA','PC','PCK','Carton'));
    end if;
  end if;
end $$;

-- 2) Per-provider override column (used by the app already; make it real + validate)
-- NOTE: This table is created by the low-stock notification migration.
-- We add the column here defensively so older DBs don't error.
alter table if exists public.field_provider_commodity_settings
  add column if not exists unit_override text null;

do $$
begin
  if to_regclass('public.field_provider_commodity_settings') is not null then
    if not exists (
      select 1 from pg_constraint
      where conname = 'fp_commodity_settings_unit_override_allowed'
    ) then
      alter table public.field_provider_commodity_settings
        add constraint fp_commodity_settings_unit_override_allowed
        check (unit_override is null or unit_override in ('EA','PC','PCK','Carton'));
    end if;
  end if;
end $$;

-- 3) Update low-stock message/metadata to include unit_of_expression when available.
-- This is safe to run even if you haven't applied the low-stock migration yet.
create or replace function public._evaluate_low_stock(p_field_provider_id uuid, p_commodity_id uuid)
returns void
language plpgsql
as $$
declare
  v_qty integer;
  v_min integer;
  v_active boolean;
  v_name text;
  v_unit text;
  v_msg text;
begin
  -- Ensure settings row exists (function is created in the low-stock migration).
  begin
    perform public._ensure_fp_commodity_settings(p_field_provider_id, p_commodity_id);
  exception when undefined_function then
    -- Low-stock engine not installed yet; no-op.
    return;
  end;

  select minimum_quantity, low_stock_active, unit_override
    into v_min, v_active, v_unit
  from public.field_provider_commodity_settings
  where field_provider_id = p_field_provider_id
    and commodity_id = p_commodity_id;

  -- Compute current quantity (function is created in the low-stock migration).
  begin
    v_qty := public._stock_quantity(p_field_provider_id, p_commodity_id);
  exception when undefined_function then
    return;
  end;

  select name, unit_of_expression
    into v_name, v_unit
  from public.commodities
  where id = p_commodity_id;

  -- Prefer per-provider override when present.
  select coalesce(nullif(trim(s.unit_override), ''), nullif(trim(c.unit_of_expression), ''))
    into v_unit
  from public.field_provider_commodity_settings s
  left join public.commodities c on c.id = s.commodity_id
  where s.field_provider_id = p_field_provider_id
    and s.commodity_id = p_commodity_id;

  if v_name is null then v_name := 'Product'; end if;

  if v_unit is null or trim(v_unit) = '' then
    v_msg := v_name || ' is low in stock (' || v_qty || ' remaining; minimum ' || v_min || ').';
  else
    v_msg := v_name || ' is low in stock (' || v_qty || ' ' || v_unit || ' remaining; minimum ' || v_min || ' ' || v_unit || ').';
  end if;

  -- Low-stock triggers at <= minimum (includes equality)
  if v_qty <= v_min then
    if not v_active then
      insert into public.notifications(field_provider_id, commodity_id, title, message, type, is_read, metadata)
      values (
        p_field_provider_id,
        p_commodity_id,
        'Low stock: ' || v_name,
        v_msg,
        'low_stock',
        false,
        jsonb_build_object(
          'commodity_name', v_name,
          'current_quantity', v_qty,
          'minimum_quantity', v_min,
          'unit_of_expression', v_unit
        )
      )
      on conflict do nothing;

      update public.field_provider_commodity_settings
      set low_stock_active = true
      where field_provider_id = p_field_provider_id
        and commodity_id = p_commodity_id;
    end if;
  else
    if v_active then
      update public.field_provider_commodity_settings
      set low_stock_active = false
      where field_provider_id = p_field_provider_id
        and commodity_id = p_commodity_id;
    end if;
  end if;
end;
$$;

commit;
