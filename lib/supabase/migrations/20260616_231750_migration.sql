-- Low-stock notifications (production-safe)
-- Adds:
-- 1) public.field_provider_commodity_settings (per-provider minimum thresholds + low-stock state)
-- 2) public.notifications (provider-scoped notifications)
-- 3) Trigger functions to generate/dedupe low-stock alerts on stock movement + threshold changes
-- 4) Idempotent backfill for existing inventory

create extension if not exists pgcrypto;

-- =========================================================
-- 1) Per-provider commodity settings (minimum threshold + state)
-- =========================================================
create table if not exists public.field_provider_commodity_settings (
  field_provider_id uuid not null references public.users(id) on delete cascade,
  commodity_id uuid not null references public.commodities(id) on delete cascade,
  minimum_quantity integer not null default 0,
  -- Optional per-provider unit override used for display + notifications.
  -- (This is now restricted via a CHECK constraint in a later migration.)
  unit_override text null,
  -- Tracks whether we already emitted an active low-stock alert for the *current* low state.
  -- This prevents spam while qty remains <= minimum.
  low_stock_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (field_provider_id, commodity_id)
);

create index if not exists idx_fp_commodity_settings_provider on public.field_provider_commodity_settings (field_provider_id);
create index if not exists idx_fp_commodity_settings_commodity on public.field_provider_commodity_settings (commodity_id);

create or replace function public._touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_fp_commodity_settings_touch on public.field_provider_commodity_settings;
create trigger trg_fp_commodity_settings_touch
before update on public.field_provider_commodity_settings
for each row execute function public._touch_updated_at();

-- =========================================================
-- 2) Notifications table
-- =========================================================
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  field_provider_id uuid not null references public.users(id) on delete cascade,
  commodity_id uuid null references public.commodities(id) on delete set null,
  title text not null,
  message text not null,
  type text not null,
  is_read boolean not null default false,
  read_at timestamptz null,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_notifications_provider_created_at on public.notifications (field_provider_id, created_at desc);
create index if not exists idx_notifications_provider_unread on public.notifications (field_provider_id, is_read);
create index if not exists idx_notifications_type on public.notifications (type);

-- Only one ACTIVE unread low-stock alert per provider per commodity.
create unique index if not exists uq_notifications_low_stock_unread_per_product
on public.notifications (field_provider_id, commodity_id, type)
where (type = 'low_stock' and is_read = false and commodity_id is not null);

-- =========================================================
-- 3) RLS: provider-scoped notifications/settings
-- =========================================================
alter table public.notifications enable row level security;
alter table public.field_provider_commodity_settings enable row level security;

-- Notifications: field provider can only SELECT their own
drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own
on public.notifications
for select
to authenticated
using (field_provider_id = auth.uid());

-- Notifications: field provider can only UPDATE their own (for marking read)
drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own
on public.notifications
for update
to authenticated
using (field_provider_id = auth.uid())
with check (field_provider_id = auth.uid());

-- Notifications: allow providers to INSERT their own non-low-stock notifications
-- (system messages, delivery updates, etc). Low-stock must be backend-generated.
drop policy if exists notifications_insert_own_non_low_stock on public.notifications;
create policy notifications_insert_own_non_low_stock
on public.notifications
for insert
to authenticated
with check (field_provider_id = auth.uid() and type <> 'low_stock');

-- No insert/delete policies: only DB owner (triggers/migrations) can insert/delete.

-- Settings: provider can manage only their own settings
drop policy if exists fp_commodity_settings_all_own on public.field_provider_commodity_settings;
create policy fp_commodity_settings_all_own
on public.field_provider_commodity_settings
for all
to authenticated
using (field_provider_id = auth.uid())
with check (field_provider_id = auth.uid());

-- =========================================================
-- 4) Low-stock engine (trigger helpers)
-- =========================================================

-- Compute current quantity from stock movements.
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

-- Idempotent: ensure settings row exists.
create or replace function public._ensure_fp_commodity_settings(p_field_provider_id uuid, p_commodity_id uuid)
returns void
language plpgsql
as $$
begin
  insert into public.field_provider_commodity_settings(field_provider_id, commodity_id)
  values (p_field_provider_id, p_commodity_id)
  on conflict (field_provider_id, commodity_id) do nothing;
end;
$$;

-- Core: update low_stock_active state + insert notification when crossing into low.
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
  perform public._ensure_fp_commodity_settings(p_field_provider_id, p_commodity_id);

  select minimum_quantity, low_stock_active, unit_override
    into v_min, v_active, v_unit
  from public.field_provider_commodity_settings
  where field_provider_id = p_field_provider_id
    and commodity_id = p_commodity_id;

  v_qty := public._stock_quantity(p_field_provider_id, p_commodity_id);

  select name into v_name from public.commodities where id = p_commodity_id;
  if v_name is null then
    v_name := 'Product';
  end if;

  -- Prefer per-provider override when present.
  select coalesce(nullif(trim(s.unit_override), ''), nullif(trim(c.unit_of_expression), ''))
    into v_unit
  from public.field_provider_commodity_settings s
  left join public.commodities c on c.id = s.commodity_id
  where s.field_provider_id = p_field_provider_id
    and s.commodity_id = p_commodity_id;

  if v_unit is null or trim(v_unit) = '' then
    v_msg := v_name || ' is low in stock (' || v_qty || ' remaining; minimum ' || v_min || ').';
  else
    v_msg := v_name || ' is low in stock (' || v_qty || ' ' || v_unit || ' remaining; minimum ' || v_min || ' ' || v_unit || ').';
  end if;

  -- Low-stock triggers at <= minimum (includes equality)
  if v_qty <= v_min then
    if not v_active then
      -- Insert notification only if we haven't already emitted one for this low state.
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
    -- Restocked above minimum: reset state so a future drop can notify again.
    if v_active then
      update public.field_provider_commodity_settings
      set low_stock_active = false
      where field_provider_id = p_field_provider_id
        and commodity_id = p_commodity_id;
    end if;
  end if;
end;
$$;

-- Trigger: when stock movements change
create or replace function public._on_stock_movement_change()
returns trigger
language plpgsql
as $$
declare
  u uuid;
  c uuid;
  ou uuid;
  oc uuid;
begin
  u := coalesce(new.userid, old.userid);
  c := coalesce(new.commodityid, old.commodityid);

  -- If a row was updated and user/commodity changed, evaluate both pairs.
  ou := old.userid;
  oc := old.commodityid;

  if ou is not null and oc is not null and (ou <> u or oc <> c) then
    perform public._evaluate_low_stock(ou, oc);
  end if;

  if u is not null and c is not null then
    perform public._evaluate_low_stock(u, c);
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_stock_movements_low_stock on public.stock_movements;
create trigger trg_stock_movements_low_stock
after insert or update or delete on public.stock_movements
for each row execute function public._on_stock_movement_change();

-- Trigger: when minimum threshold changes
create or replace function public._on_minimum_quantity_change()
returns trigger
language plpgsql
as $$
begin
  perform public._evaluate_low_stock(new.field_provider_id, new.commodity_id);
  return new;
end;
$$;

drop trigger if exists trg_fp_settings_low_stock on public.field_provider_commodity_settings;
create trigger trg_fp_settings_low_stock
after insert or update of minimum_quantity on public.field_provider_commodity_settings
for each row execute function public._on_minimum_quantity_change();

-- =========================================================
-- 5) Backend unread count RPC (source-of-truth for Home tile)
-- =========================================================
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

-- =========================================================
-- 6) Idempotent backfill for existing inventory
-- =========================================================
-- This backfill is safe to rerun. It:
-- - ensures settings rows exist for every (user, commodity) pair that has at least one movement
-- - evaluates low-stock state and creates a single unread low-stock notification per pair if needed

do $$
declare
  r record;
begin
  for r in (
    select distinct userid as field_provider_id, commodityid as commodity_id
    from public.stock_movements
  ) loop
    perform public._ensure_fp_commodity_settings(r.field_provider_id, r.commodity_id);
    perform public._evaluate_low_stock(r.field_provider_id, r.commodity_id);
  end loop;
end;
$$;
