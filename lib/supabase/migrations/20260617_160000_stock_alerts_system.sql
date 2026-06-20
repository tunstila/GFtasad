-- Production-safe Stock Alerts system (fieldProvider)
--
-- Adds:
-- - public.stock_alerts table
-- - RLS policies (provider scoped)
-- - Trigger-driven generation + resolution for low/out-of-stock
-- - Near-expiry evaluation + backfill + RPC count
-- - Reconciliation RPC for scheduled/daily checks
--
-- Notes:
-- - Inventory quantity is derived from public.stock_movements (SUM(add) - SUM(remove)).
-- - Minimum threshold comes from public.field_provider_commodity_settings.minimum_quantity.
-- - Batches are inferred from stock_movements batchNumber/expiryDate columns.

create extension if not exists pgcrypto;

-- =========================================================
-- 1) Canonical stock alerts table
-- =========================================================
create table if not exists public.stock_alerts (
  id uuid primary key default gen_random_uuid(),
  field_provider_id uuid not null references public.users(id) on delete cascade,
  commodity_id uuid null references public.commodities(id) on delete set null,

  -- Batch context (nullable for non-batch alerts)
  batch_number text null,
  expiry_date date null,

  alert_type text not null,
  severity text not null,
  title text not null,
  message text not null,

  current_quantity integer null,
  minimum_threshold integer null,

  is_read boolean not null default false,
  read_at timestamptz null,
  resolved_at timestamptz null,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

-- Allowed alert types + severity
alter table public.stock_alerts
  drop constraint if exists stock_alerts_alert_type_check;
alter table public.stock_alerts
  add constraint stock_alerts_alert_type_check
  check (alert_type in ('low_stock','out_of_stock','near_expiry'));

alter table public.stock_alerts
  drop constraint if exists stock_alerts_severity_check;
alter table public.stock_alerts
  add constraint stock_alerts_severity_check
  check (severity in ('warning','critical'));

create index if not exists idx_stock_alerts_provider_created_at
  on public.stock_alerts (field_provider_id, created_at desc);

create index if not exists idx_stock_alerts_provider_active_unread
  on public.stock_alerts (field_provider_id, is_read, resolved_at);

-- Duplicate prevention: only one *active unread* alert of each type per scope.
create unique index if not exists uq_sa_low_stock_active_unread
  on public.stock_alerts (field_provider_id, commodity_id, alert_type)
  where (alert_type = 'low_stock' and is_read = false and resolved_at is null and commodity_id is not null);

create unique index if not exists uq_sa_out_of_stock_active_unread
  on public.stock_alerts (field_provider_id, commodity_id, alert_type)
  where (alert_type = 'out_of_stock' and is_read = false and resolved_at is null and commodity_id is not null);

create unique index if not exists uq_sa_near_expiry_active_unread
  on public.stock_alerts (field_provider_id, commodity_id, batch_number, alert_type)
  where (alert_type = 'near_expiry' and is_read = false and resolved_at is null and commodity_id is not null and batch_number is not null);

-- =========================================================
-- 2) RLS: provider can only see/update their own alerts
-- =========================================================
alter table public.stock_alerts enable row level security;

drop policy if exists stock_alerts_select_own on public.stock_alerts;
create policy stock_alerts_select_own
on public.stock_alerts
for select
to authenticated
using (field_provider_id = auth.uid());

drop policy if exists stock_alerts_update_own on public.stock_alerts;
create policy stock_alerts_update_own
on public.stock_alerts
for update
to authenticated
using (field_provider_id = auth.uid())
with check (field_provider_id = auth.uid());

-- No INSERT/DELETE policies: alerts are backend-generated.

-- =========================================================
-- 3) Helpers: stock qty, min threshold, and batch expiry
-- =========================================================

-- Ensure we have stock_movements columns for batch data (idempotent)
-- (Older projects may have CamelCase columns; other migrations already add them.
--  These are safe no-ops if already present.)
alter table if exists public.stock_movements add column if not exists "batchNumber" text null;
alter table if exists public.stock_movements add column if not exists "expiryDate" date null;
alter table if exists public.stock_movements add column if not exists batchnumber text null;
alter table if exists public.stock_movements add column if not exists expirydate date null;

-- Stable quantity computation (reuses existing if present)
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
  from public.stock_movements
  where userid = p_field_provider_id
    and commodityid = p_commodity_id;
$$;

create or replace function public._minimum_threshold(p_field_provider_id uuid, p_commodity_id uuid)
returns integer
language sql
stable
as $$
  select coalesce(
    (select minimum_quantity from public.field_provider_commodity_settings
      where field_provider_id = p_field_provider_id and commodity_id = p_commodity_id
      limit 1),
    0
  )::integer;
$$;

create or replace function public._batch_expiry_date(p_field_provider_id uuid, p_commodity_id uuid, p_batch_number text)
returns date
language sql
stable
as $$
  select max(coalesce("expiryDate", expirydate))::date
  from public.stock_movements
  where userid = p_field_provider_id
    and commodityid = p_commodity_id
    and coalesce(nullif(trim(coalesce("batchNumber", batchnumber)), ''), '') = coalesce(nullif(trim(p_batch_number), ''), '')
    and coalesce("expiryDate", expirydate) is not null;
$$;

-- =========================================================
-- 4) Core engines: evaluate stock levels + near-expiry
-- =========================================================

create or replace function public._create_stock_alert(
  p_field_provider_id uuid,
  p_commodity_id uuid,
  p_batch_number text,
  p_expiry_date date,
  p_alert_type text,
  p_severity text,
  p_title text,
  p_message text,
  p_current_quantity integer,
  p_minimum_threshold integer,
  p_metadata jsonb
)
returns void
language plpgsql
as $$
begin
  insert into public.stock_alerts(
    field_provider_id, commodity_id, batch_number, expiry_date,
    alert_type, severity, title, message,
    current_quantity, minimum_threshold,
    is_read, resolved_at, metadata
  )
  values(
    p_field_provider_id,
    p_commodity_id,
    nullif(trim(p_batch_number), ''),
    p_expiry_date,
    p_alert_type,
    p_severity,
    p_title,
    p_message,
    p_current_quantity,
    p_minimum_threshold,
    false,
    null,
    coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict do nothing;
end;
$$;

create or replace function public._resolve_stock_alerts(
  p_field_provider_id uuid,
  p_commodity_id uuid,
  p_alert_type text,
  p_batch_number text default null
)
returns void
language plpgsql
as $$
begin
  update public.stock_alerts
  set resolved_at = now()
  where field_provider_id = p_field_provider_id
    and commodity_id = p_commodity_id
    and alert_type = p_alert_type
    and resolved_at is null
    and (p_batch_number is null or batch_number = nullif(trim(p_batch_number), ''));
end;
$$;

create or replace function public._evaluate_stock_levels(p_field_provider_id uuid, p_commodity_id uuid)
returns void
language plpgsql
as $$
declare
  v_qty integer;
  v_min integer;
  v_name text;
  v_unit text;
  v_title text;
  v_msg text;
  v_reason text;
  v_meta jsonb;
  v_qty_text text;
  v_min_text text;
begin
  v_qty := public._stock_quantity(p_field_provider_id, p_commodity_id);
  v_min := public._minimum_threshold(p_field_provider_id, p_commodity_id);

  select name, unit_of_expression
    into v_name, v_unit
  from public.commodities
  where id = p_commodity_id;

  if v_name is null then v_name := 'Product'; end if;
  if v_unit is null or trim(v_unit) = '' then
    v_qty_text := v_qty::text;
    v_min_text := v_min::text;
  else
    v_qty_text := v_qty::text || ' ' || v_unit;
    v_min_text := v_min::text || ' ' || v_unit;
  end if;

  -- Rule: if stock is 0 => out_of_stock only (higher severity).
  if v_qty = 0 then
    perform public._resolve_stock_alerts(p_field_provider_id, p_commodity_id, 'low_stock');

    v_reason := 'Out of stock';
    v_title := 'Out of stock: ' || v_name;
    v_msg := v_name || ': Out of stock. Current quantity ' || v_qty_text || '; minimum ' || v_min_text || '.';
    v_meta := jsonb_build_object(
      'alert_type','out_of_stock',
      'reason', v_reason,
      'commodity_id', p_commodity_id,
      'commodity_name', v_name,
      'current_quantity', v_qty,
      'minimum_threshold', v_min,
      'unit_of_expression', v_unit
    );

    perform public._create_stock_alert(
      p_field_provider_id,
      p_commodity_id,
      null,
      null,
      'out_of_stock',
      'critical',
      v_title,
      v_msg,
      v_qty,
      v_min,
      v_meta
    );

    return;
  end if;

  -- If qty > 0, resolve out_of_stock if it exists.
  if v_qty > 0 then
    perform public._resolve_stock_alerts(p_field_provider_id, p_commodity_id, 'out_of_stock');
  end if;

  -- Low-stock: only for qty > 0 and qty <= min.
  if v_qty > 0 and v_qty <= v_min then
    v_reason := 'Low stock';
    v_title := 'Low stock: ' || v_name;
    v_msg := v_name || ': Low stock. Current quantity ' || v_qty_text || '; minimum ' || v_min_text || '. Current quantity is equal to or below the minimum stock level.';
    v_meta := jsonb_build_object(
      'alert_type','low_stock',
      'reason', v_reason,
      'commodity_id', p_commodity_id,
      'commodity_name', v_name,
      'current_quantity', v_qty,
      'minimum_threshold', v_min,
      'unit_of_expression', v_unit
    );

    perform public._create_stock_alert(
      p_field_provider_id,
      p_commodity_id,
      null,
      null,
      'low_stock',
      'warning',
      v_title,
      v_msg,
      v_qty,
      v_min,
      v_meta
    );
  else
    -- Restocked above minimum: resolve any active low-stock.
    perform public._resolve_stock_alerts(p_field_provider_id, p_commodity_id, 'low_stock');
  end if;
end;
$$;

create or replace function public._evaluate_near_expiry(p_field_provider_id uuid, p_commodity_id uuid, p_batch_number text)
returns void
language plpgsql
as $$
declare
  v_exp date;
  v_name text;
  v_unit text;
  v_title text;
  v_msg text;
  v_meta jsonb;
  v_window_end date;
begin
  if p_batch_number is null or trim(p_batch_number) = '' then
    return;
  end if;

  v_exp := public._batch_expiry_date(p_field_provider_id, p_commodity_id, p_batch_number);
  v_window_end := (current_date + interval '3 months')::date;

  select name, unit_of_expression into v_name, v_unit from public.commodities where id = p_commodity_id;
  if v_name is null then v_name := 'Product'; end if;

  -- If no expiry date is known, resolve any existing near-expiry.
  if v_exp is null then
    perform public._resolve_stock_alerts(p_field_provider_id, p_commodity_id, 'near_expiry', p_batch_number);
    return;
  end if;

  -- Do not keep near-expiry alerts alive once the batch is already expired.
  if v_exp <= current_date then
    perform public._resolve_stock_alerts(p_field_provider_id, p_commodity_id, 'near_expiry', p_batch_number);
    return;
  end if;

  if v_exp <= v_window_end then
    v_title := 'Near expiry: ' || v_name;
    v_msg := v_name || ' batch ' || trim(p_batch_number) || ' expires on ' || to_char(v_exp, 'YYYY-MM-DD') || ' (within 3 months).';
    v_meta := jsonb_build_object(
      'alert_type','near_expiry',
      'reason','Near expiry',
      'commodity_id', p_commodity_id,
      'commodity_name', v_name,
      'batch_number', trim(p_batch_number),
      'expiry_date', to_char(v_exp, 'YYYY-MM-DD'),
      'unit_of_expression', v_unit
    );

    perform public._create_stock_alert(
      p_field_provider_id,
      p_commodity_id,
      p_batch_number,
      v_exp,
      'near_expiry',
      'warning',
      v_title,
      v_msg,
      null,
      null,
      v_meta
    );
  else
    -- If expiry moves out of window, resolve.
    perform public._resolve_stock_alerts(p_field_provider_id, p_commodity_id, 'near_expiry', p_batch_number);
  end if;
end;
$$;

-- =========================================================
-- 5) Triggers: evaluate on stock movement changes + threshold changes
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
  u := coalesce(new.userid, old.userid);
  c := coalesce(new.commodityid, old.commodityid);

  old_u := old.userid;
  old_c := old.commodityid;

  if old_u is not null and old_c is not null and (old_u <> u or old_c <> c) then
    perform public._evaluate_stock_levels(old_u, old_c);
  end if;

  if u is not null and c is not null then
    perform public._evaluate_stock_levels(u, c);
  end if;

  -- Near-expiry: best-effort when batch fields change.
  old_b := nullif(trim(coalesce(old."batchNumber", old.batchnumber)), '');
  new_b := nullif(trim(coalesce(new."batchNumber", new.batchnumber)), '');
  b := coalesce(new_b, old_b);

  if u is not null and c is not null and b is not null then
    perform public._evaluate_near_expiry(u, c, b);
  end if;

  -- If the batch number itself changed, evaluate the old batch too (it might need resolving).
  if u is not null and c is not null and old_b is not null and new_b is not null and old_b <> new_b then
    perform public._evaluate_near_expiry(u, c, old_b);
  end if;

  return coalesce(new, old);
end;
$$;

-- Replace previous low-stock-only trigger with the new stock-alerts trigger.
drop trigger if exists trg_stock_movements_low_stock on public.stock_movements;
drop trigger if exists trg_stock_movements_stock_alerts on public.stock_movements;
create trigger trg_stock_movements_stock_alerts
after insert or update or delete on public.stock_movements
for each row execute function public._on_stock_movement_change_stock_alerts();

create or replace function public._on_minimum_threshold_change_stock_alerts()
returns trigger
language plpgsql
as $$
begin
  perform public._evaluate_stock_levels(new.field_provider_id, new.commodity_id);
  return new;
end;
$$;

-- Replace previous minimum-change trigger.
drop trigger if exists trg_fp_settings_low_stock on public.field_provider_commodity_settings;
drop trigger if exists trg_fp_settings_stock_alerts on public.field_provider_commodity_settings;
create trigger trg_fp_settings_stock_alerts
after insert or update of minimum_quantity on public.field_provider_commodity_settings
for each row execute function public._on_minimum_threshold_change_stock_alerts();

-- =========================================================
-- 6) Backend RPCs: count + reconcile (backfill + scheduled use)
-- =========================================================

create or replace function public.count_unread_active_stock_alerts()
returns bigint
language sql
stable
as $$
  select count(*)::bigint
  from public.stock_alerts
  where field_provider_id = auth.uid()
    and is_read = false
    and resolved_at is null;
$$;

grant execute on function public.count_unread_active_stock_alerts() to authenticated;

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
    select distinct sm.userid as field_provider_id, sm.commodityid as commodity_id
    from public.stock_movements sm
    union
    select distinct s.field_provider_id, s.commodity_id
    from public.field_provider_commodity_settings s
  ) loop
    perform public._evaluate_stock_levels(r.field_provider_id, r.commodity_id);
  end loop;

  -- 2) Near expiry: scan known batches with expiry dates.
  for b in (
    select distinct sm.userid as field_provider_id, sm.commodityid as commodity_id,
      nullif(trim(coalesce(sm."batchNumber", sm.batchnumber)), '') as batch_number
    from public.stock_movements sm
    where coalesce(sm."expiryDate", sm.expirydate) is not null
      and nullif(trim(coalesce(sm."batchNumber", sm.batchnumber)), '') is not null
  ) loop
    v_batch := b.batch_number;
    if v_batch is not null then
      perform public._evaluate_near_expiry(b.field_provider_id, b.commodity_id, v_batch);
    end if;
  end loop;
end;
$$;

-- Do NOT grant this to `authenticated` (it inserts/updates alerts for all providers).
-- It should be called by migrations/triggers/service-role (e.g., scheduled Edge Function).

-- =========================================================
-- 7) One-time backfill after deployment (safe to re-run)
-- =========================================================
select public.reconcile_stock_alerts();
