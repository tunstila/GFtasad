begin;

create extension if not exists pgcrypto;

-- =========================================================
-- A) Inventory batches: allow controlled updates of missing batch/expiry
-- =========================================================

-- Ensure baseline columns exist on stock_movements (some environments use lowercase)
alter table if exists public.stock_movements add column if not exists batchnumber text null;
alter table if exists public.stock_movements add column if not exists expirydate date null;
alter table if exists public.stock_movements add column if not exists createdat timestamptz null;
alter table if exists public.stock_movements add column if not exists createdby uuid null;

alter table if exists public.stock_movements add column if not exists "batchNumber" text null;
alter table if exists public.stock_movements add column if not exists "expiryDate" date null;
alter table if exists public.stock_movements add column if not exists "createdAt" timestamptz null;
alter table if exists public.stock_movements add column if not exists "createdBy" uuid null;

create index if not exists idx_stock_movements_user_commodity on public.stock_movements (userid, commodityid);
create index if not exists idx_stock_movements_batch on public.stock_movements (batchnumber);
create index if not exists idx_stock_movements_expiry on public.stock_movements (expirydate);

-- RLS: stock_movements should be provider-scoped by default
alter table public.stock_movements enable row level security;

drop policy if exists stock_movements_select_own on public.stock_movements;
create policy stock_movements_select_own
on public.stock_movements
for select
to authenticated
using (
  userid = auth.uid()
  or exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and u.role in ('admin','sfhTeam','superAdmin')
  )
);

drop policy if exists stock_movements_insert_own on public.stock_movements;
create policy stock_movements_insert_own
on public.stock_movements
for insert
to authenticated
with check (
  userid = auth.uid()
  and exists(select 1 from public.users u where u.id = auth.uid() and u.role in ('fieldProvider','superAdmin'))
);

-- Intentionally do NOT allow direct UPDATE/DELETE from the client.

-- RPC: FieldProvider can backfill missing batch/expiry on *their own* movement rows.
-- Rules:
-- - Only the owner (userid=auth.uid()) can update.
-- - Only allowed when the corresponding value is currently missing.
-- - Allows updating batch number and/or expiry date in one call.
create or replace function public.update_my_stock_movement_batch_expiry(
  p_movement_id uuid,
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
  v_row public.stock_movements%rowtype;
  v_next_batch text;
  v_next_exp date;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select role into v_role from public.users where id = v_uid;
  if coalesce(v_role,'') not in ('fieldProvider','superAdmin') then
    raise exception 'Only fieldProvider can edit inventory batches';
  end if;

  select * into v_row
  from public.stock_movements
  where id = p_movement_id
    and userid = v_uid
  for update;

  if not found then
    raise exception 'Movement not found (or not owned by you)';
  end if;

  v_next_batch := nullif(trim(coalesce(p_batch_number,'')), '');
  v_next_exp := p_expiry_date;

  if v_next_batch is null and v_next_exp is null then
    raise exception 'Provide batch number and/or expiry date';
  end if;

  -- Only allow setting values that are currently missing.
  if v_next_batch is not null then
    if nullif(trim(coalesce(v_row.batchnumber, v_row."batchNumber")), '') is not null then
      raise exception 'Batch number is already set and cannot be edited';
    end if;
  end if;

  if v_next_exp is not null then
    if coalesce(v_row.expirydate, v_row."expiryDate") is not null then
      raise exception 'Expiry date is already set and cannot be edited';
    end if;
  end if;

  if v_next_exp is not null and v_next_exp < current_date then
    raise exception 'Expiry date cannot be in the past';
  end if;

  update public.stock_movements
  set
    batchnumber = coalesce(v_next_batch, batchnumber),
    "batchNumber" = coalesce(v_next_batch, "batchNumber"),
    expirydate = coalesce(v_next_exp, expirydate),
    "expiryDate" = coalesce(v_next_exp, "expiryDate")
  where id = p_movement_id;

  select * into v_row from public.stock_movements where id = p_movement_id;

  -- Re-run expiry/stock alert evaluation (best-effort; functions may not exist in all envs).
  begin
    perform public._evaluate_stock_levels(v_uid, v_row.commodityid);
  exception when undefined_function then
    null;
  end;

  if v_next_batch is not null then
    begin
      perform public._evaluate_near_expiry(v_uid, v_row.commodityid, v_next_batch);
    exception when undefined_function then
      null;
    end;
  end if;

  return jsonb_build_object('movement', row_to_json(v_row));
end;
$$;

revoke all on function public.update_my_stock_movement_batch_expiry(uuid, text, date) from public;
grant execute on function public.update_my_stock_movement_batch_expiry(uuid, text, date) to authenticated;

-- =========================================================
-- B) Restock requests + deliveries: RLS + atomic accept/reject
-- =========================================================

-- Tolerant schema adds (these columns are safe even if unused by the Flutter models)
alter table if exists public.stock_requests add column if not exists "requestedAt" timestamptz null;
alter table if exists public.stock_requests add column if not exists "respondedAt" timestamptz null;
alter table if exists public.stock_requests add column if not exists "responseNote" text null;

alter table if exists public.stock_requests add column if not exists requested_at timestamptz null;
alter table if exists public.stock_requests add column if not exists responded_at timestamptz null;
alter table if exists public.stock_requests add column if not exists response_note text null;

alter table if exists public.deliveries add column if not exists "restockRequestId" uuid null;
alter table if exists public.deliveries add column if not exists restock_request_id uuid null;

create unique index if not exists uq_deliveries_restock_request
on public.deliveries ("restockRequestId")
where ("restockRequestId" is not null);

-- Enable RLS
alter table public.stock_requests enable row level security;
alter table public.deliveries enable row level security;

-- Stock requests: provider sees own; supplier sees assigned; admin global
drop policy if exists stock_requests_select_scope on public.stock_requests;
create policy stock_requests_select_scope
on public.stock_requests
for select
to authenticated
using (
  "providerId" = auth.uid()
  or "supplierId" = auth.uid()
  or exists(select 1 from public.users u where u.id = auth.uid() and u.role in ('admin','sfhTeam','superAdmin'))
);

-- Provider creates only for self (server must not trust client role)
drop policy if exists stock_requests_insert_own on public.stock_requests;
create policy stock_requests_insert_own
on public.stock_requests
for insert
to authenticated
with check (
  "providerId" = auth.uid()
  and exists(select 1 from public.users u where u.id = auth.uid() and u.role in ('fieldProvider','superAdmin'))
);

-- No direct UPDATE from clients; supplier must use RPC for accept/reject

-- Deliveries: provider sees own; supplier sees own; admin global
drop policy if exists deliveries_select_scope on public.deliveries;
create policy deliveries_select_scope
on public.deliveries
for select
to authenticated
using (
  "providerId" = auth.uid()
  or "supplierId" = auth.uid()
  or exists(select 1 from public.users u where u.id = auth.uid() and u.role in ('admin','sfhTeam','superAdmin'))
);

-- Provider can update their delivery for confirmation/dispute flows (existing app behavior)
drop policy if exists deliveries_update_provider_own on public.deliveries;
create policy deliveries_update_provider_own
on public.deliveries
for update
to authenticated
using (
  "providerId" = auth.uid()
  or exists(select 1 from public.users u where u.id = auth.uid() and u.role = 'superAdmin')
)
with check (
  "providerId" = auth.uid()
  or exists(select 1 from public.users u where u.id = auth.uid() and u.role = 'superAdmin')
);

-- Supplier accept: atomically update request + create delivery (idempotent)
create or replace function public.supplier_accept_stock_request(
  p_request_id uuid,
  p_response_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_role text;
  v_req public.stock_requests%rowtype;
  v_delivery public.deliveries%rowtype;
  v_now timestamptz;
  v_status text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select role into v_role from public.users where id = v_uid;
  if coalesce(v_role,'') not in ('supplier','superAdmin') then
    raise exception 'Only supplier can accept requests';
  end if;

  v_now := now();

  select * into v_req
  from public.stock_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Request not found';
  end if;

  if v_req."supplierId" <> v_uid then
    raise exception 'Not your assigned request';
  end if;

  v_status := lower(coalesce(v_req."status", ''));
  if v_status not in ('pending','pending_supplier_response','requested') then
    raise exception 'Request is not pending';
  end if;

  update public.stock_requests
  set
    "status" = 'approved',
    "respondedAt" = coalesce("respondedAt", v_now),
    "responseNote" = nullif(trim(p_response_note), ''),
    responded_at = coalesce(responded_at, v_now),
    response_note = nullif(trim(p_response_note), ''),
    "updatedAt" = v_now
  where id = p_request_id;

  -- Idempotent delivery creation (one delivery per accepted request)
  insert into public.deliveries(
    id,
    "restockRequestId",
    "supplierId",
    "supplierName",
    "providerId",
    "deliveryDate",
    reference,
    items,
    "status",
    "syncStatus",
    "createdAt",
    "updatedAt"
  )
  values (
    gen_random_uuid(),
    p_request_id,
    v_req."supplierId",
    v_req."supplierName",
    v_req."providerId",
    v_now,
    'REQ-' || left(p_request_id::text, 8),
    v_req.items,
    'pending',
    'synced',
    v_now,
    v_now
  )
  on conflict ("restockRequestId") do nothing;

  select * into v_delivery
  from public.deliveries
  where "restockRequestId" = p_request_id
  limit 1;

  return jsonb_build_object(
    'request_id', p_request_id,
    'new_status', 'approved',
    'delivery', row_to_json(v_delivery)
  );
end;
$$;

revoke all on function public.supplier_accept_stock_request(uuid, text) from public;
grant execute on function public.supplier_accept_stock_request(uuid, text) to authenticated;

-- Supplier reject: atomically update request (idempotent)
create or replace function public.supplier_reject_stock_request(
  p_request_id uuid,
  p_response_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_role text;
  v_req public.stock_requests%rowtype;
  v_now timestamptz;
  v_status text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select role into v_role from public.users where id = v_uid;
  if coalesce(v_role,'') not in ('supplier','superAdmin') then
    raise exception 'Only supplier can reject requests';
  end if;

  v_now := now();

  select * into v_req
  from public.stock_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Request not found';
  end if;

  if v_req."supplierId" <> v_uid then
    raise exception 'Not your assigned request';
  end if;

  v_status := lower(coalesce(v_req."status", ''));
  if v_status not in ('pending','pending_supplier_response','requested') then
    raise exception 'Request is not pending';
  end if;

  update public.stock_requests
  set
    "status" = 'rejected',
    "respondedAt" = coalesce("respondedAt", v_now),
    "responseNote" = nullif(trim(p_response_note), ''),
    responded_at = coalesce(responded_at, v_now),
    response_note = nullif(trim(p_response_note), ''),
    "updatedAt" = v_now
  where id = p_request_id;

  return jsonb_build_object(
    'request_id', p_request_id,
    'new_status', 'rejected'
  );
end;
$$;

revoke all on function public.supplier_reject_stock_request(uuid, text) from public;
grant execute on function public.supplier_reject_stock_request(uuid, text) to authenticated;

commit;
