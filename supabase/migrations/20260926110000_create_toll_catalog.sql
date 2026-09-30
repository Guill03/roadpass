-- Bloc C — Postes de péage, catégories de véhicules, tarifs.
-- Nouvelle migration dédiée : aucune migration existante n'est modifiée.

create extension if not exists pgcrypto;
create extension if not exists btree_gist;

-- ---------------------------------------------------------------------
-- 1) POSTES DE PÉAGE
-- ---------------------------------------------------------------------
create table if not exists public.toll_posts (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  location text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_toll_posts_code_unique
  on public.toll_posts (upper(trim(code)));

create trigger trg_set_toll_posts_updated_at
before update on public.toll_posts
for each row
execute function public.set_vehicles_updated_at(); -- fonction générique déjà créée au Bloc B

alter table public.toll_posts enable row level security;

create policy "toll_posts_select_authenticated"
on public.toll_posts
for select
to authenticated
using (true);

create policy "toll_posts_write_admin"
on public.toll_posts
for insert
to authenticated
with check (public.is_admin());

create policy "toll_posts_update_admin"
on public.toll_posts
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

revoke all on table public.toll_posts from anon;
revoke all on table public.toll_posts from authenticated;
grant select, insert, update on table public.toll_posts to authenticated;

-- Donnée réelle et sourcée (Chapitre 2, observation de terrain + Wikipédia) :
-- premier poste de l'axe Kinshasa-Matadi, RN1, ~40 km au sud de Kinshasa,
-- province du Kongo Central. Ce n'est PAS une donnée fictive de développement.
-- Gestion institutionnelle : ACGT (maître d'ouvrage délégué) / SOPECO
-- (concessionnaire percepteur), et non le FONER.
insert into public.toll_posts (code, name, location, is_active)
values (
  'KASANGULU',
  'Poste de péage de Kasangulu',
  'Route Nationale n°1 (RN1), territoire de Kasangulu, Kongo Central, RDC',
  true
)
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 2) CATÉGORIES DE VÉHICULES
-- ---------------------------------------------------------------------
create table if not exists public.vehicle_categories (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  description text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_vehicle_categories_code_unique
  on public.vehicle_categories (upper(trim(code)));

create trigger trg_set_vehicle_categories_updated_at
before update on public.vehicle_categories
for each row
execute function public.set_vehicles_updated_at();

alter table public.vehicle_categories enable row level security;

create policy "vehicle_categories_select_authenticated"
on public.vehicle_categories
for select
to authenticated
using (true);

create policy "vehicle_categories_insert_admin"
on public.vehicle_categories
for insert
to authenticated
with check (public.is_admin());

create policy "vehicle_categories_update_admin"
on public.vehicle_categories
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

revoke all on table public.vehicle_categories from anon;
revoke all on table public.vehicle_categories from authenticated;
grant select, insert, update on table public.vehicle_categories to authenticated;

-- Les 10 catégories réellement en usage au poste de Kasangulu (données de
-- terrain fournies par le porteur du projet). "description" reprend le nom
-- officiel ; les catégories V et VL n'ont pas de critère de distinction
-- documenté au-delà du nom (à préciser plus tard via l'admin si besoin).
insert into public.vehicle_categories (code, name, description) values
  ('V',   'Voiture simple',                       'Voiture simple.'),
  ('VL',  'Voiture légère',                        'Voiture légère.'),
  ('B30', 'Véhicule 20 à 30 places',                'Véhicule pouvant accueillir de 20 à 30 places.'),
  ('C2E', 'Véhicule à 2 essieux',                   'Véhicule à 2 essieux.'),
  ('C3E', 'Véhicule à 3 essieux',                   'Véhicule à 3 essieux.'),
  ('C4E', 'Véhicule à 4 essieux',                   'Véhicule à 4 essieux.'),
  ('C5E', 'Véhicule à 5 essieux',                   'Véhicule à 5 essieux.'),
  ('C6E', 'Véhicule à 6 essieux',                   'Véhicule à 6 essieux.'),
  ('C7E', 'Véhicule à 7 essieux',                   'Véhicule à 7 essieux.'),
  ('C8E', 'Véhicule à 8 essieux et plus',            'Véhicule à 8 essieux et plus.')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 3) LIEN VÉHICULE → CATÉGORIE (section 17 du cahier du Bloc C)
-- ---------------------------------------------------------------------
-- Nullable et ajouté en parallèle de l'ancien champ texte vehicles.category,
-- qui reste en place tant que la bascule complète n'est pas décidée.
-- vehicles.category est donc à considérer comme déprécié à partir de ce
-- point, sans être supprimé pour ne rien casser du Bloc B.
alter table public.vehicles
  add column if not exists category_id uuid references public.vehicle_categories(id);

create index if not exists idx_vehicles_category_id
  on public.vehicles (category_id);

-- ---------------------------------------------------------------------
-- 4) TARIFS
-- ---------------------------------------------------------------------
create table if not exists public.toll_tariffs (
  id uuid primary key default gen_random_uuid(),
  toll_post_id uuid not null references public.toll_posts(id),
  category_id uuid not null references public.vehicle_categories(id),
  -- 'demi_trajet' : l'usager ne dépasse pas un autre poste de péage sur son
  -- trajet (définition confirmée par le porteur du projet et jugée, sur le
  -- terrain, par le passage à un autre poste). Le calcul réel de cette
  -- condition à partir d'un itinéraire appartient au futur Bloc D — ce champ
  -- ne fait ici que stocker la valeur choisie/déclarée.
  trip_type text not null check (trip_type in ('longue_distance', 'demi_trajet')),
  amount numeric(12, 2) not null check (amount > 0),
  currency text not null default 'USD',
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint toll_tariffs_valid_period
    check (valid_until is null or valid_until > valid_from)
);

-- Empêche deux tarifs actifs simultanés pour la même combinaison
-- poste + catégorie + type de trajet sur des périodes qui se chevauchent
-- (section 12 du cahier — pas une simple vérification côté Flutter).
alter table public.toll_tariffs
  add constraint toll_tariffs_no_overlap
  exclude using gist (
    toll_post_id with =,
    category_id with =,
    trip_type with =,
    tstzrange(valid_from, coalesce(valid_until, 'infinity'), '[)') with &&
  );

create index if not exists idx_toll_tariffs_lookup
  on public.toll_tariffs (toll_post_id, category_id, trip_type, valid_from);

create trigger trg_set_toll_tariffs_updated_at
before update on public.toll_tariffs
for each row
execute function public.set_vehicles_updated_at();

alter table public.toll_tariffs enable row level security;

create policy "toll_tariffs_select_authenticated"
on public.toll_tariffs
for select
to authenticated
using (true);

create policy "toll_tariffs_insert_admin"
on public.toll_tariffs
for insert
to authenticated
with check (public.is_admin());

create policy "toll_tariffs_update_admin"
on public.toll_tariffs
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Pas de politique DELETE : un tarif historique n'est jamais supprimé
-- physiquement, seule sa valid_until change (fin de validité).
revoke all on table public.toll_tariffs from anon;
revoke all on table public.toll_tariffs from authenticated;
grant select, insert, update on table public.toll_tariffs to authenticated;

-- Tarifs réels du poste de Kasangulu (données de terrain fournies par le
-- porteur du projet, en USD). Insertion idempotente via NOT EXISTS plutôt
-- que ON CONFLICT, pour ne pas dépendre du comportement de l'arbitre sur
-- une contrainte d'exclusion.
insert into public.toll_tariffs (toll_post_id, category_id, trip_type, amount, currency)
select p.id, vc.id, t.trip_type, t.amount, 'USD'
from (
  values
    ('V',   'longue_distance', 5.00),
    ('V',   'demi_trajet',     2.50),
    ('VL',  'longue_distance', 10.00),
    ('VL',  'demi_trajet',     5.00),
    ('B30', 'longue_distance', 15.00),
    ('B30', 'demi_trajet',     7.50),
    ('C2E', 'longue_distance', 50.00),
    ('C2E', 'demi_trajet',     25.00),
    ('C3E', 'longue_distance', 80.00),
    ('C3E', 'demi_trajet',     40.00),
    ('C4E', 'longue_distance', 150.00),
    ('C4E', 'demi_trajet',     75.00),
    ('C5E', 'longue_distance', 190.00),
    ('C5E', 'demi_trajet',     95.00),
    ('C6E', 'longue_distance', 230.00),
    ('C6E', 'demi_trajet',     115.00),
    ('C7E', 'longue_distance', 260.00),
    ('C7E', 'demi_trajet',     130.00),
    ('C8E', 'longue_distance', 300.00),
    ('C8E', 'demi_trajet',     150.00)
) as t(category_code, trip_type, amount)
join public.vehicle_categories vc on upper(trim(vc.code)) = t.category_code
cross join (select id from public.toll_posts where upper(trim(code)) = 'KASANGULU') as p
where not exists (
  select 1 from public.toll_tariffs tt
  where tt.toll_post_id = p.id
    and tt.category_id = vc.id
    and tt.trip_type = t.trip_type
);
