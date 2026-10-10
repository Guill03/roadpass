-- Bloc G — Exemptions et comptes prépayés (sous-provision).
-- Hors périmètre ici : mode manuel en cas de panne réseau (à cadrer).

-- ---------------------------------------------------------------------
-- 1) Exemptions (véhicules de l'État, etc.) — validées par un administrateur
-- ---------------------------------------------------------------------
create table if not exists public.exemptions (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id),
  reason text not null check (length(trim(reason)) > 0),
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  status text not null default 'active' check (status in ('active', 'terminee')),
  validated_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  constraint exemptions_valid_period
    check (valid_until is null or valid_until > valid_from)
);

create index if not exists idx_exemptions_vehicle
  on public.exemptions (vehicle_id, status);

alter table public.exemptions enable row level security;

drop policy if exists "exemptions_select_admin_or_owner" on public.exemptions;
create policy "exemptions_select_admin_or_owner"
on public.exemptions
for select
to authenticated
using (
  public.is_admin()
  or exists (
    select 1 from public.vehicles v
    where v.id = exemptions.vehicle_id and v.user_id = auth.uid()
  )
);

revoke all on table public.exemptions from anon, authenticated;
grant select on table public.exemptions to authenticated;

-- ---------------------------------------------------------------------
-- 2) Comptes prépayés : un compte au plus par utilisateur
-- ---------------------------------------------------------------------
create table if not exists public.prepaid_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id),
  balance integer not null default 0 check (balance >= 0),
  status text not null default 'actif' check (status in ('actif', 'suspendu')),
  created_at timestamptz not null default now()
);

alter table public.prepaid_accounts enable row level security;

drop policy if exists "prepaid_accounts_select_owner_or_admin" on public.prepaid_accounts;
create policy "prepaid_accounts_select_owner_or_admin"
on public.prepaid_accounts
for select
to authenticated
using (user_id = auth.uid() or public.is_admin());

revoke all on table public.prepaid_accounts from anon, authenticated;
grant select on table public.prepaid_accounts to authenticated;

create table if not exists public.account_movements (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.prepaid_accounts(id),
  movement_type text not null check (movement_type in ('recharge', 'debit')),
  quantity integer not null check (quantity > 0),
  transaction_id uuid references public.transactions(id),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  constraint movements_transaction_coherent check (
    (movement_type = 'debit' and transaction_id is not null)
    or (movement_type = 'recharge' and transaction_id is null)
  )
);

create index if not exists idx_account_movements_account
  on public.account_movements (account_id, created_at desc);

alter table public.account_movements enable row level security;

drop policy if exists "account_movements_select_owner_or_admin" on public.account_movements;
create policy "account_movements_select_owner_or_admin"
on public.account_movements
for select
to authenticated
using (
  public.is_admin()
  or exists (
    select 1 from public.prepaid_accounts a
    where a.id = account_movements.account_id and a.user_id = auth.uid()
  )
);

revoke all on table public.account_movements from anon, authenticated;
grant select on table public.account_movements to authenticated;

-- ---------------------------------------------------------------------
-- 3) Transactions : mode de règlement (RG5)
-- ---------------------------------------------------------------------
alter table public.transactions
  add column if not exists settlement_type text not null default 'paiement'
    check (settlement_type in ('paiement', 'sous_provision', 'exemption')),
  add column if not exists account_id uuid references public.prepaid_accounts(id),
  add column if not exists exemption_id uuid references public.exemptions(id);

alter table public.transactions
  drop constraint if exists transactions_amount_due_check;
alter table public.transactions
  drop constraint if exists transactions_amount_due_valid;
alter table public.transactions
  add constraint transactions_amount_due_valid check (
    amount_due >= 0
    and (settlement_type = 'exemption' or amount_due > 0)
  );

alter table public.transactions
  drop constraint if exists transactions_settlement_coherent;
alter table public.transactions
  add constraint transactions_settlement_coherent check (
    (settlement_type = 'paiement' and account_id is null and exemption_id is null)
    or (settlement_type = 'sous_provision' and account_id is not null and exemption_id is null)
    or (settlement_type = 'exemption' and exemption_id is not null and account_id is null)
  );

-- Un règlement par exemption naît déjà « payee » : le justificatif doit donc
-- aussi se générer à l'INSERT (le déclencheur existant ne couvre que l'UPDATE).
drop trigger if exists trg_generate_receipt_on_insert on public.transactions;
create trigger trg_generate_receipt_on_insert
after insert on public.transactions
for each row
when (new.status = 'payee')
execute function public.generate_receipt_on_payment();

-- ---------------------------------------------------------------------
-- 4) create_transaction : détecte une exemption active sur le véhicule
-- ---------------------------------------------------------------------
create or replace function public.create_transaction(
  p_vehicle_id uuid,
  p_post_id uuid,
  p_trip_type text
)
returns public.transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_vehicle public.vehicles;
  v_tariff public.toll_tariffs;
  v_exemption public.exemptions;
  v_result public.transactions;
begin
  if auth.uid() is null then
    raise exception 'Non authentifié';
  end if;
  if p_trip_type not in ('longue_distance', 'demi_trajet') then
    raise exception 'Type de trajet invalide';
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
  if not exists (
    select 1 from public.toll_posts where id = p_post_id and is_active
  ) then
    raise exception 'Poste de péage introuvable ou inactif';
  end if;

  select * into v_tariff
  from public.toll_tariffs
  where toll_post_id = p_post_id
    and category_id = v_vehicle.category_id
    and trip_type = p_trip_type
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

  if found then
    insert into public.transactions (
      user_id, vehicle_id, tariff_id, registration_post_id, trip_type,
      amount_due, currency, status, settlement_type, exemption_id
    )
    values (
      auth.uid(), v_vehicle.id, v_tariff.id, p_post_id, p_trip_type,
      0, v_tariff.currency, 'payee', 'exemption', v_exemption.id
    )
    returning * into v_result;
  else
    insert into public.transactions (
      user_id, vehicle_id, tariff_id, registration_post_id, trip_type,
      amount_due, currency
    )
    values (
      auth.uid(), v_vehicle.id, v_tariff.id, p_post_id, p_trip_type,
      v_tariff.amount, v_tariff.currency
    )
    returning * into v_result;
  end if;

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------
-- 5) Règlement par compte prépayé : débite 1 passage (Initiée -> Payée)
-- ---------------------------------------------------------------------
create or replace function public.pay_transaction_with_account(p_transaction_id uuid)
returns public.transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tx public.transactions;
  v_account public.prepaid_accounts;
  v_result public.transactions;
begin
  if auth.uid() is null then
    raise exception 'Non authentifié';
  end if;

  select * into v_tx
  from public.transactions
  where id = p_transaction_id and user_id = auth.uid()
  for update;
  if not found then
    raise exception 'Transaction introuvable';
  end if;
  if v_tx.status <> 'initiee' or v_tx.settlement_type <> 'paiement' then
    raise exception 'Cette transaction ne peut plus être réglée';
  end if;

  select * into v_account
  from public.prepaid_accounts
  where user_id = auth.uid()
  for update;
  if not found then
    raise exception 'Vous n''avez pas de compte prépayé';
  end if;
  if v_account.status <> 'actif' then
    raise exception 'Votre compte prépayé est suspendu';
  end if;
  if v_account.balance < 1 then
    raise exception 'Solde de passages insuffisant';
  end if;

  update public.prepaid_accounts
  set balance = balance - 1
  where id = v_account.id;

  insert into public.account_movements (
    account_id, movement_type, quantity, transaction_id, created_by
  )
  values (v_account.id, 'debit', 1, v_tx.id, auth.uid());

  update public.transactions
  set status = 'payee', settlement_type = 'sous_provision', account_id = v_account.id
  where id = v_tx.id
  returning * into v_result;

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------
-- 6) RPC administrateur (rôle vérifié par la base)
-- ---------------------------------------------------------------------
create or replace function public.admin_find_vehicle(p_registration_number text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_vehicle public.vehicles;
  v_owner public.profiles;
begin
  if not public.is_admin() then
    raise exception 'Action réservée aux administrateurs';
  end if;
  select * into v_vehicle
  from public.vehicles
  where upper(trim(registration_number)) = upper(trim(p_registration_number));
  if not found then
    raise exception 'Aucun véhicule avec cette immatriculation';
  end if;
  select * into v_owner from public.profiles where id = v_vehicle.user_id;
  return jsonb_build_object(
    'id', v_vehicle.id,
    'registration_number', v_vehicle.registration_number,
    'brand', v_vehicle.brand,
    'model', v_vehicle.model,
    'owner_name', trim(v_owner.prenom || ' ' || v_owner.nom)
  );
end;
$$;

create or replace function public.admin_create_exemption(
  p_vehicle_id uuid,
  p_reason text,
  p_valid_until timestamptz default null
)
returns public.exemptions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result public.exemptions;
begin
  if not public.is_admin() then
    raise exception 'Action réservée aux administrateurs';
  end if;
  if length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'Le motif est obligatoire';
  end if;
  if not exists (select 1 from public.vehicles where id = p_vehicle_id) then
    raise exception 'Véhicule introuvable';
  end if;
  if p_valid_until is not null and p_valid_until <= now() then
    raise exception 'La date de fin doit être dans le futur';
  end if;
  if exists (
    select 1 from public.exemptions
    where vehicle_id = p_vehicle_id
      and status = 'active'
      and (valid_until is null or valid_until > now())
  ) then
    raise exception 'Ce véhicule a déjà une exemption active';
  end if;

  insert into public.exemptions (vehicle_id, reason, valid_until, validated_by)
  values (p_vehicle_id, trim(p_reason), p_valid_until, auth.uid())
  returning * into v_result;
  return v_result;
end;
$$;

create or replace function public.admin_end_exemption(p_exemption_id uuid)
returns public.exemptions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result public.exemptions;
begin
  if not public.is_admin() then
    raise exception 'Action réservée aux administrateurs';
  end if;
  update public.exemptions
  set status = 'terminee',
      valid_until = case
        when valid_until is null or valid_until > now() then now()
        else valid_until
      end
  where id = p_exemption_id and status = 'active'
  returning * into v_result;
  if v_result.id is null then
    raise exception 'Exemption introuvable ou déjà terminée';
  end if;
  return v_result;
end;
$$;

create or replace function public.admin_list_exemptions()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Action réservée aux administrateurs';
  end if;
  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', e.id,
        'vehicle_id', e.vehicle_id,
        'registration_number', v.registration_number,
        'brand', v.brand,
        'model', v.model,
        'reason', e.reason,
        'status', e.status,
        'valid_from', e.valid_from,
        'valid_until', e.valid_until
      )
      order by e.created_at desc
    )
    from public.exemptions e
    join public.vehicles v on v.id = e.vehicle_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_open_prepaid_account(p_user_id uuid)
returns public.prepaid_accounts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result public.prepaid_accounts;
begin
  if not public.is_admin() then
    raise exception 'Action réservée aux administrateurs';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'Utilisateur introuvable';
  end if;
  if exists (select 1 from public.prepaid_accounts where user_id = p_user_id) then
    raise exception 'Cet utilisateur a déjà un compte prépayé';
  end if;
  insert into public.prepaid_accounts (user_id) values (p_user_id)
  returning * into v_result;
  return v_result;
end;
$$;

create or replace function public.admin_recharge_prepaid_account(
  p_account_id uuid,
  p_quantity integer
)
returns public.prepaid_accounts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result public.prepaid_accounts;
begin
  if not public.is_admin() then
    raise exception 'Action réservée aux administrateurs';
  end if;
  if p_quantity is null or p_quantity < 1 then
    raise exception 'La quantité doit être positive';
  end if;
  update public.prepaid_accounts
  set balance = balance + p_quantity
  where id = p_account_id
  returning * into v_result;
  if v_result.id is null then
    raise exception 'Compte introuvable';
  end if;
  insert into public.account_movements (
    account_id, movement_type, quantity, created_by
  )
  values (v_result.id, 'recharge', p_quantity, auth.uid());
  return v_result;
end;
$$;

revoke all on function public.pay_transaction_with_account(uuid) from public, anon;
grant execute on function public.pay_transaction_with_account(uuid) to authenticated;

revoke all on function public.admin_find_vehicle(text) from public, anon;
grant execute on function public.admin_find_vehicle(text) to authenticated;
revoke all on function public.admin_create_exemption(uuid, text, timestamptz) from public, anon;
grant execute on function public.admin_create_exemption(uuid, text, timestamptz) to authenticated;
revoke all on function public.admin_end_exemption(uuid) from public, anon;
grant execute on function public.admin_end_exemption(uuid) to authenticated;
revoke all on function public.admin_list_exemptions() from public, anon;
grant execute on function public.admin_list_exemptions() to authenticated;
revoke all on function public.admin_open_prepaid_account(uuid) from public, anon;
grant execute on function public.admin_open_prepaid_account(uuid) to authenticated;
revoke all on function public.admin_recharge_prepaid_account(uuid, integer) from public, anon;
grant execute on function public.admin_recharge_prepaid_account(uuid, integer) to authenticated;
