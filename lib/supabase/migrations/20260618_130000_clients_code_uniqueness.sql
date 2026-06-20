-- Enforce normalized uniqueness for location-prefixed client codes.
--
-- This prevents duplicates that differ only by whitespace/casing.

do $$
begin
  if to_regclass('public.clients') is null then
    -- Table is created lazily by the id_management edge function in some installs.
    return;
  end if;

  -- Ensure the base unique index exists (older setups may already have it).
  execute 'create unique index if not exists clients_clientid_uniq on public.clients (clientid)';

  -- Stronger normalized uniqueness (case/trim-insensitive).
  execute 'create unique index if not exists clients_clientid_norm_uniq on public.clients ((lower(trim(clientid))))';
end;
$$;