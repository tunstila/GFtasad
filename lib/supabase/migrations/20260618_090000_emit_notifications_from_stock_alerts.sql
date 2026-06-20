-- Emit provider notifications from stock_alerts (production-safe)
--
-- Why:
-- - Your app's Notifications UI + unread-low-stock RPC read from `public.notifications`.
-- - Your newer stock-alert engine creates rows in `public.stock_alerts`.
-- - Without a bridge, low-stock alerts never appear in Notifications.
--
-- This migration creates an AFTER INSERT trigger on `public.stock_alerts` that inserts
-- a corresponding row into `public.notifications` for low_stock and out_of_stock.
-- The insert is de-duped using the existing unique index on notifications.

begin;

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
begin
  -- Only for active, unread alerts.
  if new.resolved_at is not null then
    return new;
  end if;

  v_type := coalesce(new.alert_type, 'system');

  -- Map stock alert types to notification types.
  if v_type = 'low_stock' then
    v_type := 'low_stock';
  elsif v_type = 'out_of_stock' then
    -- Keep as its own type (still shows in notifications list);
    -- it won't affect the low-stock unread counter RPC.
    v_type := 'out_of_stock';
  else
    return new;
  end if;

  v_commodity_id := new.commodity_id;
  v_title := coalesce(nullif(trim(new.title), ''), 'Stock Alert');
  v_message := coalesce(nullif(trim(new.message), ''), 'Stock alert triggered.');
  v_meta := coalesce(new.metadata, '{}'::jsonb);

  -- Low stock clarity: store state if present.
  -- If absent, infer from qty vs min when both exist.
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

  -- Insert into notifications.
  -- For low_stock, the existing unique index prevents duplicates while unread.
  insert into public.notifications(
    field_provider_id,
    commodity_id,
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

commit;
