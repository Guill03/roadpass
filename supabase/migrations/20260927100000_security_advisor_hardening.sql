-- Durcissement suite aux alertes du Security Advisor Supabase (2026-10-01).

-- ---------------------------------------------------------------------
-- 1) Nettoyage de policies/fonction orphelines sur profiles, absentes de
--    toutes les migrations du dépôt (créées manuellement hors suivi).
--
--    Policies SELECT constatées sur public.profiles :
--      profiles_select_admin        : is_current_user_admin()
--      profiles_select_own          : id = auth.uid()
--      profiles_select_own_or_admin : auth.uid() = id OR is_admin()
--
--    Les policies RLS d'une même commande sont combinées par OR : les trois
--    conditions ci-dessus sont logiquement équivalentes (admin OU propre
--    ligne). profiles_select_admin et profiles_select_own n'accordent donc
--    aucun accès que profiles_select_own_or_admin n'accorde déjà : leur
--    suppression ne change aucun droit effectif.
-- ---------------------------------------------------------------------
drop policy if exists "profiles_select_admin" on public.profiles;
drop policy if exists "profiles_select_own" on public.profiles;

-- is_current_user_admin() n'a plus aucun dépendant après les DROP POLICY
-- ci-dessus (c'était profiles_select_admin qui bloquait sa suppression).
-- Son corps est strictement identique à is_admin() : reliquat d'un
-- renommage antérieur sans nettoyage.
drop function if exists public.is_current_user_admin();

-- ---------------------------------------------------------------------
-- 2) Fonctions purement internes (appelées uniquement par des triggers) :
--    jamais destinées à être invoquées directement via l'API REST
--    (/rest/v1/rpc/...). Aucun rôle applicatif n'a besoin d'EXECUTE dessus.
-- ---------------------------------------------------------------------
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.prevent_privilege_escalation() from public, anon, authenticated;
revoke all on function public.set_vehicles_updated_at() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) Ré-affirmation idempotente des fonctions déjà censées être
--    restreintes (is_admin, update_own_profile), au cas où la migration
--    d'origine (20260923090000) n'aurait pas été déployée sur ce projet.
-- ---------------------------------------------------------------------
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

revoke all on function public.update_own_profile(text, text, text, text) from public, anon;
grant execute on function public.update_own_profile(text, text, text, text) to authenticated;