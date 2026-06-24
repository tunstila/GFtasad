-- Performance indexes for login tracker
--
-- Keeps superAdmin login tracker queries fast at scale.

begin;

create index if not exists idx_user_login_sessions_status on public.user_login_sessions (status);
create index if not exists idx_user_login_sessions_signed_in_at_status on public.user_login_sessions (signed_in_at, status);

commit;
