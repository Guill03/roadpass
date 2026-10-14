-- Tests pgTAP des règles d'accès RoadPass (RLS, grants, RPC, rôles).
-- Exécution locale : supabase start && supabase test db --local
-- Chaque test s'exécute dans une transaction annulée à la fin (rollback).
-- no_plan() : pas de compteur à maintenir à la main.

begin;
select * from no_plan();

-- ---------------------------------------------------------------------
-- Aide : changer d'identité (rôle Postgres + claims JWT).
-- Toujours précédée de « reset role; » pour revenir au rôle de départ.
-- ---------------------------------------------------------------------
create schema tests_helper;
create function tests_helper.as_user(p_uid uuid, p_role text default 'authenticated')
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claim.role', p_role, true);
  execute format('set local role %I', p_role);
end;
$$;

-- ---------------------------------------------------------------------
-- Données de départ (rôle propriétaire, contourne la RLS)
--   A = usager 1, B = usager 2, agent, admin
-- ---------------------------------------------------------------------
insert into auth.users (id, aud, role, email)
values
  ('00000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'a@roadpass.test'),
  ('00000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'b@roadpass.test'),
  ('00000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'agent@roadpass.test'),
  ('00000000-0000-0000-0000-0000000000ad', 'authenticated', 'authenticated', 'admin@roadpass.test');

-- Le déclencheur anti-escalade n'autorise le changement de rôle que pour
-- service_role : on simule ce contexte le temps de l'amorçage.
select set_config('request.jwt.claim.role', 'service_role', true);
update public.profiles set role = 'agent'
  where id = '00000000-0000-0000-0000-0000000000a1';
update public.profiles set role = 'admin'
  where id = '00000000-0000-0000-0000-0000000000ad';
select set_config('request.jwt.claim.role', '', true);

insert into public.vehicles (id, user_id, brand, model, registration_number, category, category_id)
select 'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
       '00000000-0000-0000-0000-00000000000a'::uuid,
       'SeedA', 'Modele', 'TEST-A-001', c.name, c.id
from public.vehicle_categories c where upper(c.code) = 'V';

insert into public.vehicles (id, user_id, brand, model, registration_number, category, category_id)
select 'bbbbbbbb-0000-0000-0000-000000000001'::uuid,
       '00000000-0000-0000-0000-00000000000b'::uuid,
       'SeedB', 'Modele', 'TEST-B-001', c.name, c.id
from public.vehicle_categories c where upper(c.code) = 'V';

-- =====================================================================
-- 1) NON AUTHENTIFIÉ (anon)
-- =====================================================================
reset role;
select tests_helper.as_user(null, 'anon');

select throws_ok($$select * from public.profiles$$, '42501', null,
  'anon ne peut pas lire profiles');
select throws_ok($$select * from public.vehicles$$, '42501', null,
  'anon ne peut pas lire vehicles');
select throws_ok($$select * from public.toll_posts$$, '42501', null,
  'anon ne peut pas lire les postes');
select throws_ok($$select * from public.transactions$$, '42501', null,
  'anon ne peut pas lire transactions');
select throws_ok(
  $$select public.create_transaction(
      'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
      '00000000-0000-0000-0000-000000000000'::uuid,
      '00000000-0000-0000-0000-000000000000'::uuid)$$,
  '42501', null, 'anon ne peut pas appeler create_transaction');

-- =====================================================================
-- 2) USAGER A
-- =====================================================================
reset role;
select tests_helper.as_user('00000000-0000-0000-0000-00000000000a');

select is((select count(*)::int from public.profiles), 1,
  'A ne voit que son profil');
select is((select count(*)::int from public.vehicles), 1,
  'A ne voit que son véhicule');
select ok((select count(*) from public.toll_posts) >= 1,
  'A peut lire les postes');
select ok((select count(*) from public.toll_tariffs) >= 1,
  'A peut lire les tarifs');
select ok((select count(*) from public.vehicle_categories) >= 1,
  'A peut lire les catégories');

select throws_ok(
  $$update public.profiles set role = 'admin'
    where id = '00000000-0000-0000-0000-00000000000a'$$,
  '42501', null, 'A ne peut pas se promouvoir admin (UPDATE direct refusé)');
select lives_ok(
  $$select public.update_own_profile('Alpha', 'User', 'a@roadpass.test', '+243000000001')$$,
  'A peut modifier ses coordonnées via la RPC');

select throws_ok(
  $$insert into public.vehicles (user_id, brand, model, registration_number, category)
    values ('00000000-0000-0000-0000-00000000000b', 'X', 'Y', 'TEST-HACK-1', 'V')$$,
  '42501', null, 'A ne peut pas créer un véhicule pour B');
select lives_ok(
  $$insert into public.vehicles (id, user_id, brand, model, registration_number, category, category_id)
    select 'aaaaaaaa-0000-0000-0000-000000000002',
           '00000000-0000-0000-0000-00000000000a',
           'Deux', 'Modele', 'TEST-A-002', c.name, c.id
    from public.vehicle_categories c where upper(c.code) = 'V'$$,
  'A peut créer son propre véhicule');
select is(
  (select count(*)::int from public.vehicles
   where user_id = '00000000-0000-0000-0000-00000000000b'), 0,
  'A ne voit pas les véhicules de B');
select lives_ok(
  $$update public.vehicles set brand = 'Hacked'
    where id = 'bbbbbbbb-0000-0000-0000-000000000001'$$,
  'la modification du véhicule de B ne lève pas d''erreur (0 ligne touchée)');
select throws_ok(
  $$update public.vehicles
    set user_id = '00000000-0000-0000-0000-00000000000b'
    where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$,
  '42501', null, 'A ne peut pas transférer son véhicule à B');
select throws_ok(
  $$delete from public.vehicles where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$,
  '42501', null, 'A ne peut pas supprimer un véhicule');

select throws_ok(
  $$insert into public.toll_posts (code, name, location)
    values ('HACK', 'Hack', 'Hack')$$,
  '42501', null, 'A ne peut pas créer un poste');
select throws_ok(
  $$insert into public.toll_tariffs (toll_post_id, category_id, trip_type, amount, currency)
    select p.id, c.id, 'demi_trajet', 1, 'USD'
    from public.toll_posts p, public.vehicle_categories c
    where p.code = 'KASANGULU' and upper(c.code) = 'V'$$,
  '42501', null, 'A ne peut pas créer un tarif');
select throws_ok(
  $$insert into public.transactions (user_id, vehicle_id, tariff_id, registration_post_id, trip_type, amount_due, currency)
    select '00000000-0000-0000-0000-00000000000a', 'aaaaaaaa-0000-0000-0000-000000000001',
           t.id, t.toll_post_id, 'longue_distance', 0.01, 'USD'
    from public.toll_tariffs t limit 1$$,
  '42501', null, 'A ne peut pas insérer une transaction directement');
select throws_ok(
  $$select * from public.app_settings$$, '42501', null,
  'A ne peut pas lire les réglages serveur');

select lives_ok(
  $$select public.create_transaction(
      'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
      (select id from public.toll_posts where code = 'KASANGULU'),
      (select id from public.toll_posts where code = 'KASANGULU'))$$,
  'A crée une transaction pour son véhicule');
select throws_ok(
  $$select public.create_transaction(
      'bbbbbbbb-0000-0000-0000-000000000001'::uuid,
      (select id from public.toll_posts where code = 'KASANGULU'),
      (select id from public.toll_posts where code = 'KASANGULU'))$$,
  'P0001', null, 'A ne peut pas créer une transaction pour le véhicule de B');
select is((select count(*)::int from public.transactions), 1,
  'A voit sa transaction');
select is((select amount_due from public.transactions), 2.50::numeric,
  'le montant vient du tarif serveur (catégorie V, un seul poste = demi-trajet = 2.50)');
select is((select status from public.transactions), 'initiee',
  'la transaction naît « initiee »');

select lives_ok(
  $$select public.pay_transaction_simulated((select id from public.transactions limit 1))$$,
  'A paie (simulation)');
select is((select status from public.transactions), 'payee',
  'la transaction est « payee »');
select is((select count(*)::int from public.receipts), 1,
  'un justificatif est généré automatiquement');
select throws_ok(
  $$select public.pay_transaction_simulated((select id from public.transactions limit 1))$$,
  'P0001', null, 'A ne peut pas payer deux fois');
select throws_ok(
  $$select public.cancel_transaction((select id from public.transactions limit 1))$$,
  'P0001', null, 'A ne peut pas annuler une transaction payée');
select throws_ok(
  $$select public.scan_receipt('RP-INCONNU')$$,
  'P0001', null, 'A (usager) ne peut pas scanner un justificatif');
select throws_ok(
  $$select public.admin_find_vehicle('TEST-B-001')$$,
  'P0001', null, 'A ne peut pas utiliser les fonctions admin');
select throws_ok(
  $$select public.admin_create_exemption(
      'aaaaaaaa-0000-0000-0000-000000000001'::uuid, 'auto-exemption', null)$$,
  'P0001', null, 'A ne peut pas s''accorder une exemption');
select throws_ok(
  $$select public.admin_open_prepaid_account('00000000-0000-0000-0000-00000000000a'::uuid)$$,
  'P0001', null, 'A ne peut pas s''ouvrir un compte prépayé');

-- =====================================================================
-- 3) USAGER B : aucune fuite des données de A
-- =====================================================================
reset role;
select tests_helper.as_user('00000000-0000-0000-0000-00000000000b');

select is((select count(*)::int from public.profiles), 1,
  'B ne voit que son profil');
select is(
  (select count(*)::int from public.vehicles
   where id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0,
  'B ne voit pas le véhicule de A');
select is((select count(*)::int from public.transactions), 0,
  'B ne voit pas les transactions de A');
select is((select count(*)::int from public.receipts), 0,
  'B ne voit pas les justificatifs de A');
select is((select count(*)::int from public.payments), 0,
  'B ne voit pas les paiements de A');
select throws_ok(
  $$select public.pay_transaction_simulated(
      (select id from public.transactions limit 1))$$,
  'P0001', null, 'B ne peut pas payer la transaction de A');
select throws_ok(
  $$select public.pay_transaction_with_account(
      (select id from public.transactions limit 1))$$,
  'P0001', null, 'B ne peut pas régler par compte la transaction de A');

-- Retour au rôle propriétaire : vérifier que les attaques n'ont rien modifié
reset role;
select is(
  (select brand from public.vehicles where id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  'SeedB', 'le véhicule de B est intact après la tentative de A');
select is(
  (select user_id from public.vehicles where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  '00000000-0000-0000-0000-00000000000a'::uuid,
  'le véhicule de A appartient toujours à A');
select set_config('tests.qr', (select qr_code from public.receipts limit 1), true);

-- =====================================================================
-- 4) AGENT
-- =====================================================================
reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000a1');

select is((select count(*)::int from public.profiles), 1,
  'l''agent ne voit que son profil');
select is((select count(*)::int from public.vehicles), 0,
  'l''agent ne voit pas les véhicules des usagers');
select ok((select count(*) from public.toll_posts) >= 1,
  'l''agent peut lire les postes');
select throws_ok(
  $$insert into public.toll_tariffs (toll_post_id, category_id, trip_type, amount, currency)
    select p.id, c.id, 'demi_trajet', 1, 'USD'
    from public.toll_posts p, public.vehicle_categories c
    where p.code = 'KASANGULU' and upper(c.code) = 'V'$$,
  '42501', null, 'l''agent ne peut pas modifier les tarifs');
select throws_ok(
  $$select public.admin_find_vehicle('TEST-A-001')$$,
  'P0001', null, 'l''agent ne reçoit pas les droits admin');
select lives_ok(
  $$select public.scan_receipt(current_setting('tests.qr'))$$,
  'l''agent scanne un justificatif payé');
select throws_ok(
  $$select public.decide_passage(current_setting('tests.qr'), false, null)$$,
  'P0001', null, 'un refus sans motif est rejeté');
select lives_ok(
  $$select public.decide_passage(current_setting('tests.qr'), true, null)$$,
  'l''agent autorise le passage');
select throws_ok(
  $$select public.scan_receipt(current_setting('tests.qr'))$$,
  'P0001', null, 'un justificatif utilisé ne peut pas être rescanné');
select is((select count(*)::int from public.passages), 1,
  'l''agent voit son passage');
select throws_ok(
  $$insert into public.passages (receipt_id, agent_id, post_id, result)
    select r.id, '00000000-0000-0000-0000-0000000000a1', p.id, 'autorise'
    from public.receipts r, public.toll_posts p limit 1$$,
  '42501', null, 'l''agent ne peut pas insérer un passage directement');

reset role;
select is(
  (select status from public.transactions limit 1), 'passage_valide',
  'la transaction est « passage_valide »');
select is(
  (select status from public.receipts limit 1), 'utilise',
  'le justificatif est « utilise »');

-- Le propriétaire voit le passage, un tiers non
select tests_helper.as_user('00000000-0000-0000-0000-00000000000a');
select is((select count(*)::int from public.passages), 1,
  'A voit le passage de sa transaction');
reset role;
select tests_helper.as_user('00000000-0000-0000-0000-00000000000b');
select is((select count(*)::int from public.passages), 0,
  'B ne voit pas le passage de A');

-- =====================================================================
-- 5) ADMINISTRATEUR
-- =====================================================================
reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000ad');

select is(
  (select count(*)::int from public.profiles
   where id in (
     '00000000-0000-0000-0000-00000000000a',
     '00000000-0000-0000-0000-00000000000b',
     '00000000-0000-0000-0000-0000000000a1',
     '00000000-0000-0000-0000-0000000000ad')), 4,
  'l''admin lit les profils des autres utilisateurs');
select throws_ok(
  $$update public.profiles set role = 'user'
    where id = '00000000-0000-0000-0000-0000000000a1'$$,
  '42501', null, 'même l''admin ne modifie pas profiles directement');
select throws_ok(
  $$select public.scan_receipt('RP-INCONNU')$$,
  'P0001', null, 'l''admin ne reçoit pas les droits agent');
select is((select count(*)::int from public.vehicles), 0,
  'l''admin ne lit pas les véhicules des usagers directement');
select lives_ok(
  $$insert into public.vehicle_categories (code, name, description)
    values ('TESTCAT', 'Catégorie test', 'Test')$$,
  'l''admin crée une catégorie');
select lives_ok(
  $$insert into public.toll_posts (code, name, location)
    values ('TESTPOST', 'Poste test', 'Nulle part')$$,
  'l''admin crée un poste');
select throws_ok(
  $$insert into public.toll_tariffs (toll_post_id, category_id, trip_type, amount, currency)
    select p.id, c.id, 'longue_distance', 9, 'USD'
    from public.toll_posts p, public.vehicle_categories c
    where p.code = 'KASANGULU' and upper(c.code) = 'V'$$,
  '23P01', null, 'deux tarifs actifs qui se chevauchent sont refusés');
select throws_ok(
  $$insert into public.toll_tariffs (toll_post_id, category_id, trip_type, amount, currency)
    select p.id, c.id, 'demi_trajet', -1, 'USD'
    from public.toll_posts p, public.vehicle_categories c
    where p.code = 'TESTPOST' and upper(c.code) = 'TESTCAT'$$,
  '23514', null, 'un montant négatif est refusé');
select lives_ok(
  $$select public.admin_find_vehicle('test-a-001')$$,
  'l''admin retrouve un véhicule par immatriculation');
select lives_ok(
  $$select public.admin_create_exemption(
      'aaaaaaaa-0000-0000-0000-000000000001'::uuid, 'Véhicule de l''État', null)$$,
  'l''admin accorde une exemption');
select throws_ok(
  $$select public.admin_create_exemption(
      'aaaaaaaa-0000-0000-0000-000000000001'::uuid, 'doublon', null)$$,
  'P0001', null, 'une seconde exemption active sur le même véhicule est refusée');
select lives_ok(
  $$select public.admin_open_prepaid_account('00000000-0000-0000-0000-00000000000a'::uuid)$$,
  'l''admin ouvre un compte prépayé pour A');
select lives_ok(
  $$select public.admin_recharge_prepaid_account(
      (select id from public.prepaid_accounts
       where user_id = '00000000-0000-0000-0000-00000000000a'), 3)$$,
  'l''admin recharge le compte de 3 passages');
select throws_ok(
  $$select public.admin_recharge_prepaid_account(
      (select id from public.prepaid_accounts
       where user_id = '00000000-0000-0000-0000-00000000000a'), 0)$$,
  'P0001', null, 'une recharge de 0 passage est refusée');

-- =====================================================================
-- 6) USAGER A : exemption et compte prépayé
-- =====================================================================
reset role;
select tests_helper.as_user('00000000-0000-0000-0000-00000000000a');

select lives_ok(
  $$select public.create_transaction(
      'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
      (select id from public.toll_posts where code = 'KASANGULU'),
      (select id from public.toll_posts where code = 'KASANGULU'))$$,
  'A crée une transaction sur son véhicule exempté');
select is(
  (select amount_due from public.transactions where settlement_type = 'exemption'),
  0::numeric, 'la transaction exemptée est à 0');
select is(
  (select status from public.transactions where settlement_type = 'exemption'),
  'payee', 'la transaction exemptée naît « payee »');

select lives_ok(
  $$select public.create_transaction(
      'aaaaaaaa-0000-0000-0000-000000000002'::uuid,
      (select id from public.toll_posts where code = 'KASANGULU'),
      (select id from public.toll_posts where code = 'KASANGULU'))$$,
  'A crée une transaction sur son second véhicule (non exempté)');
select is(
  (select amount_due from public.transactions
   where vehicle_id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  2.50::numeric, 'demi-trajet catégorie V = 2.50');
select lives_ok(
  $$select public.pay_transaction_with_account(
      (select id from public.transactions
       where vehicle_id = 'aaaaaaaa-0000-0000-0000-000000000002'))$$,
  'A règle avec son compte prépayé');
select is((select balance from public.prepaid_accounts), 2,
  'le solde passe de 3 à 2');
select is(
  (select settlement_type from public.transactions
   where vehicle_id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  'sous_provision', 'le mode de règlement est « sous_provision »');
select is((select count(*)::int from public.account_movements), 2,
  'A voit une recharge et un débit');
select is((select count(*)::int from public.receipts), 3,
  'un justificatif par transaction réglée (3 au total)');
select throws_ok(
  $$update public.prepaid_accounts set balance = 999$$,
  '42501', null, 'A ne peut pas modifier son solde directement');
select throws_ok(
  $$insert into public.account_movements (account_id, movement_type, quantity, created_by)
    select id, 'recharge', 100, user_id from public.prepaid_accounts$$,
  '42501', null, 'A ne peut pas s''ajouter des passages');

reset role;
select tests_helper.as_user('00000000-0000-0000-0000-00000000000b');
select is((select count(*)::int from public.prepaid_accounts), 0,
  'B ne voit pas le compte prépayé de A');
select is((select count(*)::int from public.exemptions), 0,
  'B ne voit pas les exemptions de A');

-- =====================================================================
-- 7) STRUCTURE : droits d'exécution et RLS
-- =====================================================================
reset role;
select ok(not has_function_privilege('anon', 'public.scan_receipt(text, uuid)', 'execute'),
  'anon ne peut pas exécuter scan_receipt');
select ok(not has_function_privilege('anon', 'public.create_transaction(uuid, uuid, uuid)', 'execute'),
  'anon ne peut pas exécuter create_transaction');
select ok(not has_function_privilege('authenticated', 'public.handle_new_user()', 'execute'),
  'authenticated ne peut pas exécuter handle_new_user');
select ok(not has_function_privilege('authenticated', 'public.generate_receipt_on_payment()', 'execute'),
  'authenticated ne peut pas exécuter generate_receipt_on_payment');
select ok(
  (select bool_and(c.relrowsecurity)
   from pg_class c
   where c.oid in (
     'public.profiles'::regclass, 'public.vehicles'::regclass,
     'public.toll_posts'::regclass, 'public.vehicle_categories'::regclass,
     'public.toll_tariffs'::regclass, 'public.transactions'::regclass,
     'public.payments'::regclass, 'public.receipts'::regclass,
     'public.passages'::regclass, 'public.exemptions'::regclass,
     'public.prepaid_accounts'::regclass, 'public.account_movements'::regclass,
     'public.app_settings'::regclass)),
  'la RLS est activée sur toutes les tables métier');

select * from finish();
rollback;
