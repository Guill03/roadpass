-- Trajets sur plusieurs postes (axe Kinshasa-Matadi).
--
-- Règle retenue (à confirmer sur le terrain) : on compte les postes franchis,
-- départ et arrivée compris. Le type de trajet est DÉDUIT, il n'est plus choisi
-- par l'usager :
--   moins de N postes franchis  -> demi_trajet
--   N postes ou plus            -> longue_distance
-- N = app_settings.long_trip_min_posts (3 par défaut), modifiable sans migration.
-- Le tarif est celui du poste de départ (là où l'on paie). Le justificatif est
-- valable à tous les postes du trajet et n'est « utilise » qu'au dernier.
--
-- scan_receipt, decide_passage, create_transaction et admin_list_transactions
-- sont REDÉFINIES ici : cette migration contient leur version active.

-- ---------------------------------------------------------------------
-- 1) Position des postes sur l'axe
-- ---------------------------------------------------------------------
alter table public.toll_posts
  add column if not exists sequence integer check (sequence >= 1);

create unique index if not exists idx_toll_posts_sequence_unique
  on public.toll_posts (sequence) where sequence is not null;

-- Kasangulu est le premier poste de l'axe en sortant de Kinshasa (source de
-- terrain). L'ordre de Kenge et Lukala n'est pas confirmé : il se saisit dans
-- l'écran admin « Postes de péage », rien n'est supposé ici.
update public.toll_posts
set sequence = 1
where upper(trim(code)) = 'KASANGULU' and sequence is null;

insert into public.app_settings (key, value)
values ('long_trip_min_posts', '3')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2) Destination et nombre de postes sur la transaction
--    (registration_post_id reste le poste de départ, où l'on paie)
-- ---------------------------------------------------------------------
alter table public.transactions
  add column if not exists destination_post_id uuid references public.toll_posts(id),
  add column if not exists posts_crossed integer check (posts_crossed >= 1);

alter table public.transactions
  drop constraint if exists transactions_trip_coherent;
alter table public.transactions
  add constraint transactions_trip_coherent
  check ((destination_post_id is null) = (posts_crossed is null));

-- ---------------------------------------------------------------------
-- 3) Un passage par poste et par justificatif
-- ---------------------------------------------------------------------
alter table public.passages drop constraint if exists passages_receipt_id_key;
alter table public.passages drop constraint if exists passages_receipt_post_unique;
alter table public.passages
  add constraint passages_receipt_post_unique unique (receipt_id, post_id);

-- ---------------------------------------------------------------------
-- 4) Fonctions internes (aucun accès client)
-- ---------------------------------------------------------------------
-- Postes d'un trajet, du départ vers l'arrivée. Sans destination (anciennes
-- transactions) : le seul poste de départ.
create or replace function public.trip_post_ids(p_origin uuid, p_destination uuid)
returns table (post_id uuid, step integer)
language sql
stable
security definer
set search_path = ''
as $$
  select p_origin, 0
  where p_destination is null or p_destination = p_origin
  union all
  select p.id, abs(p.sequence - o.sequence)::integer
  from public.toll_posts p
  join public.toll_posts o on o.id = p_origin
  join public.toll_posts d on d.id = p_destination
  where p_destination is not null
    and p_destination <> p_origin
    and p.is_active
    and p.sequence is not null
    and o.sequence is not null
    and d.sequence is not null
    and p.sequence between least(o.sequence, d.sequence)
                       and greatest(o.sequence, d.sequence);
$$;

create or replace function public.derive_trip(p_origin uuid, p_destination uuid)
returns table (posts_crossed integer, trip_type text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_origin public.toll_posts;
  v_destination public.toll_posts;
  v_count integer;
  v_threshold integer;
begin
  select * into v_origin
  from public.toll_posts where id = p_origin and is_active;
  if not found then
    raise exception 'Poste de départ introuvable ou inactif';
  end if;

  select * into v_destination
  from public.toll_posts where id = p_destination and is_active;
  if not found then
    raise exception 'Poste d''arrivée introuvable ou inactif';
  end if;

  if p_origin <> p_destination
     and (v_origin.sequence is null or v_destination.sequence is null) then
    raise exception 'L''ordre des postes sur l''axe n''est pas défini';
  end if;

  select count(*) into v_count
  from public.trip_post_ids(p_origin, p_destination);

  v_threshold := coalesce(
    (select nullif(value, '')::integer
     from public.app_settings where key = 'long_trip_min_posts'),
    3
  );

  return query
  select v_count,
         case when v_count >= v_threshold
              then 'longue_distance' else 'demi_trajet' end;
end;
$$;

revoke all on function public.trip_post_ids(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.derive_trip(uuid, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 5) Devis et création d'une transaction (nouvelle signature)
-- ---------------------------------------------------------------------
drop function if exists public.create_transaction(uuid, uuid, text);

create or replace function public.quote_transaction(
  p_vehicle_id uuid,
  p_origin_post_id uuid,
  p_destination_post_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_vehicle public.vehicles;
  v_trip record;
  v_tariff public.toll_tariffs;
  v_exemption public.exemptions;
begin
  if auth.uid() is null then
    raise exception 'Non authentifié';
  end if;

  select * into v_vehicle
  from public.vehicles
  where id = p_vehicle_id and user_id = auth.uid() and is_active;
  if not found then
    raise exception 'Véhicule introuvable ou désactivé';
  end if;
  if v_vehicle.category_id is null then
    raise exception 'Ce véhicule n''a pas de catégorie tarifaire';
  end if;

  select * into v_trip
  from public.derive_trip(p_origin_post_id, p_destination_post_id);

  select * into v_tariff
  from public.toll_tariffs
  where toll_post_id = p_origin_post_id
    and category_id = v_vehicle.category_id
    and trip_type = v_trip.trip_type
    and valid_from <= now()
    and (valid_until is null or valid_until > now())
  order by valid_from desc
  limit 1;
  if not found then
    raise exception 'Aucun tarif applicable pour cette combinaison';
  end if;

  select * into v_exemption
  from public.exemptions
  where vehicle_id = v_vehicle.id
    and status = 'active'
    and valid_from <= now()
    and (valid_until is null or valid_until > now())
  order by valid_from desc
  limit 1;

  return jsonb_build_object(
    'trip_type', v_trip.trip_type,
    'posts_crossed', v_trip.posts_crossed,
    'tariff_id', v_tariff.id,
    'amount', case when v_exemption.id is not null then 0 else v_tariff.amount end,
    'currency', v_tariff.currency,
    'exemption_id', v_exemption.id
  );
end;
$$;

create or replace function public.create_transaction(
  p_vehicle_id uuid,
  p_origin_post_id uuid,
  p_destination_post_id uuid
)
returns public.transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quote jsonb;
  v_result public.transactions;
begin
  -- Les règles (trajet, tarif, exemption) vivent dans quote_transaction :
  -- une seule définition pour l'aperçu et pour l'enregistrement.
  v_quote := public.quote_transaction(
    p_vehicle_id, p_origin_post_id, p_destination_post_id
  );

  if (v_quote ->> 'exemption_id') is not null then
    insert into public.transactions (
      user_id, vehicle_id, tariff_id, registration_post_id,
      destination_post_id, posts_crossed, trip_type,
      amount_due, currency, status, settlement_type, exemption_id
    )
    values (
      auth.uid(), p_vehicle_id, (v_quote ->> 'tariff_id')::uuid,
      p_origin_post_id, p_destination_post_id,
      (v_quote ->> 'posts_crossed')::integer, v_quote ->> 'trip_type',
      0, v_quote ->> 'currency', 'payee', 'exemption',
      (v_quote ->> 'exemption_id')::uuid
    )
    returning * into v_result;
  else
    insert into public.transactions (
      user_id, vehicle_id, tariff_id, registration_post_id,
      destination_post_id, posts_crossed, trip_type,
      amount_due, currency
    )
    values (
      auth.uid(), p_vehicle_id, (v_quote ->> 'tariff_id')::uuid,
      p_origin_post_id, p_destination_post_id,
      (v_quote ->> 'posts_crossed')::integer, v_quote ->> 'trip_type',
      (v_quote ->> 'amount')::numeric, v_quote ->> 'currency'
    )
    returning * into v_result;
  end if;

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------
-- 6) Contrôle à la barrière : scan et décision, poste par poste
--    Le poste de contrôle est choisi par l'agent (aucun lien agent-poste
--    n'existe encore) ; par défaut : prochain poste du trajet non franchi.
-- ---------------------------------------------------------------------
drop function if exists public.scan_receipt(text);
drop function if exists public.decide_passage(text, boolean, text);

create or replace function public.scan_receipt(
  p_qr_code text,
  p_post_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_agent public.profiles;
  v_receipt public.receipts;
  v_tx public.transactions;
  v_vehicle public.vehicles;
  v_category public.vehicle_categories;
  v_post public.toll_posts;
  v_destination public.toll_posts;
  v_post_id uuid;
  v_total integer;
  v_passed integer;
begin
  if auth.uid() is null then
    raise exception 'Non authentifié';
  end if;

  select * into v_agent from public.profiles where id = auth.uid();
  if v_agent.role is distinct from 'agent' then
    raise exception 'Action réservée aux agents';
  end if;
  if v_agent.account_status <> 'actif' then
    raise exception 'Votre compte agent est suspendu';
  end if;

  select * into v_receipt
  from public.receipts
  where qr_code = trim(p_qr_code)
  for update;
  if not found then
    raise exception 'Code QR inconnu';
  end if;
  if v_receipt.status <> 'valide' then
    raise exception 'Justificatif déjà utilisé ou invalide';
  end if;

  select * into v_tx
  from public.transactions
  where id = v_receipt.transaction_id
  for update;
  if v_tx.status not in ('payee', 'verifiee') then
    raise exception 'Cette transaction n''est pas payée';
  end if;

  v_post_id := coalesce(
    p_post_id,
    (select t.post_id
     from public.trip_post_ids(v_tx.registration_post_id, v_tx.destination_post_id) t
     where not exists (
       select 1 from public.passages ps
       where ps.receipt_id = v_receipt.id and ps.post_id = t.post_id
     )
     order by t.step
     limit 1)
  );
  if v_post_id is null then
    raise exception 'Tous les postes du trajet ont déjà été franchis';
  end if;
  if not exists (
    select 1
    from public.trip_post_ids(v_tx.registration_post_id, v_tx.destination_post_id) t
    where t.post_id = v_post_id
  ) then
    raise exception 'Ce poste ne fait pas partie du trajet de ce justificatif';
  end if;
  if exists (
    select 1 from public.passages ps
    where ps.receipt_id = v_receipt.id and ps.post_id = v_post_id
  ) then
    raise exception 'Ce poste a déjà été franchi';
  end if;

  if v_tx.status = 'payee' then
    update public.transactions set status = 'verifiee' where id = v_tx.id;
    v_tx.status := 'verifiee';
  end if;

  select count(*) into v_total
  from public.trip_post_ids(v_tx.registration_post_id, v_tx.destination_post_id);
  select count(*) into v_passed
  from public.passages ps where ps.receipt_id = v_receipt.id;

  select * into v_vehicle from public.vehicles where id = v_tx.vehicle_id;
  select * into v_category
  from public.vehicle_categories where id = v_vehicle.category_id;
  select * into v_post from public.toll_posts where id = v_post_id;
  select * into v_destination
  from public.toll_posts
  where id = coalesce(v_tx.destination_post_id, v_tx.registration_post_id);

  return jsonb_build_object(
    'qr_code', v_receipt.qr_code,
    'receipt_status', v_receipt.status,
    'transaction_status', v_tx.status,
    'trip_type', v_tx.trip_type,
    'amount_due', v_tx.amount_due,
    'currency', v_tx.currency,
    'registration_number', v_vehicle.registration_number,
    'brand', v_vehicle.brand,
    'model', v_vehicle.model,
    'category_code', v_category.code,
    'category_name', v_category.name,
    'post_id', v_post.id,
    'post_name', v_post.name,
    'destination_name', v_destination.name,
    'posts_crossed', v_total,
    'passed_count', v_passed
  );
end;
$$;

create or replace function public.decide_passage(
  p_qr_code text,
  p_authorized boolean,
  p_reason text default null,
  p_post_id uuid default null
)
returns public.passages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_agent public.profiles;
  v_receipt public.receipts;
  v_tx public.transactions;
  v_passage public.passages;
  v_post_id uuid;
  v_total integer;
  v_passed integer;
begin
  if auth.uid() is null then
    raise exception 'Non authentifié';
  end if;

  select * into v_agent from public.profiles where id = auth.uid();
  if v_agent.role is distinct from 'agent' then
    raise exception 'Action réservée aux agents';
  end if;
  if v_agent.account_status <> 'actif' then
    raise exception 'Votre compte agent est suspendu';
  end if;

  if not p_authorized and length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'Le motif du refus est obligatoire';
  end if;

  select * into v_receipt
  from public.receipts
  where qr_code = trim(p_qr_code)
  for update;
  if not found then
    raise exception 'Code QR inconnu';
  end if;
  if v_receipt.status <> 'valide' then
    raise exception 'Justificatif déjà utilisé ou invalide';
  end if;

  select * into v_tx
  from public.transactions
  where id = v_receipt.transaction_id
  for update;
  if v_tx.status <> 'verifiee' then
    raise exception 'Vérifiez d''abord le justificatif avant de décider';
  end if;

  v_post_id := coalesce(
    p_post_id,
    (select t.post_id
     from public.trip_post_ids(v_tx.registration_post_id, v_tx.destination_post_id) t
     where not exists (
       select 1 from public.passages ps
       where ps.receipt_id = v_receipt.id and ps.post_id = t.post_id
     )
     order by t.step
     limit 1)
  );
  if v_post_id is null then
    raise exception 'Tous les postes du trajet ont déjà été franchis';
  end if;
  if not exists (
    select 1
    from public.trip_post_ids(v_tx.registration_post_id, v_tx.destination_post_id) t
    where t.post_id = v_post_id
  ) then
    raise exception 'Ce poste ne fait pas partie du trajet de ce justificatif';
  end if;
  if exists (
    select 1 from public.passages ps
    where ps.receipt_id = v_receipt.id and ps.post_id = v_post_id
  ) then
    raise exception 'Ce poste a déjà été franchi';
  end if;

  insert into public.passages (
    receipt_id, agent_id, post_id, result, refusal_reason
  )
  values (
    v_receipt.id,
    auth.uid(),
    v_post_id,
    case when p_authorized then 'autorise' else 'refuse' end,
    case when p_authorized then null else trim(p_reason) end
  )
  returning * into v_passage;

  select count(*) into v_total
  from public.trip_post_ids(v_tx.registration_post_id, v_tx.destination_post_id);
  select count(*) into v_passed
  from public.passages ps where ps.receipt_id = v_receipt.id;

  if not p_authorized then
    -- Un refus à un poste met fin au trajet : justificatif invalide.
    update public.receipts set status = 'invalide' where id = v_receipt.id;
    update public.transactions set status = 'refusee' where id = v_tx.id;
  elsif v_passed >= v_total then
    update public.receipts set status = 'utilise' where id = v_receipt.id;
    update public.transactions set status = 'passage_valide' where id = v_tx.id;
  else
    -- Poste franchi, trajet pas terminé : on attend le poste suivant.
    update public.transactions set status = 'payee' where id = v_tx.id;
  end if;

  return v_passage;
end;
$$;

-- ---------------------------------------------------------------------
-- 7) Supervision : la liste admin affiche aussi la destination
-- ---------------------------------------------------------------------
create or replace function public.admin_list_transactions(
  p_status text default null,
  p_limit integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Action réservée aux administrateurs';
  end if;
  if p_status is not null and p_status not in (
    'initiee', 'en_attente_paiement', 'payee', 'verifiee',
    'passage_valide', 'echouee', 'annulee', 'refusee'
  ) then
    raise exception 'Statut invalide';
  end if;

  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    from (
      select
        t.id,
        t.status,
        t.settlement_type,
        t.trip_type,
        t.posts_crossed,
        t.amount_due,
        t.currency,
        t.created_at,
        v.registration_number,
        v.brand,
        v.model,
        trim(p.prenom || ' ' || p.nom) as user_name,
        tp.name as post_name,
        dp.name as destination_name,
        (select ps.result
         from public.passages ps
         join public.receipts r2 on r2.id = ps.receipt_id
         where r2.transaction_id = t.id
         order by ps.created_at desc
         limit 1) as passage_result,
        (select ps.refusal_reason
         from public.passages ps
         join public.receipts r2 on r2.id = ps.receipt_id
         where r2.transaction_id = t.id and ps.result = 'refuse'
         limit 1) as refusal_reason
      from public.transactions t
      join public.vehicles v on v.id = t.vehicle_id
      join public.profiles p on p.id = t.user_id
      join public.toll_posts tp on tp.id = t.registration_post_id
      left join public.toll_posts dp on dp.id = t.destination_post_id
      where p_status is null or t.status = p_status
      order by t.created_at desc
      limit least(greatest(coalesce(p_limit, 100), 1), 500)
    ) x
  );
end;
$$;

-- ---------------------------------------------------------------------
-- 8) Copie des tarifs en vigueur d'un poste vers un autre (admin).
--    À utiliser seulement si les tarifs sont confirmés identiques.
-- ---------------------------------------------------------------------
create or replace function public.admin_copy_tariffs(p_from uuid, p_to uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not public.is_admin() then
    raise exception 'Action réservée aux administrateurs';
  end if;
  if p_from = p_to then
    raise exception 'Les deux postes doivent être différents';
  end if;
  if not exists (select 1 from public.toll_posts where id = p_from)
     or not exists (select 1 from public.toll_posts where id = p_to) then
    raise exception 'Poste introuvable';
  end if;

  with inserted as (
    insert into public.toll_tariffs (
      toll_post_id, category_id, trip_type, amount, currency, valid_from
    )
    select p_to, t.category_id, t.trip_type, t.amount, t.currency, now()
    from public.toll_tariffs t
    where t.toll_post_id = p_from
      and t.valid_from <= now()
      and (t.valid_until is null or t.valid_until > now())
      and not exists (
        select 1 from public.toll_tariffs x
        where x.toll_post_id = p_to
          and x.category_id = t.category_id
          and x.trip_type = t.trip_type
          and (x.valid_until is null or x.valid_until > now())
      )
    returning 1
  )
  select count(*) into v_count from inserted;

  return v_count;
end;
$$;

-- ---------------------------------------------------------------------
-- 9) Journal d'audit : suivre aussi la position des postes et la destination
-- ---------------------------------------------------------------------
drop trigger if exists trg_audit_posts_ins on public.toll_posts;
create trigger trg_audit_posts_ins after insert on public.toll_posts
  for each row execute function public.audit_row_change('code,name,location,is_active,sequence');
drop trigger if exists trg_audit_posts_upd on public.toll_posts;
create trigger trg_audit_posts_upd after update on public.toll_posts
  for each row execute function public.audit_row_change('code,name,location,is_active,sequence');

drop trigger if exists trg_audit_transactions_ins on public.transactions;
create trigger trg_audit_transactions_ins after insert on public.transactions
  for each row execute function public.audit_row_change('status,settlement_type,amount_due,currency,vehicle_id,destination_post_id,posts_crossed');

-- ---------------------------------------------------------------------
-- 10) Droits d'exécution
-- ---------------------------------------------------------------------
revoke all on function public.quote_transaction(uuid, uuid, uuid) from public, anon;
grant execute on function public.quote_transaction(uuid, uuid, uuid) to authenticated;
revoke all on function public.create_transaction(uuid, uuid, uuid) from public, anon;
grant execute on function public.create_transaction(uuid, uuid, uuid) to authenticated;
revoke all on function public.scan_receipt(text, uuid) from public, anon;
grant execute on function public.scan_receipt(text, uuid) to authenticated;
revoke all on function public.decide_passage(text, boolean, text, uuid) from public, anon;
grant execute on function public.decide_passage(text, boolean, text, uuid) to authenticated;
revoke all on function public.admin_list_transactions(text, integer) from public, anon;
grant execute on function public.admin_list_transactions(text, integer) to authenticated;
revoke all on function public.admin_copy_tariffs(uuid, uuid) from public, anon;
grant execute on function public.admin_copy_tariffs(uuid, uuid) to authenticated;
