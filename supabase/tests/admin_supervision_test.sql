-- Tests pgTAP : supervision administrateur des transactions.
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
  ('00000000-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'c1@roadpass.test'),
  ('00000000-0000-0000-0000-0000000000cd', 'authenticated', 'authenticated', 'cadmin@roadpass.test');

select set_config('request.jwt.claim.role', 'service_role', true);
update public.profiles set role = 'admin'
  where id = '00000000-0000-0000-0000-0000000000cd';
select set_config('request.jwt.claim.role', '', true);

insert into public.vehicles (id, user_id, brand, model, registration_number, category, category_id)
select 'cccccccc-0000-0000-0000-000000000001'::uuid,
       '00000000-0000-0000-0000-0000000000c1'::uuid,
       'SupBrand', 'Modele', 'TEST-C-001', c.name, c.id
from public.vehicle_categories c where upper(c.code) = 'V';

-- Un usager crée une transaction
reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000c1');
select lives_ok(
  $$select public.create_transaction(
      'cccccccc-0000-0000-0000-000000000001'::uuid,
      (select id from public.toll_posts where code = 'KASANGULU'),
      (select id from public.toll_posts where code = 'KASANGULU'))$$,
  'l''usager crée une transaction');
select throws_ok($$select public.admin_list_transactions(null, 10)$$,
  'P0001', null, 'un usager ne peut pas lister les transactions (admin)');
select throws_ok($$select public.admin_transactions_summary()$$,
  'P0001', null, 'un usager ne peut pas lire le résumé admin');

-- Anonyme
reset role;
select tests_helper.as_user(null, 'anon');
select throws_ok($$select public.admin_list_transactions(null, 10)$$,
  '42501', null, 'anon ne peut pas exécuter admin_list_transactions');

-- Administrateur
reset role;
select tests_helper.as_user('00000000-0000-0000-0000-0000000000cd');
select ok(
  (select jsonb_array_length(public.admin_list_transactions(null, 50))) >= 1,
  'l''admin voit au moins la transaction créée');
select lives_ok(
  $$select public.admin_list_transactions('annulee', 50)$$,
  'le filtre par statut valide est accepté');
select throws_ok($$select public.admin_list_transactions('inconnu', 10)$$,
  'P0001', null, 'un statut invalide est rejeté');
select ok(
  (public.admin_transactions_summary() ->> 'total')::int >= 1,
  'le résumé compte au moins une transaction');
select ok(
  ((public.admin_transactions_summary() -> 'by_status' ->> 'initiee')::int) >= 1,
  'le résumé distingue les statuts');
select is(
  (select count(*)::int from public.transactions), 0,
  'l''admin ne lit toujours pas la table transactions directement');

reset role;
select * from finish();
rollback;
