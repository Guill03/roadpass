-- Bloc H — Journal d'audit, suspension des agents (RG11), statistiques,
-- réglage de la simulation de paiement.
-- Les fonctions scan_receipt et decide_passage sont REDÉFINIES ici (la
-- dernière définition gagne) pour refuser un agent suspendu.

-- ---------------------------------------------------------------------
-- 1) Statut de compte (entité UTILISATEUR.statut du Chapitre 3)
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists account_status text not null default 'actif'
    check (account_status in ('actif', 'suspendu'));

-- ---------------------------------------------------------------------
-- 2) Journal d'audit (entité JOURNAL) : aucune lecture ni écriture directe
-- ---------------------------------------------------------------------
create table if not exists public.audit_log (
  id uuid primary key default gen_random_uuid(),
  -- Nul pour les actions automatiques (aucune session utilisateur).
  user_id uuid references public.profiles(id) on delete set null,
  action text not null,
  target_entity text not null,
  target_id text,
  details jsonb not null default '{}'::jsonb,
  -- clock_timestamp() et non now() : now() est figé pour toute la transaction,
  -- ce qui rendrait l'ordre des entrées ambigu quand une fonction modifie
  -- plusieurs lignes d'un coup.
  created_at timestamptz not null default clock_timestamp()
);

create index if not exists idx_audit_log_created
  on public.audit_log (created_at desc);
create index if not exists idx_audit_log_entity
  on public.audit_log (target_entity, created_at desc);

alter table public.audit_log enable row level security;
revoke all on table public.audit_log from anon, authenticated;
-- Aucune policy, aucun grant : seules les fonctions ci-dessous y accèdent.

-- Le journal est en ajout seul : toute modification ou suppression échoue.
create or replace function public.audit_log_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Le journal d''audit est en ajout seul';
end;
$$;

drop trigger if exists trg_audit_log_immutable on public.audit_log;
create trigger trg_audit_log_immutable
before update or delete on public.audit_log
for each row execute function public.audit_log_immutable();

create or replace function public.write_audit(
  p_action text,
  p_entity text,
  p_target_id text,
  p_details jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.audit_log (user_id, action, target_entity, target_id, details)
  values (auth.uid(), p_action, p_entity, p_target_id, coalesce(p_details, '{}'::jsonb));
end;
$$;

-- Fonction générique de trigger. Argument 1 : colonnes à journaliser,
-- séparées par des virgules. INSERT : valeurs enregistrées. UPDATE : seules
-- les colonnes qui ont changé (de -> vers) ; aucune ligne si rien d'audité
-- n'a changé.
create or replace function public.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cols text[] := string_to_array(coalesce(tg_argv[0], ''), ',');
  v_new jsonb := to_jsonb(new);
  v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else null end;
  v_details jsonb := '{}'::jsonb;
  v_col text;
begin
  foreach v_col in array v_cols loop
    if tg_op = 'INSERT' then
      v_details := v_details || jsonb_build_object(v_col, v_new -> v_col);
    elsif (v_old -> v_col) is distinct from (v_new -> v_col) then
      v_details := v_details || jsonb_build_object(
        v_col,
        jsonb_build_object('from', v_old -> v_col, 'to', v_new -> v_col)
      );
    end if;
  end loop;

  if tg_op = 'UPDATE' and v_details = '{}'::jsonb then
    return new;
  end if;

  perform public.write_audit(
    lower(tg_op),
    tg_table_name,
    coalesce(v_new ->> 'id', v_new ->> 'key'),
    v_details
  );
  return new;
end;
$$;

revoke all on function public.write_audit(text, text, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.audit_row_change()
  from public, anon, authenticated;
revoke all on function public.audit_log_immutable()
  from public, anon, authenticated;

-- Branchements (un trigger par table et par opération)
drop trigger if exists trg_audit_transactions_ins on public.transactions;
create trigger trg_audit_transactions_ins after insert on public.transactions
  for each row execute function public.audit_row_change('status,settlement_type,amount_due,currency,vehicle_id');
drop trigger if exists trg_audit_transactions_upd on public.transactions;
create trigger trg_audit_transactions_upd after update on public.transactions
  for each row execute function public.audit_row_change('status,settlement_type');

drop trigger if exists trg_audit_payments_ins on public.payments;
create trigger trg_audit_payments_ins after insert on public.payments
  for each row execute function public.audit_row_change('status,payment_method,external_reference,transaction_id');

drop trigger if exists trg_audit_receipts_ins on public.receipts;
create trigger trg_audit_receipts_ins after insert on public.receipts
  for each row execute function public.audit_row_change('transaction_id');
drop trigger if exists trg_audit_receipts_upd on public.receipts;
create trigger trg_audit_receipts_upd after update on public.receipts
  for each row execute function public.audit_row_change('status');

drop trigger if exists trg_audit_passages_ins on public.passages;
create trigger trg_audit_passages_ins after insert on public.passages
  for each row execute function public.audit_row_change('result,refusal_reason,receipt_id');

drop trigger if exists trg_audit_exemptions_ins on public.exemptions;
create trigger trg_audit_exemptions_ins after insert on public.exemptions
  for each row execute function public.audit_row_change('vehicle_id,reason,valid_until');
drop trigger if exists trg_audit_exemptions_upd on public.exemptions;
create trigger trg_audit_exemptions_upd after update on public.exemptions
  for each row execute function public.audit_row_change('status,valid_until');

drop trigger if exists trg_audit_prepaid_ins on public.prepaid_accounts;
create trigger trg_audit_prepaid_ins after insert on public.prepaid_accounts
  for each row execute function public.audit_row_change('user_id');
drop trigger if exists trg_audit_prepaid_upd on public.prepaid_accounts;
create trigger trg_audit_prepaid_upd after update on public.prepaid_accounts
  for each row execute function public.audit_row_change('balance,status');

drop trigger if exists trg_audit_movements_ins on public.account_movements;
create trigger trg_audit_movements_ins after insert on public.account_movements
  for each row execute function public.audit_row_change('movement_type,quantity,account_id,transaction_id');

drop trigger if exists trg_audit_posts_ins on public.toll_posts;
create trigger trg_audit_posts_ins after insert on public.toll_posts
  for each row execute function public.audit_row_change('code,name,location,is_active');
drop trigger if exists trg_audit_posts_upd on public.toll_posts;
create trigger trg_audit_posts_upd after update on public.toll_posts
  for each row execute function public.audit_row_change('code,name,location,is_active');

drop trigger if exists trg_audit_categories_ins on public.vehicle_categories;
create trigger trg_audit_categories_ins after insert on public.vehicle_categories
  for each row execute function public.audit_row_change('code,name,is_active');
drop trigger if exists trg_audit_categories_upd on public.vehicle_categories;
create trigger trg_audit_categories_upd after update on public.vehicle_categories
  for each row execute function public.audit_row_change('code,name,description,is_active');

drop trigger if exists trg_audit_tariffs_ins on public.toll_tariffs;
create trigger trg_audit_tariffs_ins after insert on public.toll_tariffs
  for each row execute function public.audit_row_change('toll_post_id,category_id,trip_type,amount,currency,valid_from');
drop trigger if exists trg_audit_tariffs_upd on public.toll_tariffs;
create trigger trg_audit_tariffs_upd after update on public.toll_tariffs
  for each row execute function public.audit_row_change('amount,valid_until');

-- Changements de rôle ou de statut de compte (pas les simples coordonnées).
drop trigger if exists trg_audit_profiles_upd on public.profiles;
create trigger trg_audit_profiles_upd after update on public.profiles
  for each row execute function public.audit_row_change('role,account_status');

drop trigger if exists trg_audit_settings_ins on public.app_settings;
create trigger trg_audit_settings_ins after insert on public.app_settings
  for each row execute function public.audit_row_change('key,value');
drop trigger if exists trg_audit_settings_upd on public.app_settings;
create trigger trg_audit_settings_upd after update on public.app_settings
  for each row execute function public.audit_row_change('value');

-- ---------------------------------------------------------------------
-- 3) Lecture du journal par l'administrateur
-- ---------------------------------------------------------------------
create or replace function public.admin_list_audit_log(
  p_entity text default null,
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

  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    from (
      select
        l.id,
        l.action,
        l.target_entity,
        l.target_id,
        l.details,
        l.created_at,
        nullif(trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), '') as user_name,
        p.role as user_role
      from public.audit_log l
      left join public.profiles p on p.id = l.user_id
      where p_entity is null or l.target_entity = p_entity
      order by l.created_at desc
      limit least(greatest(coalesce(p_limit, 100), 1), 500)
    ) x
  );
end;
$$;

-- ---------------------------------------------------------------------
-- 4) Suspension / réactivation d'un agent (RG11)
-- ---------------------------------------------------------------------
create or replace function public.admin_set_account_status(
  p_user_id uuid,
  p_status text
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target public.profiles;
  v_result public.profiles;
begin
  if not public.is_admin() then
    raise exception 'Action réservée aux administrateurs';
  end if;
  if p_status not in ('actif', 'suspendu') then
    raise exception 'Statut invalide';
  end if;

  select * into v_target from public.profiles where id = p_user_id;
  if not found then
    raise exception 'Utilisateur introuvable';
  end if;
  if v_target.role <> 'agent' then
    raise exception 'Seuls les comptes agents peuvent être suspendus';
  end if;

  update public.profiles
  set account_status = p_status
  where id = p_user_id
  returning * into v_result;

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------
-- 5) scan_receipt / decide_passage : refuser un agent suspendu
--    (corps identiques à 20260930090000, sauf le contrôle de l'agent)
-- ---------------------------------------------------------------------
create or replace function public.scan_receipt(p_qr_code text)
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

  if v_tx.status = 'payee' then
    update public.transactions set status = 'verifiee' where id = v_tx.id;
    v_tx.status := 'verifiee';
  end if;

  select * into v_vehicle from public.vehicles where id = v_tx.vehicle_id;
  select * into v_category
  from public.vehicle_categories where id = v_vehicle.category_id;
  select * into v_post
  from public.toll_posts where id = v_tx.registration_post_id;

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
    'post_name', v_post.name
  );
end;
$$;

create or replace function public.decide_passage(
  p_qr_code text,
  p_authorized boolean,
  p_reason text default null
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

  insert into public.passages (
    receipt_id, agent_id, post_id, result, refusal_reason
  )
  values (
    v_receipt.id,
    auth.uid(),
    v_tx.registration_post_id,
    case when p_authorized then 'autorise' else 'refuse' end,
    case when p_authorized then null else trim(p_reason) end
  )
  returning * into v_passage;

  update public.receipts
  set status = case when p_authorized then 'utilise' else 'invalide' end
  where id = v_receipt.id;

  update public.transactions
  set status = case when p_authorized then 'passage_valide' else 'refusee' end
  where id = v_tx.id;

  return v_passage;
end;
$$;

-- ---------------------------------------------------------------------
-- 6) Statistiques (lecture seule)
-- ---------------------------------------------------------------------
create or replace function public.admin_statistics(p_days integer default 30)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_days integer := greatest(least(coalesce(p_days, 30), 365), 1);
  v_today date := (now() at time zone 'utc')::date;
begin
  if not public.is_admin() then
    raise exception 'Action réservée aux administrateurs';
  end if;

  return jsonb_build_object(
    'days', (
      select jsonb_agg(
        jsonb_build_object(
          'day', d.day,
          'transactions', coalesce(t.n, 0),
          'validated', coalesce(t.v, 0)
        )
        order by d.day
      )
      from (
        select g::date as day
        from generate_series((v_today - (v_days - 1))::timestamp, v_today::timestamp, interval '1 day') g
      ) d
      left join (
        select (created_at at time zone 'utc')::date as day,
               count(*) as n,
               count(*) filter (where status = 'passage_valide') as v
        from public.transactions
        group by 1
      ) t on t.day = d.day
    ),
    'by_category', coalesce((
      select jsonb_agg(
        jsonb_build_object('code', x.code, 'name', x.name, 'count', x.n)
        order by x.n desc, x.code
      )
      from (
        select c.code, c.name, count(t.id) as n
        from public.vehicle_categories c
        left join public.vehicles v on v.category_id = c.id
        left join public.transactions t on t.vehicle_id = v.id
        group by c.id, c.code, c.name
      ) x
    ), '[]'::jsonb),
    'passages', jsonb_build_object(
      'autorise', (select count(*) from public.passages where result = 'autorise'),
      'refuse', (select count(*) from public.passages where result = 'refuse')
    )
  );
end;
$$;

-- ---------------------------------------------------------------------
-- 7) Réglage de la simulation de paiement par l'administrateur
-- ---------------------------------------------------------------------
create or replace function public.admin_get_payment_simulation()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Action réservée aux administrateurs';
  end if;
  return coalesce(
    (select value from public.app_settings
     where key = 'payment_simulation_enabled') = 'true',
    false
  );
end;
$$;

create or replace function public.admin_set_payment_simulation(p_enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Action réservée aux administrateurs';
  end if;
  if p_enabled is null then
    raise exception 'Valeur invalide';
  end if;
  insert into public.app_settings (key, value)
  values ('payment_simulation_enabled', case when p_enabled then 'true' else 'false' end)
  on conflict (key) do update set value = excluded.value;
  return p_enabled;
end;
$$;

-- ---------------------------------------------------------------------
-- 8) Droits d'exécution
-- ---------------------------------------------------------------------
revoke all on function public.admin_list_audit_log(text, integer) from public, anon;
grant execute on function public.admin_list_audit_log(text, integer) to authenticated;
revoke all on function public.admin_set_account_status(uuid, text) from public, anon;
grant execute on function public.admin_set_account_status(uuid, text) to authenticated;
revoke all on function public.admin_statistics(integer) from public, anon;
grant execute on function public.admin_statistics(integer) to authenticated;
revoke all on function public.admin_get_payment_simulation() from public, anon;
grant execute on function public.admin_get_payment_simulation() to authenticated;
revoke all on function public.admin_set_payment_simulation(boolean) from public, anon;
grant execute on function public.admin_set_payment_simulation(boolean) to authenticated;

-- scan_receipt / decide_passage : create or replace conserve les droits
-- déjà posés par 20260930090000 ; on les réaffirme par prudence.
revoke all on function public.scan_receipt(text) from public, anon;
grant execute on function public.scan_receipt(text) to authenticated;
revoke all on function public.decide_passage(text, boolean, text) from public, anon;
grant execute on function public.decide_passage(text, boolean, text) to authenticated;
