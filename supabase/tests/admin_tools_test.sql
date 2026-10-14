-- Tests pgTAP : journal d'audit, suspension d'agent, statistiques, réglages.
-- Lancer avec : supabase test db --local
begin;
select * from no_plan();

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

insert into auth.users (id, aud, role, email)
values
  ('00000000-0000-0000-0000-0000000000d1', 'authenticated', 'authenticated', 'd1@roadpass.test'),
  ('00000000-0000-0000-0000-0000000000d2', 'authenticated', 'authenticated', 'd2agent@roadpass.test'),
  ('00000000-0000-0000-0000-0000000000d3', 'authenticated', 'authenticated', 'd3admin@roadpass.test');

select set_config('request.jwt.claim.role', 'service_role', true);
update public.profiles set role = 'agent'
  where id = '00000000-0000-0000-0000-0000000000d2';
update public.profiles set role = 'admin'
  where id = '00000000-0000-0000-0000-0000000000d3';
select set_config('request.jwt.claim.role', '', true);

insert into public.vehicles (id, user_id, brand, model, registration_number, category, category_id)
select 'dddddddd-0000-0000-0000-000000000001'::uuid,
       '00000000-0000-0000-0000-0000000000d1'::uuid,
       'ToolsBrand', 'Modele', 'TEST-D-001', c.name, c.id
from public.vehicle_categories c where upper(c.code) = 'V';

-- =====================================================================
-- 1) Journal alimenté automatiquement
-- =====================================================================
reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000d1');
select lives_ok(
  $$select public.create_transaction(
      'dddddddd-0000-0000-0000-000000000001'::uuid,
      (select id from public.toll_posts where code = 'KASANGULU'),
      (select id from public.toll_posts where code = 'KASANGULU'))$$,
  'l''usager crée une première transaction');
select lives_ok(
  $$select public.pay_transaction_simulated(
      (select id from public.transactions where status = 'initiee' limit 1))$$,
  'l''usager la paie (simulation active par défaut)');
select lives_ok(
  $$select public.create_transaction(
      'dddddddd-0000-0000-0000-000000000001'::uuid,
      (select id from public.toll_posts where code = 'KASANGULU'),
      (select id from public.toll_posts where code = 'KASANGULU'))$$,
  'l''usager crée une seconde transaction');

reset role;
select ok(
  exists (
    select 1 from public.audit_log
    where target_entity = 'transactions'
      and action = 'update'
      and details -> 'status' ->> 'to' = 'payee'
  ),
  'le passage à « payee » est journalisé');
select ok(
  exists (
    select 1 from public.audit_log
    where target_entity = 'payments' and action = 'insert'
  ),
  'la création du paiement est journalisée');
select ok(
  exists (
    select 1 from public.audit_log
    where target_entity = 'transactions'
      and action = 'insert'
      and user_id = '00000000-0000-0000-0000-0000000000d1'
  ),
  'l''auteur (usager connecté) est enregistré');

-- =====================================================================
-- 2) Le journal est fermé aux clients et en ajout seul
-- =====================================================================
select tests_helper.as_user('00000000-0000-0000-0000-0000000000d1');
select throws_ok($$select * from public.audit_log$$, '42501', null,
  'un usager ne lit pas le journal directement');
select throws_ok($$select public.admin_list_audit_log(null, 10)$$,
  'P0001', 'Action réservée aux administrateurs',
  'un usager ne lit pas le journal via la fonction admin');

reset role;
select tests_helper.as_user(null, 'anon');
select throws_ok($$select public.admin_list_audit_log(null, 10)$$,
  '42501', null, 'anon ne peut pas exécuter admin_list_audit_log');

reset role;
select throws_ok(
  $$update public.audit_log set action = 'x'$$,
  'P0001', 'Le journal d''audit est en ajout seul',
  'le journal refuse toute modification');
select throws_ok(
  $$delete from public.audit_log$$,
  'P0001', 'Le journal d''audit est en ajout seul',
  'le journal refuse toute suppression');

select tests_helper.as_user('00000000-0000-0000-0000-0000000000d3');
select ok(
  (select jsonb_array_length(public.admin_list_audit_log('transactions', 50))) >= 2,
  'l''admin lit les entrées du journal filtrées par objet');
select is(
  (select jsonb_array_length(public.admin_list_audit_log('inconnu', 50))), 0,
  'un filtre sans correspondance renvoie une liste vide');

-- =====================================================================
-- 3) Suspension d'un agent (RG11)
-- =====================================================================
select throws_ok(
  $$select public.admin_set_account_status(
      '00000000-0000-0000-0000-0000000000d1'::uuid, 'suspendu')$$,
  'P0001', 'Seuls les comptes agents peuvent être suspendus',
  'on ne suspend pas un usager');
select throws_ok(
  $$select public.admin_set_account_status(
      '00000000-0000-0000-0000-0000000000d3'::uuid, 'suspendu')$$,
  'P0001', 'Seuls les comptes agents peuvent être suspendus',
  'un admin ne peut pas se suspendre');
select throws_ok(
  $$select public.admin_set_account_status(
      '00000000-0000-0000-0000-0000000000d2'::uuid, 'inconnu')$$,
  'P0001', 'Statut invalide', 'un statut invalide est rejeté');
select lives_ok(
  $$select public.admin_set_account_status(
      '00000000-0000-0000-0000-0000000000d2'::uuid, 'suspendu')$$,
  'l''admin suspend un agent');

reset role;
select is(
  (select account_status from public.profiles
   where id = '00000000-0000-0000-0000-0000000000d2'),
  'suspendu', 'le statut est enregistré');
select ok(
  exists (
    select 1 from public.audit_log
    where target_entity = 'profiles'
      and details -> 'account_status' ->> 'to' = 'suspendu'
      and user_id = '00000000-0000-0000-0000-0000000000d3'
  ),
  'la suspension est journalisée avec l''admin comme auteur');

select tests_helper.as_user('00000000-0000-0000-0000-0000000000d2');
select throws_ok(
  $$select public.scan_receipt('RP-INCONNU')$$,
  'P0001', 'Votre compte agent est suspendu',
  'un agent suspendu ne peut pas scanner');
select throws_ok(
  $$select public.decide_passage('RP-INCONNU', true, null)$$,
  'P0001', 'Votre compte agent est suspendu',
  'un agent suspendu ne peut pas décider');
select throws_ok(
  $$select public.admin_set_account_status(
      '00000000-0000-0000-0000-0000000000d2'::uuid, 'actif')$$,
  'P0001', 'Action réservée aux administrateurs',
  'un agent ne peut pas se réactiver lui-même');

reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000d1');
select throws_ok(
  $$select public.admin_set_account_status(
      '00000000-0000-0000-0000-0000000000d2'::uuid, 'actif')$$,
  'P0001', 'Action réservée aux administrateurs',
  'un usager ne peut pas réactiver un agent');

reset role;
select tests_helper.as_user(null, 'anon');
select throws_ok(
  $$select public.admin_set_account_status(
      '00000000-0000-0000-0000-0000000000d2'::uuid, 'actif')$$,
  '42501', null, 'anon ne peut pas exécuter admin_set_account_status');

reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000d3');
select lives_ok(
  $$select public.admin_set_account_status(
      '00000000-0000-0000-0000-0000000000d2'::uuid, 'actif')$$,
  'l''admin réactive l''agent');

reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000d2');
select throws_ok(
  $$select public.scan_receipt('RP-INCONNU')$$,
  'P0001', 'Code QR inconnu',
  'l''agent réactivé passe le contrôle de statut (le code est inconnu)');

-- =====================================================================
-- 4) Statistiques
-- =====================================================================
reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000d3');
select is(
  (select jsonb_array_length(public.admin_statistics(7) -> 'days')), 7,
  'sept jours demandés, sept jours renvoyés');
select is(
  (select jsonb_array_length(public.admin_statistics(1000) -> 'days')), 365,
  'la période est plafonnée à 365 jours');
select ok(
  (select sum((e ->> 'transactions')::int)
   from jsonb_array_elements(public.admin_statistics(7) -> 'days') e) >= 2,
  'les deux transactions du jour sont comptées');
select ok(
  jsonb_array_length(public.admin_statistics(7) -> 'by_category') >= 1,
  'la répartition par catégorie est fournie');

reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000d1');
select throws_ok($$select public.admin_statistics(7)$$,
  'P0001', 'Action réservée aux administrateurs',
  'un usager ne lit pas les statistiques');

-- =====================================================================
-- 5) Réglage de la simulation de paiement
-- =====================================================================
reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000d3');
select is(public.admin_get_payment_simulation(), true,
  'la simulation est active par défaut');
select lives_ok($$select public.admin_set_payment_simulation(false)$$,
  'l''admin désactive la simulation');
select is(public.admin_get_payment_simulation(), false,
  'le réglage est relu à false');

reset role;
select ok(
  exists (
    select 1 from public.audit_log
    where target_entity = 'app_settings'
      and details -> 'value' ->> 'to' = 'false'
      and user_id = '00000000-0000-0000-0000-0000000000d3'
  ),
  'le changement de réglage est journalisé');

select tests_helper.as_user('00000000-0000-0000-0000-0000000000d1');
select throws_ok(
  $$select public.pay_transaction_simulated(
      (select id from public.transactions where status = 'initiee' limit 1))$$,
  'P0001', 'La simulation de paiement est désactivée',
  'simulation coupée : l''usager ne peut plus « payer »');
select throws_ok($$select public.admin_set_payment_simulation(true)$$,
  'P0001', 'Action réservée aux administrateurs',
  'un usager ne réactive pas la simulation');
select throws_ok($$select public.admin_get_payment_simulation()$$,
  'P0001', 'Action réservée aux administrateurs',
  'un usager ne lit pas le réglage');

reset role;
select tests_helper.as_user(null, 'anon');
select throws_ok($$select public.admin_set_payment_simulation(true)$$,
  '42501', null, 'anon ne peut pas exécuter admin_set_payment_simulation');

reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000d3');
select lives_ok($$select public.admin_set_payment_simulation(true)$$,
  'l''admin peut réactiver la simulation');

reset role;
select * from finish();
rollback;
