-- Stock alerts clarity + correct unread count (production-safe)
--
-- Goals:
-- 1) Distinguish low-stock states: at_minimum vs below_minimum
-- 2) Prevent duplicate unread alerts per product per state
-- 3) Add backend RPC for unread low-stock alert count (source of truth)
-- 4) Enrich metadata fields used by Flutter UI (reason/state/quantities)

create extension if not exists pgcrypto;

-- ---------------------------------------------------------
-- 1) Persist last low-stock state so we can re-alert safely
-- ---------------------------------------------------------
alter table public.field_provider_commodity_settings
  add column if not exists low_stock_state text null;

-- ---------------------------------------------------------
-- 2) Store state in notifications so we can dedupe correctly
-- ---------------------------------------------------------
alter table public.notifications
  add column if not exists low_stock_state text null;

-- Replace the old dedupe index (it did not distinguish state)
-- and add a state-aware one.
do $$
begin
  if exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'uq_notifications_low_stock_unread_per_product'
  ) then
    execute 'drop index public.uq_notifications_low_stock_unread_per_product';
  end if;
end;
$$;

create unique index if not exists uq_notifications_low_stock_unread_per_product_state
on public.notifications (field_provider_id, commodity_id, type, low_stock_state)
where (type = 'low_stock' and is_read = false and commodity_id is not null);

-- Helpful query index for stock-alert list screens.
create index if not exists idx_notifications_low_stock_provider_created_at
on public.notifications (field_provider_id, created_at desc)
where (type = 'low_stock');

-- ---------------------------------------------------------
-- 3) Low-stock engine: emit a new alert when:
--    - crossing from above-minimum into low, OR
--    - changing low state (at_minimum <-> below_minimum)
--    Reset when restocked above minimum.
-- ---------------------------------------------------------
create or replace function public._evaluate_low_stock(p_field_provider_id uuid, p_commodity_id uuid)
returns void
language plpgsql
as $$
declare
  v_qty integer;
  v_min integer;
  v_active boolean;
  v_prev_state text;
  v_state text;
  v_name text;
  v_unit text;
  v_reason text;
  v_msg text;
begin
  perform public._ensure_fp_commodity_settings(p_field_provider_id, p_commodity_id);

  select minimum_quantity, low_stock_active, low_stock_state
    into v_min, v_active, v_prev_state
  from public.field_provider_commodity_settings
  where field_provider_id = p_field_provider_id
    and commodity_id = p_commodity_id;

  v_qty := public._stock_quantity(p_field_provider_id, p_commodity_id);

  select name into v_name from public.commodities where id = p_commodity_id;
  if v_name is null then v_name := 'Product'; end if;

  -- Prefer per-provider override when present.
  select coalesce(nullif(trim(s.unit_override), ''), nullif(trim(c.unit_of_expression), ''))
    into v_unit
  from public.field_provider_commodity_settings s
  left join public.commodities c on c.id = s.commodity_id
  where s.field_provider_id = p_field_provider_id
    and s.commodity_id = p_commodity_id;

  -- Low-stock triggers at <= minimum (includes equality)
  if v_qty <= v_min then
    if v_qty < v_min then
      v_state := 'below_minimum';
      v_reason := 'Below minimum stock';
    else
      v_state := 'at_minimum';
      v_reason := 'At minimum stock';
    end if;

    -- Plain-language explanation required by the app.
    -- Keep it stable (so users learn it) while still including the exact numbers.
    if v_unit is null or trim(v_unit) = '' then
      v_msg := v_name || ': ' || v_reason || '. Current quantity ' || v_qty || '; minimum ' || v_min || '. Current quantity is equal to or below the minimum stock level.';
    else
      v_msg := v_name || ': ' || v_reason || '. Current quantity ' || v_qty || ' ' || v_unit || '; minimum ' || v_min || ' ' || v_unit || '. Current quantity is equal to or below the minimum stock level.';
    end if;

    -- Emit a new notification only if:
    -- - first time entering low, OR
    -- - low state changed (at_minimum <-> below_minimum)
    if (not v_active) or (coalesce(v_prev_state, '') <> coalesce(v_state, '')) then
      insert into public.notifications(field_provider_id, commodity_id, title, message, type, is_read, low_stock_state, metadata)
      values (
        p_field_provider_id,
        p_commodity_id,
        'Stock alert: ' || v_name,
        v_msg,
        'low_stock',
        false,
        v_state,
        jsonb_build_object(
          'alert_type', 'low_stock',
          'commodity_id', p_commodity_id,
          'commodity_name', v_name,
          'current_quantity', v_qty,
          'minimum_quantity', v_min,
          'reason', v_reason,
          'low_stock_state', v_state,
          'unit_of_expression', v_unit
        )
      )
      on conflict do nothing;

      update public.field_provider_commodity_settings
      set low_stock_active = true,
          low_stock_state = v_state
      where field_provider_id = p_field_provider_id
        and commodity_id = p_commodity_id;
    end if;

  else
    -- Restocked above minimum: reset state so a future drop can notify again.
    if v_active or v_prev_state is not null then
      update public.field_provider_commodity_settings
      set low_stock_active = false,
          low_stock_state = null
      where field_provider_id = p_field_provider_id
        and commodity_id = p_commodity_id;
    end if;
  end if;
end;
$$;

-- ---------------------------------------------------------
-- 4) Backend unread count RPCs (source of truth)
-- ---------------------------------------------------------
create or replace function public.count_unread_low_stock_alerts()
returns bigint
language sql
stable
as $$
  select count(*)::bigint
  from public.notifications
  where field_provider_id = auth.uid()
    and type = 'low_stock'
    and is_read = false;
$$;

grant execute on function public.count_unread_low_stock_alerts() to authenticated;

-- Optional helper used by some dashboards; keep it correct too.
create or replace function public.count_unread_notifications()
returns bigint
language sql
stable
as $$
  select count(*)::bigint
  from public.notifications
  where field_provider_id = auth.uid()
    and is_read = false;
$$;

grant execute on function public.count_unread_notifications() to authenticated;
