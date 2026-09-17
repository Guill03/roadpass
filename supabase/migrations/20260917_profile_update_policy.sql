-- This RPC deliberately updates only contact fields: a client can never
-- promote its own profile by changing its role.
create or replace function public.update_own_profile(
  p_nom text,
  p_prenom text,
  p_email text,
  p_telephone text
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_profile public.profiles;
begin
  if auth.uid() is null then
    raise exception 'Non authentifié';
  end if;

  update public.profiles
  set nom = trim(p_nom),
      prenom = trim(p_prenom),
      email = lower(trim(p_email)),
      telephone = trim(p_telephone)
  where id = auth.uid()
  returning * into updated_profile;

  if updated_profile.id is null then
    raise exception 'Profil introuvable';
  end if;

  return updated_profile;
end;
$$;

revoke all on function public.update_own_profile(text, text, text, text) from public;
grant execute on function public.update_own_profile(text, text, text, text) to authenticated;
