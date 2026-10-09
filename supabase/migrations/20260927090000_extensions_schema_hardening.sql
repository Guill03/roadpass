-- Durcissement sécurité Supabase : les extensions ne doivent pas vivre
-- dans le schéma public (alerte "Extension in Public" du Security Advisor).
-- On les déplace vers le schéma dédié "extensions" (convention Supabase),
-- en ne les déplaçant que si elles ne s'y trouvent pas déjà.

create schema if not exists extensions;

do $$
begin
  if exists (
    select 1 from pg_extension e
    join pg_namespace n on n.oid = e.extnamespace
    where e.extname = 'pgcrypto' and n.nspname = 'public'
  ) then
    alter extension pgcrypto set schema extensions;
  end if;

  if exists (
    select 1 from pg_extension e
    join pg_namespace n on n.oid = e.extnamespace
    where e.extname = 'btree_gist' and n.nspname = 'public'
  ) then
    alter extension btree_gist set schema extensions;
  end if;
end $$;
