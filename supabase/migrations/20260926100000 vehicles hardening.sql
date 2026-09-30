-- Bloc B — durcissement, sans modifier les migrations existantes.

-- 1) Une même immatriculation ne doit pas pouvoir exister deux fois dans le
--    système (tous utilisateurs confondus), quelle que soit la casse ou les
--    espaces superflus. Un index unique fonctionnel évite de forcer un
--    format de stockage particulier : ce n'est pas une règle de validation
--    du format, seulement une garantie d'unicité logique.
create unique index if not exists idx_vehicles_registration_number_unique
  on public.vehicles (upper(trim(registration_number)));

-- 2) Grants explicites plutôt que de dépendre du comportement par défaut de
--    Supabase (auto_expose_new_tables). Aligné sur le style déjà utilisé
--    pour public.profiles : le client authentifié ne reçoit jamais le
--    privilège DELETE, en plus du blocage déjà fait par la policy RLS
--    "vehicles_block_delete". anon n'a aucun accès.
revoke all on table public.vehicles from anon;
revoke all on table public.vehicles from authenticated;
grant select, insert, update on table public.vehicles to authenticated;