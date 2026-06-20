-- Allow a fieldProvider to reconcile ONLY their own stock alerts (production-safe)
-- This is a safety net in case triggers were not created yet or a migration was missed.
--
-- Requires the core Stock Alerts system functions from:
-- - 20260617_160000_stock_alerts_system.sql
--
-- This function is restricted to auth.uid() scope, and is safe to grant to authenticated.

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

  -- Low/out of stock: scan provider+commodity pairs for this user.
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

  -- Near expiry: scan known batches for this user.
  for b in (
    select distinct sm.userid as field_provider_id, sm.commodityid as commodity_id,
      nullif(trim(coalesce(sm."batchNumber", sm.batchnumber)), '') as batch_number
    from public.stock_movements sm
    where sm.userid = v_uid
      and coalesce(sm."expiryDate", sm.expirydate) is not null
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
