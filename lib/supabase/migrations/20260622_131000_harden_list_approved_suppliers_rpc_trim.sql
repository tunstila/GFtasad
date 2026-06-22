-- Harden list_approved_suppliers to be whitespace/case tolerant.
-- Production-safe: CREATE OR REPLACE only.

begin;

create or replace function public.list_approved_suppliers()
returns setof public.users
language plpgsql
security definer
set search_path = public
as $$
declare
  v_my_role text;
begin
  select lower(trim(coalesce(u.role::text, ''))) into v_my_role
  from public.users u
  where u.id = auth.uid();

  if v_my_role not in ('fieldprovider', 'supplier', 'admin', 'superadmin', 'national') then
    raise exception 'not_authorized';
  end if;

  return query
  select u.*
  from public.users u
  where lower(trim(coalesce(u.role::text, ''))) = 'supplier'
    and lower(trim(coalesce(u.approvalstatus::text, ''))) = 'approved'
  order by u.username asc nulls last;
end;
$$;

revoke all on function public.list_approved_suppliers() from public;
grant execute on function public.list_approved_suppliers() to authenticated;

commit;
