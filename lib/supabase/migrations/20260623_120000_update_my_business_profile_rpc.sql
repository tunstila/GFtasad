-- Production-safe self-service Business Profile update
--
-- Adds RPC:
--   public.update_my_business_profile(
--     p_business_address text,
--     p_state text,
--     p_lga text,
--     p_ward text default null,
--     p_latitude double precision default null,
--     p_longitude double precision default null
--   ) returns jsonb
--
-- Goals:
-- - Use auth.uid() (no client-supplied user id)
-- - Update only caller's rows
-- - Preserve created_at
-- - Normalize/trim state/lga/ward/address
-- - Validate coordinates ranges

create or replace function public.update_my_business_profile(
  p_business_address text,
  p_state text,
  p_lga text,
  p_ward text default null,
  p_latitude double precision default null,
  p_longitude double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_role text;
  v_address text;
  v_state text;
  v_lga text;
  v_ward text;
  v_created_at timestamptz;
  v_now timestamptz := now();
  v_row public.user_business_addresses%rowtype;

  -- Optional back-compat mirror onto public.users (only if columns exist).
  v_has_users_table boolean;
  v_has_business_address_snake boolean;
  v_has_updated_at_snake boolean;
  v_has_updated_at_camel boolean;
  v_has_latitude boolean;
  v_has_longitude boolean;
  v_has_state boolean;
  v_has_lga boolean;
  v_has_ward boolean;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select u.role into v_role from public.users u where u.id = v_user_id;
  v_role := coalesce(nullif(trim(v_role), ''), 'unknown');

  -- Allow only roles that represent actual app users who manage a business profile.
  -- (Adjust if you later allow additional roles to edit their address.)
  if v_role not in ('fieldProvider','supplier','superAdmin') then
    return jsonb_build_object('ok', false, 'error', 'forbidden_role', 'role', v_role);
  end if;

  v_address := nullif(trim(coalesce(p_business_address, '')), '');
  v_state := nullif(trim(coalesce(p_state, '')), '');
  v_lga := nullif(trim(coalesce(p_lga, '')), '');
  v_ward := nullif(trim(coalesce(p_ward, '')), '');

  if v_address is null then
    return jsonb_build_object('ok', false, 'error', 'missing_business_address');
  end if;
  if v_state is null then
    return jsonb_build_object('ok', false, 'error', 'missing_state');
  end if;
  if v_lga is null then
    return jsonb_build_object('ok', false, 'error', 'missing_lga');
  end if;

  if p_latitude is not null and (p_latitude < -90 or p_latitude > 90) then
    return jsonb_build_object('ok', false, 'error', 'invalid_latitude');
  end if;
  if p_longitude is not null and (p_longitude < -180 or p_longitude > 180) then
    return jsonb_build_object('ok', false, 'error', 'invalid_longitude');
  end if;

  -- Preserve created_at if row already exists.
  select created_at into v_created_at
  from public.user_business_addresses
  where user_id = v_user_id;

  insert into public.user_business_addresses (
    user_id,
    business_address,
    ward,
    state,
    lga,
    latitude,
    longitude,
    created_at,
    updated_at
  ) values (
    v_user_id,
    v_address,
    v_ward,
    v_state,
    v_lga,
    p_latitude,
    p_longitude,
    coalesce(v_created_at, v_now),
    v_now
  )
  on conflict (user_id) do update set
    business_address = excluded.business_address,
    ward = excluded.ward,
    state = excluded.state,
    lga = excluded.lga,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    updated_at = excluded.updated_at;

  -- Back-compat: mirror onto public.users if the table/columns exist.
  -- IMPORTANT: this must never fail the RPC even if the profile table schema differs.
  select to_regclass('public.users') is not null into v_has_users_table;
  if v_has_users_table then
    select exists(
      select 1 from pg_attribute
      where attrelid = 'public.users'::regclass and attname = 'business_address' and not attisdropped
    ) into v_has_business_address_snake;
    select exists(
      select 1 from pg_attribute
      where attrelid = 'public.users'::regclass and attname = 'updated_at' and not attisdropped
    ) into v_has_updated_at_snake;
    select exists(
      select 1 from pg_attribute
      where attrelid = 'public.users'::regclass and attname = 'updatedAt' and not attisdropped
    ) into v_has_updated_at_camel;
    select exists(
      select 1 from pg_attribute
      where attrelid = 'public.users'::regclass and attname = 'latitude' and not attisdropped
    ) into v_has_latitude;
    select exists(
      select 1 from pg_attribute
      where attrelid = 'public.users'::regclass and attname = 'longitude' and not attisdropped
    ) into v_has_longitude;
    select exists(
      select 1 from pg_attribute
      where attrelid = 'public.users'::regclass and attname = 'state' and not attisdropped
    ) into v_has_state;
    select exists(
      select 1 from pg_attribute
      where attrelid = 'public.users'::regclass and attname = 'lga' and not attisdropped
    ) into v_has_lga;
    select exists(
      select 1 from pg_attribute
      where attrelid = 'public.users'::regclass and attname = 'ward' and not attisdropped
    ) into v_has_ward;

    begin
      -- Prefer snake_case when available.
      if v_has_business_address_snake or v_has_state or v_has_lga or v_has_ward or v_has_latitude or v_has_longitude or v_has_updated_at_snake then
        execute (
          'update public.users set '
          || (case when v_has_business_address_snake then 'business_address = $1, ' else '' end)
          || (case when v_has_ward then 'ward = $2, ' else '' end)
          || (case when v_has_state then 'state = $3, ' else '' end)
          || (case when v_has_lga then 'lga = $4, ' else '' end)
          || (case when v_has_latitude then 'latitude = $5, ' else '' end)
          || (case when v_has_longitude then 'longitude = $6, ' else '' end)
          || (case when v_has_updated_at_snake then 'updated_at = $7, ' else '' end)
          || 'id = id where id = $8'
        ) using v_address, v_ward, v_state, v_lga, p_latitude, p_longitude, v_now, v_user_id;
      end if;
    exception when others then
      -- Never fail the business-profile update due to legacy mirroring issues.
      null;
    end;
  end if;

  select * into v_row from public.user_business_addresses where user_id = v_user_id;

  return jsonb_build_object(
    'ok', true,
    'businessAddress', v_row.business_address,
    'ward', v_row.ward,
    'state', v_row.state,
    'lga', v_row.lga,
    'latitude', v_row.latitude,
    'longitude', v_row.longitude,
    'updatedAt', v_row.updated_at
  );
exception
  when others then
    -- Avoid leaking internal details to end users, but keep a hint for developers.
    return jsonb_build_object('ok', false, 'error', 'server_error', 'detail', sqlerrm);
end;
$$;

-- Ensure authenticated can execute.
grant execute on function public.update_my_business_profile(text,text,text,text,double precision,double precision) to authenticated;
