-- Inventory + Alerts/Notifications unification v2 (production-safe)
--
-- Goals
-- 1) Low-stock works for ALL commodities (no name hardcoding)
-- 2) Use product master minimum as fallback when provider-specific minimum not set
-- 3) Expiry + expired alerts are backend-generated and visible in BOTH stock_alerts and notifications
-- 4) Prevent duplicates (per provider+commodity; and per provider+commodity+batch for expiry)
-- 5) Add configurable expiry_alert_days per fieldProvider (default 30)
-- 6) Resolve expiry alerts when a batch has no remaining quantity
--
-- Canonical tables in this project:
-- - public.commodities (product master)
-- - public.stock_movements (source-of-truth inventory transactions)
-- - public.field_provider_commodity_settings (per-provider thresholds + optional metadata)
-- - public.stock_alerts (canonical alerts)
-- - public.notifications (provider-scoped feed)

begin;

create extension if not exists pgcrypto;

-- =========================================================
-- A) Product master: default minimum quantity fallback
-- =========================================================
-- If a provider never configured a minimum, we fall back to the commodity master.
alter table if exists public.commodities
  add column if not exists minimum_quantity integer not null default 0;

create index if not exists idx_commodities_minimum_quantity
  on public.commodities (minimum_quantity);

-- =========================================================
-- B) Provider-level settings (expiry alert threshold)
-- =========================================================
create table if not exists public.field_provider_settings (
  field_provider_id uuid primary key references public.users(id) on delete cascade,
  expiry_alert_days integer not null default 30,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.field_provider_settings enable row level security;

drop policy if exists fp_settings_select_own on public.field_provider_settings;
create policy fp_settings_select_own
on public.field_provider_settings
for select
to authenticated
using (field_provider_id = auth.uid());

drop policy if exists fp_settings_upsert_own on public.field_provider_settings;
create policy fp_settings_upsert_own
on public.field_provider_settings
for all
to authenticated
using (field_provider_id = auth.uid())
with check (field_provider_id = auth.uid());

create or replace function public._touch_updated_at_fp_settings()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_fp_settings_touch on public.field_provider_settings;
create trigger trg_fp_settings_touch
before update on public.field_provider_settings
for each row execute function public._touch_updated_at_fp_settings();

create or replace function public._expiry_alert_days(p_field_provider_id uuid)
returns integer
language sql
stable
as $$
  select greatest(0, least(
    coalesce((select expiry_alert_days from public.field_provider_settings where field_provider_id = p_field_provider_id), 30),
    3650
  ))::integer;
$$;

-- Ensure a settings row exists for any provider that already has movements.
insert into public.field_provider_settings(field_provider_id)
select distinct sm.userid
from public.stock_movements sm
where sm.userid is not null
on conflict (field_provider_id) do nothing;

-- =========================================================
-- C) Notifications: add batch context for expiry dedupe
-- =========================================================
alter table public.notifications
  add column if not exists batch_number text null;

alter table public.notifications
  add column if not exists expiry_date date null;

-- Dedupe: one active unread expiry notification per provider+commodity+batch+type
create unique index if not exists uq_notifications_expiry_unread_per_batch
on public.notifications (field_provider_id, commodity_id, type, batch_number)
where (type in ('near_expiry','expired') and is_read = false and commodity_id is not null and batch_number is not null);

-- Helpful list index
create index if not exists idx_notifications_expiry_provider_created_at
on public.notifications (field_provider_id, created_at desc)
where (type in ('near_expiry','expired'));

-- =========================================================
-- D) Stock alerts: support expired alerts + expiry evaluation improvements
-- =========================================================
-- Extend allowed types
alter table public.stock_alerts
  drop constraint if exists stock_alerts_alert_type_check;

alter table public.stock_alerts
  add constraint stock_alerts_alert_type_check
  check (alert_type in ('low_stock','out_of_stock','near_expiry','expired'));

-- Active unread unique constraint for expired per provider+commodity+batch
create unique index if not exists uq_sa_expired_active_unread
  on public.stock_alerts (field_provider_id, commodity_id, batch_number, alert_type)
  where (alert_type = 'expired' and is_read = false and resolved_at is null and commodity_id is not null and batch_number is not null);

-- Minimum threshold now falls back to commodity master.
create or replace function public._minimum_threshold(p_field_provider_id uuid, p_commodity_id uuid)
returns integer
language sql
stable
as $$
  select coalesce(
    (select minimum_quantity from public.field_provider_commodity_settings
      where field_provider_id = p_field_provider_id and commodity_id = p_commodity_id
      limit 1),
    (select minimum_quantity from public.commodities where id = p_commodity_id),
    0
  )::integer;
$$;

-- Batch remaining quantity for FEFO / expiry cleanup.
create or replace function public._batch_quantity(p_field_provider_id uuid, p_commodity_id uuid, p_batch_number text)
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
    and commodityid = p_commodity_id
    and coalesce(nullif(trim(coalesce("batchNumber", batchnumber)), ''), '') = coalesce(nullif(trim(p_batch_number), ''), '');
$$;

-- Replace near-expiry evaluation with threshold + expired support.
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
  v_days integer;
  v_batch_qty integer;
begin
  if p_batch_number is null or trim(p_batch_number) = '' then
    return;
  end if;

  -- If the batch has no remaining quantity, resolve any expiry alerts for it.
  v_batch_qty := public._batch_quantity(p_field_provider_id, p_commodity_id, p_batch_number);
  if v_batch_qty <= 0 then
    perform public._resolve_stock_alerts(p_field_provider_id, p_commodity_id, 'near_expiry', p_batch_number);
    perform public._resolve_stock_alerts(p_field_provider_id, p_commodity_id, 'expired', p_batch_number);
    return;
  end if;

  v_exp := public._batch_expiry_date(p_field_provider_id, p_commodity_id, p_batch_number);
  select name, unit_of_expression into v_name, v_unit from public.commodities where id = p_commodity_id;
  if v_name is null then v_name := 'Product'; end if;

  -- If no expiry date is known, resolve any existing expiry alerts.
  if v_exp is null then
    perform public._resolve_stock_alerts(p_field_provider_id, p_commodity_id, 'near_expiry', p_batch_number);
    perform public._resolve_stock_alerts(p_field_provider_id, p_commodity_id, 'expired', p_batch_number);
    return;
  end if;

  v_days := public._expiry_alert_days(p_field_provider_id);
  v_window_end := (current_date + (v_days::text || ' days')::interval)::date;

  -- Expired: show as its own alert.
  if v_exp <= current_date then
    perform public._resolve_stock_alerts(p_field_provider_id, p_commodity_id, 'near_expiry', p_batch_number);

    v_title := 'Expired: ' || v_name;
    v_msg := v_name || ' batch ' || trim(p_batch_number) || ' expired on ' || to_char(v_exp, 'YYYY-MM-DD') || '.';
    v_meta := jsonb_build_object(
      'alert_type','expired',
      'reason','Expired',
      'commodity_id', p_commodity_id,
      'commodity_name', v_name,
      'batch_number', trim(p_batch_number),
      'expiry_date', to_char(v_exp, 'YYYY-MM-DD'),
      'batch_quantity', v_batch_qty,
      'expiry_alert_days', v_days,
      'unit_of_expression', v_unit
    );

    perform public._create_stock_alert(
      p_field_provider_id,
      p_commodity_id,
      p_batch_number,
      v_exp,
      'expired',
      'critical',
      v_title,
      v_msg,
      null,
      null,
      v_meta
    );
    return;
  end if;

  -- Near expiry: expiring within threshold window.
  if v_exp <= v_window_end then
    v_title := 'Near expiry: ' || v_name;
    v_msg := v_name || ' batch ' || trim(p_batch_number) || ' expires on ' || to_char(v_exp, 'YYYY-MM-DD') || ' (within ' || v_days || ' days).';
    v_meta := jsonb_build_object(
      'alert_type','near_expiry',
      'reason','Near expiry',
      'commodity_id', p_commodity_id,
      'commodity_name', v_name,
      'batch_number', trim(p_batch_number),
      'expiry_date', to_char(v_exp, 'YYYY-MM-DD'),
      'batch_quantity', v_batch_qty,
      'expiry_alert_days', v_days,
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

    -- If it is near-expiry, it cannot be expired.
    perform public._resolve_stock_alerts(p_field_provider_id, p_commodity_id, 'expired', p_batch_number);
  else
    perform public._resolve_stock_alerts(p_field_provider_id, p_commodity_id, 'near_expiry', p_batch_number);
    perform public._resolve_stock_alerts(p_field_provider_id, p_commodity_id, 'expired', p_batch_number);
  end if;
end;
$$;

-- =========================================================
-- E) Notifications bridge: emit expiry + stock alerts into notifications
-- =========================================================
create or replace function public._emit_notification_from_stock_alert()
returns trigger
language plpgsql
as $$
declare
  v_type text;
  v_message text;
  v_meta jsonb;
  v_commodity_id uuid;
  v_title text;
  v_low_stock_state text;
  v_batch text;
  v_exp date;
begin
  if new.resolved_at is not null then
    return new;
  end if;

  v_type := coalesce(new.alert_type, 'system');
  if v_type not in ('low_stock','out_of_stock','near_expiry','expired') then
    return new;
  end if;

  v_commodity_id := new.commodity_id;
  v_title := coalesce(nullif(trim(new.title), ''), 'Stock Alert');
  v_message := coalesce(nullif(trim(new.message), ''), 'Stock alert triggered.');
  v_meta := coalesce(new.metadata, '{}'::jsonb);

  v_batch := nullif(trim(coalesce(new.batch_number, '')), '');
  v_exp := new.expiry_date;

  -- Low stock state (only meaningful for low_stock)
  if v_type = 'low_stock' then
    if (v_meta ? 'low_stock_state') then
      v_low_stock_state := nullif(trim(v_meta->>'low_stock_state'), '');
    elsif new.current_quantity is not null and new.minimum_threshold is not null then
      if new.current_quantity = new.minimum_threshold then
        v_low_stock_state := 'at_minimum';
      elsif new.current_quantity < new.minimum_threshold then
        v_low_stock_state := 'below_minimum';
      else
        v_low_stock_state := null;
      end if;
    end if;
  end if;

  insert into public.notifications(
    field_provider_id,
    commodity_id,
    batch_number,
    expiry_date,
    title,
    message,
    type,
    is_read,
    low_stock_state,
    metadata
  )
  values(
    new.field_provider_id,
    v_commodity_id,
    v_batch,
    v_exp,
    v_title,
    v_message,
    v_type,
    false,
    v_low_stock_state,
    v_meta
  )
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists trg_stock_alerts_emit_notification on public.stock_alerts;
create trigger trg_stock_alerts_emit_notification
after insert on public.stock_alerts
for each row execute function public._emit_notification_from_stock_alert();

-- =========================================================
-- F) Reconcile functions: ensure expiry alerts also backfill/resolve safely
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
  for r in (
    select distinct sm.userid as field_provider_id, sm.commodityid as commodity_id
    from public.stock_movements sm
    union
    select distinct s.field_provider_id, s.commodity_id
    from public.field_provider_commodity_settings s
  ) loop
    perform public._evaluate_stock_levels(r.field_provider_id, r.commodity_id);
  end loop;

  for b in (
    select distinct sm.userid as field_provider_id, sm.commodityid as commodity_id,
      nullif(trim(coalesce(sm."batchNumber", sm.batchnumber)), '') as batch_number
    from public.stock_movements sm
    where nullif(trim(coalesce(sm."batchNumber", sm.batchnumber)), '') is not null
  ) loop
    v_batch := b.batch_number;
    if v_batch is not null then
      perform public._evaluate_near_expiry(b.field_provider_id, b.commodity_id, v_batch);
    end if;
  end loop;
end;
$$;

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

  insert into public.field_provider_settings(field_provider_id)
  values (v_uid)
  on conflict (field_provider_id) do nothing;

  for r in (
    select distinct sm.userid as field_provider_id, sm.commodityid as commodity_id
    from public.stock_movements sm
    where sm.userid = v_uid
    union
    select distinct s.field_provider_id, s.commodity_id
    from public.field_provider_commodity_settings s
    where s.field_provider_id = v_uid
  ) loop
    perform public._evaluate_stock_levels(r.field_provider_id, r.commodity_id);
  end loop;

  for b in (
    select distinct sm.userid as field_provider_id, sm.commodityid as commodity_id,
      nullif(trim(coalesce(sm."batchNumber", sm.batchnumber)), '') as batch_number
    from public.stock_movements sm
    where sm.userid = v_uid
      and nullif(trim(coalesce(sm."batchNumber", sm.batchnumber)), '') is not null
  ) loop
    v_batch := b.batch_number;
    if v_batch is not null then
      perform public._evaluate_near_expiry(b.field_provider_id, b.commodity_id, v_batch);
    end if;
  end loop;
end;
$$;

revoke all on function public.reconcile_my_stock_alerts() from public;
grant execute on function public.reconcile_my_stock_alerts() to authenticated;

-- Backfill (idempotent) after changes.
select public.reconcile_stock_alerts();

commit;
