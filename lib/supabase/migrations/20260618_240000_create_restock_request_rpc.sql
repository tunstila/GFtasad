-- Production-safe restock request creation RPC.
--
-- Requirements:
-- - Derive requester from auth.uid() (do not trust client provider_id).
-- - Validate supplier exists and is role supplier (case-insensitive).
-- - Validate commodity exists.
-- - Validate quantity > 0.
-- - Validate unit_of_expression is one of the approved app units.
-- - Insert into canonical table public.stock_requests (items as jsonb).

create or replace function public.create_restock_request(
  p_supplier_id uuid,
  p_commodity_id uuid,
  p_quantity_requested integer,
  p_unit_of_expression text,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_role text;
  v_supplier public.users%rowtype;
  v_provider public.users%rowtype;
  v_comm public.commodities%rowtype;
  v_now timestamptz;
  v_id uuid;
  v_program text;
  v_item jsonb;
  v_unit text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_provider from public.users where id = v_uid;
  if not found then
    raise exception 'Requester profile not found';
  end if;

  v_role := coalesce(nullif(trim(v_provider.role), ''), '');
  if lower(v_role) not in ('fieldprovider','superadmin') then
    raise exception 'Only fieldProvider can create restock requests';
  end if;

  if p_supplier_id is null then
    raise exception 'Missing supplier_id';
  end if;

  select * into v_supplier from public.users where id = p_supplier_id;
  if not found then
    raise exception 'Invalid supplier';
  end if;

  if lower(coalesce(nullif(trim(v_supplier.role), ''), '')) <> 'supplier' then
    raise exception 'Selected account is not a supplier';
  end if;

  if p_quantity_requested is null or p_quantity_requested <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  if p_commodity_id is null then
    raise exception 'Missing product';
  end if;

  select * into v_comm from public.commodities where id = p_commodity_id;
  if not found then
    raise exception 'Invalid product';
  end if;

  if (coalesce(v_comm.is_active, true) = false or coalesce(v_comm.isactive, true) = false) then
    raise exception 'Selected product is no longer available';
  end if;

  v_unit := upper(trim(coalesce(p_unit_of_expression, '')));
  if v_unit = '' then
    raise exception 'Missing unit of expression';
  end if;

  if v_unit not in ('EA','PC','PCK','CARTON') then
    raise exception 'Invalid unit of expression';
  end if;

  v_program := coalesce(nullif(trim(v_comm.program), ''), 'unknown');

  v_item := jsonb_build_object(
    'commodityId', v_comm.id,
    'commodityName', v_comm.name,
    'unit', case when v_unit = 'CARTON' then 'Carton' else v_unit end,
    'quantity', p_quantity_requested,
    'program', v_program
  );

  v_now := now();

  insert into public.stock_requests(
    "providerId",
    "providerName",
    "providerEmail",
    "providerFacilityName",
    "providerBusinessAddress",
    "providerState",
    "providerLga",
    "providerLatitude",
    "providerLongitude",
    "supplierId",
    "supplierName",
    status,
    items,
    notes,
    "createdAt",
    "updatedAt"
  ) values (
    v_provider.id,
    v_provider.username,
    v_provider.email,
    v_provider."facilityName",
    v_provider."businessAddress",
    v_provider.state,
    v_provider.lga,
    v_provider.latitude,
    v_provider.longitude,
    v_supplier.id,
    v_supplier.username,
    'pending',
    jsonb_build_array(v_item),
    nullif(trim(p_notes), ''),
    v_now,
    v_now
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_restock_request(uuid, uuid, integer, text, text) from public;
grant execute on function public.create_restock_request(uuid, uuid, integer, text, text) to authenticated;
