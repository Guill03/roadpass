-- Tests pgTAP : trajets sur plusieurs postes (type déduit, devis, justificatif
-- valable sur plusieurs postes, copie des tarifs).
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
  ('00000000-0000-0000-0000-0000000000f1', 'authenticated', 'authenticated', 'f1@roadpass.test'),
  ('00000000-0000-0000-0000-0000000000f2', 'authenticated', 'authenticated', 'f2agent@roadpass.test'),
  ('00000000-0000-0000-0000-0000000000f3', 'authenticated', 'authenticated', 'f3admin@roadpass.test');

select set_config('request.jwt.claim.role', 'service_role', true);
update public.profiles set role = 'agent'
  where id = '00000000-0000-0000-0000-0000000000f2';
update public.profiles set role = 'admin'
  where id = '00000000-0000-0000-0000-0000000000f3';
select set_config('request.jwt.claim.role', '', true);

-- Kasangulu a la position 1 (migration). Postes de test :
insert into public.toll_posts (code, name, location, sequence, is_active) values
  ('TESTP2', 'Poste test 2', 'Test', 2, true),
  ('TESTP3', 'Poste test 3', 'Test', 3, true),
  ('TESTX',  'Poste sans position', 'Test', null, true),
  ('TESTOFF', 'Poste inactif', 'Test', 4, false);

insert into public.vehicles (id, user_id, brand, model, registration_number, category, category_id)
select 'ffffffff-0000-0000-0000-000000000001'::uuid,
       '00000000-0000-0000-0000-0000000000f1'::uuid,
       'MultiBrand', 'Modele', 'TEST-F-001', c.name, c.id
from public.vehicle_categories c where upper(c.code) = 'V';

-- =====================================================================
-- 1) Devis : le type de trajet est déduit du nombre de postes franchis
-- =====================================================================
reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000f1');

select is(
  (select public.quote_transaction(
     'ffffffff-0000-0000-0000-000000000001'::uuid,
     (select id from public.toll_posts where code = 'KASANGULU'),
     (select id from public.toll_posts where code = 'KASANGULU')) ->> 'trip_type'),
  'demi_trajet', 'un seul poste : demi-trajet');
select is(
  (select public.quote_transaction(
     'ffffffff-0000-0000-0000-000000000001'::uuid,
     (select id from public.toll_posts where code = 'KASANGULU'),
     (select id from public.toll_posts where code = 'TESTP2')) ->> 'posts_crossed'),
  '2', 'deux postes franchis');
select is(
  (select public.quote_transaction(
     'ffffffff-0000-0000-0000-000000000001'::uuid,
     (select id from public.toll_posts where code = 'KASANGULU'),
     (select id from public.toll_posts where code = 'TESTP2')) ->> 'trip_type'),
  'demi_trajet', 'deux postes : encore un demi-trajet');
select is(
  (select public.quote_transaction(
     'ffffffff-0000-0000-0000-000000000001'::uuid,
     (select id from public.toll_posts where code = 'KASANGULU'),
     (select id from public.toll_posts where code = 'TESTP3')) ->> 'trip_type'),
  'longue_distance', 'trois postes : longue distance');
select is(
  (select public.quote_transaction(
     'ffffffff-0000-0000-0000-000000000001'::uuid,
     (select id from public.toll_posts where code = 'KASANGULU'),
     (select id from public.toll_posts where code = 'TESTP3')) ->> 'amount'),
  '5.00', 'longue distance catégorie V = 5.00 (tarif du poste de départ)');
select is(
  (select public.quote_transaction(
     'ffffffff-0000-0000-0000-000000000001'::uuid,
     (select id from public.toll_posts where code = 'KASANGULU'),
     (select id from public.toll_posts where code = 'KASANGULU')) ->> 'amount'),
  '2.50', 'demi-trajet catégorie V = 2.50');

select throws_ok(
  $$select public.quote_transaction(
      'ffffffff-0000-0000-0000-000000000001'::uuid,
      (select id from public.toll_posts where code = 'TESTP2'),
      (select id from public.toll_posts where code = 'TESTP3'))$$,
  'P0001', 'Aucun tarif applicable pour cette combinaison',
  'le tarif est celui du poste de départ : TESTP2 n''en a pas encore');
select throws_ok(
  $$select public.quote_transaction(
      'ffffffff-0000-0000-0000-000000000001'::uuid,
      (select id from public.toll_posts where code = 'KASANGULU'),
      (select id from public.toll_posts where code = 'TESTX'))$$,
  'P0001', 'L''ordre des postes sur l''axe n''est pas défini',
  'un poste sans position ne peut pas former un trajet');
select throws_ok(
  $$select public.quote_transaction(
      'ffffffff-0000-0000-0000-000000000001'::uuid,
      (select id from public.toll_posts where code = 'KASANGULU'),
      (select id from public.toll_posts where code = 'TESTOFF'))$$,
  'P0001', 'Poste d''arrivée introuvable ou inactif',
  'un poste inactif est refusé');

reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000f2');
select throws_ok(
  $$select public.quote_transaction(
      'ffffffff-0000-0000-0000-000000000001'::uuid,
      (select id from public.toll_posts where code = 'KASANGULU'),
      (select id from public.toll_posts where code = 'KASANGULU'))$$,
  'P0001', 'Véhicule introuvable ou désactivé',
  'on ne demande pas un devis pour le véhicule d''un autre');

reset role;
select tests_helper.as_user(null, 'anon');
select throws_ok(
  $$select public.quote_transaction(
      'ffffffff-0000-0000-0000-000000000001'::uuid,
      '00000000-0000-0000-0000-000000000000'::uuid,
      '00000000-0000-0000-0000-000000000000'::uuid)$$,
  '42501', null, 'anon ne peut pas demander de devis');

-- =====================================================================
-- 2) Le seuil est un réglage, pas du code
-- =====================================================================
reset role;
update public.app_settings set value = '2' where key = 'long_trip_min_posts';
select tests_helper.as_user('00000000-0000-0000-0000-0000000000f1');
select is(
  (select public.quote_transaction(
     'ffffffff-0000-0000-0000-000000000001'::uuid,
     (select id from public.toll_posts where code = 'KASANGULU'),
     (select id from public.toll_posts where code = 'TESTP2')) ->> 'trip_type'),
  'longue_distance', 'seuil abaissé à 2 : deux postes deviennent une longue distance');
reset role;
update public.app_settings set value = '3' where key = 'long_trip_min_posts';

-- =====================================================================
-- 3) Création d'un trajet sur 3 postes, puis contrôle poste par poste
-- =====================================================================
select tests_helper.as_user('00000000-0000-0000-0000-0000000000f1');
select lives_ok(
  $$select public.create_transaction(
      'ffffffff-0000-0000-0000-000000000001'::uuid,
      (select id from public.toll_posts where code = 'KASANGULU'),
      (select id from public.toll_posts where code = 'TESTP3'))$$,
  'l''usager enregistre un trajet sur trois postes');
select is((select posts_crossed from public.transactions), 3,
  'le nombre de postes est enregistré');
select is((select trip_type from public.transactions), 'longue_distance',
  'le type de trajet est déduit par la base');
select is((select amount_due from public.transactions), 5.00::numeric,
  'le montant est celui de la longue distance');
select is(
  (select destination_post_id from public.transactions),
  (select id from public.toll_posts where code = 'TESTP3'),
  'la destination est enregistrée');
select lives_ok(
  $$select public.pay_transaction_simulated((select id from public.transactions limit 1))$$,
  'l''usager paie une seule fois');

reset role;
select set_config('tests.qr', (select qr_code from public.receipts limit 1), true);

select tests_helper.as_user('00000000-0000-0000-0000-0000000000f2');
select is(
  (select public.scan_receipt(current_setting('tests.qr')) ->> 'posts_crossed'),
  '3', 'le scan indique trois postes');
select is(
  (select (public.scan_receipt(current_setting('tests.qr')) ->> 'post_id')::uuid),
  (select id from public.toll_posts where code = 'KASANGULU'),
  'sans poste choisi, le premier poste non franchi est proposé');
select lives_ok(
  $$select public.decide_passage(current_setting('tests.qr'), true, null)$$,
  'premier poste : passage autorisé');

reset role;
select is((select status from public.transactions limit 1), 'payee',
  'trajet pas terminé : la transaction reste « payee »');
select is((select status from public.receipts limit 1), 'valide',
  'le justificatif reste valable pour les postes suivants');

select tests_helper.as_user('00000000-0000-0000-0000-0000000000f2');
select is(
  (select (public.scan_receipt(current_setting('tests.qr')) ->> 'post_id')::uuid),
  (select id from public.toll_posts where code = 'TESTP2'),
  'le poste suivant est proposé');
select is(
  (select public.scan_receipt(current_setting('tests.qr')) ->> 'passed_count'),
  '1', 'un poste déjà franchi');
select throws_ok(
  $$select public.scan_receipt(
      current_setting('tests.qr'),
      (select id from public.toll_posts where code = 'KASANGULU'))$$,
  'P0001', 'Ce poste a déjà été franchi', 'un poste franchi ne se rescanne pas');
select throws_ok(
  $$select public.scan_receipt(
      current_setting('tests.qr'),
      (select id from public.toll_posts where code = 'TESTX'))$$,
  'P0001', 'Ce poste ne fait pas partie du trajet de ce justificatif',
  'un poste hors trajet est refusé');
select lives_ok(
  $$select public.decide_passage(
      current_setting('tests.qr'), true, null,
      (select id from public.toll_posts where code = 'TESTP2'))$$,
  'deuxième poste : passage autorisé');

select lives_ok(
  $$select public.scan_receipt(current_setting('tests.qr'))$$,
  'troisième poste : scan');
select lives_ok(
  $$select public.decide_passage(current_setting('tests.qr'), true, null)$$,
  'troisième poste : passage autorisé');

reset role;
select is((select status from public.transactions limit 1), 'passage_valide',
  'dernier poste franchi : « passage_valide »');
select is((select status from public.receipts limit 1), 'utilise',
  'le justificatif est « utilise » après le dernier poste');
select is((select count(*)::int from public.passages), 3,
  'un passage par poste');

select tests_helper.as_user('00000000-0000-0000-0000-0000000000f2');
select throws_ok(
  $$select public.scan_receipt(current_setting('tests.qr'))$$,
  'P0001', 'Justificatif déjà utilisé ou invalide',
  'le trajet terminé ne se rescanne pas');

-- =====================================================================
-- 4) Un refus à un poste met fin au trajet
-- =====================================================================
reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000f1');
select lives_ok(
  $$select public.create_transaction(
      'ffffffff-0000-0000-0000-000000000001'::uuid,
      (select id from public.toll_posts where code = 'KASANGULU'),
      (select id from public.toll_posts where code = 'TESTP3'))$$,
  'l''usager enregistre un second trajet sur trois postes');
select lives_ok(
  $$select public.pay_transaction_simulated(
      (select id from public.transactions where status = 'initiee' limit 1))$$,
  'il le paie');

reset role;
select set_config(
  'tests.qr',
  (select r.qr_code from public.receipts r
   join public.transactions t on t.id = r.transaction_id
   where t.status = 'payee'),
  true);

select tests_helper.as_user('00000000-0000-0000-0000-0000000000f2');
select lives_ok($$select public.scan_receipt(current_setting('tests.qr'))$$,
  'l''agent scanne au premier poste');
select lives_ok(
  $$select public.decide_passage(current_setting('tests.qr'), false, 'Plaque non conforme')$$,
  'l''agent refuse avec un motif');

reset role;
select is(
  (select count(*)::int from public.transactions where status = 'refusee'), 1,
  'la transaction est « refusee »');
select is(
  (select count(*)::int from public.receipts where status = 'invalide'), 1,
  'le justificatif est « invalide »');
select is((select count(*)::int from public.passages), 4,
  'le refus est enregistré comme passage');

-- =====================================================================
-- 5) Copie des tarifs d'un poste à l'autre
-- =====================================================================
select tests_helper.as_user('00000000-0000-0000-0000-0000000000f1');
select throws_ok(
  $$select public.admin_copy_tariffs(
      (select id from public.toll_posts where code = 'KASANGULU'),
      (select id from public.toll_posts where code = 'TESTP3'))$$,
  'P0001', 'Action réservée aux administrateurs',
  'un usager ne copie pas les tarifs');

reset role;
select tests_helper.as_user(null, 'anon');
select throws_ok(
  $$select public.admin_copy_tariffs(
      '00000000-0000-0000-0000-000000000000'::uuid,
      '00000000-0000-0000-0000-000000000001'::uuid)$$,
  '42501', null, 'anon ne peut pas copier les tarifs');

reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000f3');
select throws_ok(
  $$select public.admin_copy_tariffs(
      (select id from public.toll_posts where code = 'KASANGULU'),
      (select id from public.toll_posts where code = 'KASANGULU'))$$,
  'P0001', 'Les deux postes doivent être différents',
  'on ne copie pas un poste sur lui-même');
select is(
  (select public.admin_copy_tariffs(
     (select id from public.toll_posts where code = 'KASANGULU'),
     (select id from public.toll_posts where code = 'TESTP3'))),
  20, 'les 20 tarifs de Kasangulu sont copiés');
select is(
  (select public.admin_copy_tariffs(
     (select id from public.toll_posts where code = 'KASANGULU'),
     (select id from public.toll_posts where code = 'TESTP3'))),
  0, 'une seconde copie ne crée rien');
select ok(
  (select (public.admin_list_transactions(null, 10) -> 0 ->> 'destination_name') is not null),
  'la liste admin affiche la destination');

reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000f1');
select is(
  (select public.quote_transaction(
     'ffffffff-0000-0000-0000-000000000001'::uuid,
     (select id from public.toll_posts where code = 'TESTP3'),
     (select id from public.toll_posts where code = 'KASANGULU')) ->> 'trip_type'),
  'longue_distance', 'le trajet inverse (Lukala vers Kasangulu) est aussi une longue distance');

-- =====================================================================
-- 6) La position d'un poste est unique
-- =====================================================================
reset role;
select throws_ok(
  $$insert into public.toll_posts (code, name, location, sequence)
    values ('DOUBLON', 'Doublon', 'Test', 2)$$,
  '23505', null, 'deux postes ne peuvent pas avoir la même position');

select * from finish();
rollback;
