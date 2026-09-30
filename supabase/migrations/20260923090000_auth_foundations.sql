-- Auth foundations: profiles.role is the sole authorization source.
-- This migration deliberately follows the existing profiles migrations.

alter table public.profiles enable row level security;

-- SECURITY DEFINER lets RLS ask whether the caller is an administrator
-- without querying profiles through the calling policy (which would recurse).
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.profiles as profile
    where profile.id = auth.uid()
      and profile.role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Clients never receive UPDATE rights on profiles. This trigger is defense in
-- depth for privileged server-side writes such as create-agent.
create or replace function public.prevent_privilege_escalation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if new.id is distinct from old.id then
    raise exception 'Modification de l''identifiant interdite.';
  end if;

  if new.role is distinct from old.role
     and coalesce(auth.role(), '') <> 'service_role'
     and not public.is_admin() then
    raise exception 'Modification du rôle interdite.';
  end if;

  return new;
end;
$$;

revoke all on function public.prevent_privilege_escalation() from public;

drop trigger if exists trg_prevent_privilege_escalation on public.profiles;
create trigger trg_prevent_privilege_escalation
  before update on public.profiles
  for each row execute function public.prevent_privilege_escalation();

-- A profile is created only by the auth.users trigger. Contact changes go
-- through update_own_profile, which is restricted to auth.uid().
revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;

drop policy if exists "profiles_select_own_or_admin" on public.profiles;
drop policy if exists "profiles_insert_own" on public.profiles;

create policy "profiles_select_own_or_admin"
on public.profiles
for select
to authenticated
using (auth.uid() = id or public.is_admin());
