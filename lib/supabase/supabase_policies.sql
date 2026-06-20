-- Row Level Security (RLS) policies for MediFlow

-- USERS
alter table public.users enable row level security;

-- Allow authenticated users to read user profiles
drop policy if exists "users_select_authenticated" on public.users;
create policy "users_select_authenticated" on public.users
for select to authenticated
using (true);

-- Allow inserts during signup/profile creation
-- IMPORTANT: WITH CHECK (true) is required here per app guidance.
drop policy if exists "users_insert_authenticated" on public.users;
create policy "users_insert_authenticated" on public.users
for insert to authenticated
with check (true);

-- Allow profile updates
drop policy if exists "users_update_authenticated" on public.users;
create policy "users_update_authenticated" on public.users
for update to authenticated
using (true)
with check (true);

-- Allow deletes (optional, but keeps behavior consistent with other tables)
drop policy if exists "users_delete_authenticated" on public.users;
create policy "users_delete_authenticated" on public.users
for delete to authenticated
using (true);

-- COMMODITIES
alter table public.commodities enable row level security;
drop policy if exists "commodities_all_authenticated" on public.commodities;
create policy "commodities_all_authenticated" on public.commodities
for all to authenticated
using (true)
with check (true);

-- STOCK MOVEMENTS
alter table public.stock_movements enable row level security;
drop policy if exists "stock_movements_all_authenticated" on public.stock_movements;
create policy "stock_movements_all_authenticated" on public.stock_movements
for all to authenticated
using (true)
with check (true);

-- TEST RECORDS
alter table public.test_records enable row level security;
drop policy if exists "test_records_all_authenticated" on public.test_records;
create policy "test_records_all_authenticated" on public.test_records
for all to authenticated
using (true)
with check (true);

-- DELIVERIES
alter table public.deliveries enable row level security;
drop policy if exists "deliveries_all_authenticated" on public.deliveries;
create policy "deliveries_all_authenticated" on public.deliveries
for all to authenticated
using (true)
with check (true);

-- =========================================================
-- PRODUCTION POLICY SET (RECOMMENDED)
--
-- The policies above are intentionally permissive. To enforce the role rules
-- described in your requirements (fieldProvider scoped access, supplier-scoped
-- requests, admin/superAdmin global read, national roles read-only), apply the
-- SQL below in your Supabase SQL Editor.
--
-- This file does not deploy automatically.
-- =========================================================

-- Helper: read current user's app role from public.users.
create or replace function public.app_role()
returns text
language sql
stable
as $$
  select coalesce((select role from public.users where id = auth.uid()), 'unknown');
$$;

create or replace function public.is_adminish()
returns boolean
language sql
stable
as $$
  select public.app_role() in ('admin','superAdmin','sfhTeam');
$$;

-- ===== TEST RECORDS =====
drop policy if exists test_records_all_authenticated on public.test_records;
create policy test_records_select_scoped on public.test_records
for select to authenticated
using (public.is_adminish() or userid = auth.uid() or "userId" = auth.uid() or user_id = auth.uid());

create policy test_records_insert_own on public.test_records
for insert to authenticated
with check (public.app_role() in ('fieldProvider','superAdmin') and (userid = auth.uid() or "userId" = auth.uid() or user_id = auth.uid()));

create policy test_records_update_own on public.test_records
for update to authenticated
using (public.app_role() in ('fieldProvider','superAdmin') and (userid = auth.uid() or "userId" = auth.uid() or user_id = auth.uid()))
with check (public.app_role() in ('fieldProvider','superAdmin') and (userid = auth.uid() or "userId" = auth.uid() or user_id = auth.uid()));

-- ===== STOCK MOVEMENTS =====
drop policy if exists stock_movements_all_authenticated on public.stock_movements;
create policy stock_movements_select_scoped on public.stock_movements
for select to authenticated
using (public.is_adminish() or userid = auth.uid() or "userId" = auth.uid() or user_id = auth.uid());

create policy stock_movements_insert_own on public.stock_movements
for insert to authenticated
with check (public.app_role() in ('fieldProvider','superAdmin') and (userid = auth.uid() or "userId" = auth.uid() or user_id = auth.uid()));

create policy stock_movements_update_own on public.stock_movements
for update to authenticated
using (public.app_role() in ('fieldProvider','superAdmin') and (userid = auth.uid() or "userId" = auth.uid() or user_id = auth.uid()))
with check (public.app_role() in ('fieldProvider','superAdmin') and (userid = auth.uid() or "userId" = auth.uid() or user_id = auth.uid()));

-- ===== STOCK REQUESTS (RESTOCK) =====
alter table public.stock_requests enable row level security;
drop policy if exists stock_requests_all_authenticated on public.stock_requests;

create policy stock_requests_select_scoped on public.stock_requests
for select to authenticated
using (
  public.is_adminish()
  or providerid = auth.uid() or "providerId" = auth.uid()
  or supplierid = auth.uid() or "supplierId" = auth.uid()
);

create policy stock_requests_insert_provider on public.stock_requests
for insert to authenticated
with check (public.app_role() in ('fieldProvider','superAdmin') and (providerid = auth.uid() or "providerId" = auth.uid()));

create policy stock_requests_update_supplier on public.stock_requests
for update to authenticated
using (public.is_adminish() or supplierid = auth.uid() or "supplierId" = auth.uid())
with check (public.is_adminish() or supplierid = auth.uid() or "supplierId" = auth.uid());

-- ===== DELIVERIES =====
drop policy if exists deliveries_all_authenticated on public.deliveries;
create policy deliveries_select_scoped on public.deliveries
for select to authenticated
using (
  public.is_adminish()
  or providerid = auth.uid() or "providerId" = auth.uid()
  or supplierid = auth.uid() or "supplierId" = auth.uid()
);

create policy deliveries_insert_supplier on public.deliveries
for insert to authenticated
with check (public.app_role() in ('supplier','superAdmin') and (supplierid = auth.uid() or "supplierId" = auth.uid()));

create policy deliveries_update_supplier_or_provider on public.deliveries
for update to authenticated
using (public.is_adminish() or supplierid = auth.uid() or "supplierId" = auth.uid() or providerid = auth.uid() or "providerId" = auth.uid())
with check (public.is_adminish() or supplierid = auth.uid() or "supplierId" = auth.uid() or providerid = auth.uid() or "providerId" = auth.uid());

-- National roles are implicitly read-only because they are not granted insert/update by policies above.
