-- Manual stock adjustment RPC + audit trail (production-safe)
--
-- Canonical inventory table: public.stock_movements (SUM)
-- This RPC ensures:
-- - inventory never goes negative (unless explicitly allowed later)
-- - settings row exists so thresholds/alerts work for new commodities
-- - a detailed audit row is recorded
-- - alerts are re-evaluated immediately

begin;

create extension if not exists pgcrypto;

-- =========================================================
-- 1) Audit table
-- =========================================================
create table if not exists public.inventory_adjustments (
  id uuid primary key default gen_random_uuid(),
  field_provider_id uuid not null references public.users(id) on delete cascade,
  commodity_id uuid not null references public.commodities(id) on delete cascade,
  adjustment_type text not null,
  quantity_changed integer not null,
  previous_quantity integer not null,
  new_quantity integer not null,
  reason text not null,
  notes text null,
  batch_number text null,
  expiry_date date null,
  performed_by uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_inventory_adjustments_provider_created_at
  on public.inventory_adjustments (field_provider_id, created_at desc);
create index if not exists idx_inventory_adjustments_provider_commodity
  on public.inventory_adjustments (field_provider_id, commodity_id);

alter table public.inventory_adjustments enable row level security;

drop policy if exists inv_adj_select_own on public.inventory_adjustments;
create policy inv_adj_select_own
on public.inventory_adjustments
for select
to authenticated
using (field_provider_id = auth.uid());

-- No insert policy: only RPC (security definer) writes.

-- =========================================================
-- 2) Helper: best-effort FEFO batch selection for deductions
-- =========================================================
create or replace function public._choose_depletion_batch(p_field_provider_id uuid, p_commodity_id uuid)
returns table(batch_number text, expiry_date date)
language sql
stable
as $$
  with batch_sums as (
    select
      nullif(trim(coalesce(sm."batchNumber", sm.batchnumber)), '') as batch_number,
      max(coalesce(sm."expiryDate", sm.expirydate))::date as expiry_date,
      coalesce(sum(case when lower(coalesce(sm.type,''))='add' then sm.quantity else -sm.quantity end),0)::integer as qty
    from public.stock_movements sm
    where sm.userid = p_field_provider_id
      and sm.commodityid = p_commodity_id
      and nullif(trim(coalesce(sm."batchNumber", sm.batchnumber)), '') is not null
    group by nullif(trim(coalesce(sm."batchNumber", sm.batchnumber)), '')
  )
  select batch_number, expiry_date
  from batch_sums
  where qty > 0
  order by expiry_date asc nulls last, batch_number asc
  limit 1;
$$;

-- =========================================================
-- 3) RPC: centralized adjustment
-- =========================================================
create or replace function public.manual_stock_adjustment(
  p_commodity_id uuid,
  p_action text,
  p_quantity integer,
  p_reason text,
  p_notes text default null,
  p_batch_number text default null,
  p_expiry_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_role text;
  v_prev integer;
  v_target integer;
  v_delta integer;
  v_move_type text;
  v_qty integer;
  v_batch text;
  v_exp date;
  v_sm public.stock_movements%rowtype;
  v_adj public.inventory_adjustments%rowtype;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select role into v_role from public.users where id = v_uid;
  if coalesce(v_role, '') <> 'fieldProvider' then
    raise exception 'Only fieldProvider can adjust stock';
  end if;

  if p_quantity is null or p_quantity < 0 then
    raise exception 'quantity must be >= 0';
  end if;

  if p_action not in ('increase','decrease','set') then
    raise exception 'Invalid action';
  end if;

  if nullif(trim(coalesce(p_reason,'')), '') is null then
    raise exception 'reason is required';
  end if;

  -- Ensure commodity exists
  if not exists(select 1 from public.commodities c where c.id = p_commodity_id) then
    raise exception 'Selected commodity does not exist';
  end if;

  -- Ensure provider settings row exists (for thresholds/alerts)
  insert into public.field_provider_commodity_settings(field_provider_id, commodity_id)
  values (v_uid, p_commodity_id)
  on conflict (field_provider_id, commodity_id) do nothing;

  v_prev := public._stock_quantity(v_uid, p_commodity_id);

  if p_action = 'increase' then
    v_delta := p_quantity;
  elsif p_action = 'decrease' then
    v_delta := -p_quantity;
  else
    -- set
    v_delta := p_quantity - v_prev;
  end if;

  v_target := v_prev + v_delta;
  if v_target < 0 then
    raise exception 'Cannot reduce below zero (current %, requested delta %)', v_prev, v_delta;
  end if;

  if v_delta = 0 then
    -- Still write an audit row for traceability.
    insert into public.inventory_adjustments(
      field_provider_id, commodity_id, adjustment_type,
      quantity_changed, previous_quantity, new_quantity,
      reason, notes, batch_number, expiry_date,
      performed_by, metadata
    ) values (
      v_uid, p_commodity_id, p_action,
      0, v_prev, v_prev,
      trim(p_reason), nullif(trim(p_notes), ''), nullif(trim(p_batch_number), ''), p_expiry_date,
      v_uid, jsonb_build_object('no_change', true)
    ) returning * into v_adj;

    return jsonb_build_object(
      'new_quantity', v_prev,
      'previous_quantity', v_prev,
      'movement', null,
      'adjustment', row_to_json(v_adj)
    );
  end if;

  v_batch := nullif(trim(coalesce(p_batch_number,'')), '');
  v_exp := p_expiry_date;

  -- If decreasing and no batch specified, choose FEFO batch when available.
  if v_delta < 0 and v_batch is null then
    select batch_number, expiry_date into v_batch, v_exp
    from public._choose_depletion_batch(v_uid, p_commodity_id)
    limit 1;
  end if;

  v_move_type := case when v_delta > 0 then 'add' else 'deduct' end;

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
  ) values (
    gen_random_uuid(),
    p_commodity_id,
    v_uid,
    v_move_type,
    abs(v_delta),
    'countCorrection',
    nullif(trim(coalesce(p_notes, 'Manual adjustment')), ''),
    v_batch,
    v_exp,
    v_uid,
    'synced',
    now()
  ) returning * into v_sm;

  v_qty := public._stock_quantity(v_uid, p_commodity_id);

  insert into public.inventory_adjustments(
    field_provider_id, commodity_id, adjustment_type,
    quantity_changed, previous_quantity, new_quantity,
    reason, notes, batch_number, expiry_date,
    performed_by, metadata
  ) values (
    v_uid,
    p_commodity_id,
    p_action,
    abs(v_delta),
    v_prev,
    v_qty,
    trim(p_reason),
    nullif(trim(p_notes), ''),
    v_batch,
    v_exp,
    v_uid,
    jsonb_build_object(
      'movement_id', v_sm.id,
      'movement_type', v_move_type
    )
  ) returning * into v_adj;

  -- Re-evaluate alerts immediately for this commodity (and any batch).
  perform public._evaluate_stock_levels(v_uid, p_commodity_id);
  if v_batch is not null then
    perform public._evaluate_near_expiry(v_uid, p_commodity_id, v_batch);
  end if;

  return jsonb_build_object(
    'new_quantity', v_qty,
    'previous_quantity', v_prev,
    'movement', row_to_json(v_sm),
    'adjustment', row_to_json(v_adj)
  );
end;
$$;

revoke all on function public.manual_stock_adjustment(uuid, text, integer, text, text, text, date) from public;
grant execute on function public.manual_stock_adjustment(uuid, text, integer, text, text, text, date) to authenticated;

commit;
