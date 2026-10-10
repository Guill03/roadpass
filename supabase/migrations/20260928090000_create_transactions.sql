-- Bloc D — Transactions (création et annulation uniquement).
-- Pas de paiement, QR, passage, exemption ni compte prépayé ici : ces tables
-- n'existent pas encore et leurs colonnes seront ajoutées par leurs blocs.

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  vehicle_id uuid not null references public.vehicles(id),
  -- Instantané du tarif applicable au moment de la création (RG4) : le tarif
  -- référencé, le montant et la devise sont copiés et ne changent plus,
  -- même si le tarif est clôturé ou remplacé par la suite.
  tariff_id uuid not null references public.toll_tariffs(id),
  registration_post_id uuid not null references public.toll_posts(id),
  trip_type text not null check (trip_type in ('longue_distance', 'demi_trajet')),
  amount_due numeric(12, 2) not null check (amount_due > 0),
  currency text not null,
  -- Cycle de vie : Figure 13 du Chapitre 3.
  status text not null default 'initiee' check (
    status in (
      'initiee', 'en_attente_paiement', 'payee', 'verifiee',
      'passage_valide', 'echouee', 'annulee', 'refusee'
    )
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_transactions_user_created
  on public.transactions (user_id, created_at desc);
create index if not exists idx_transactions_vehicle
  on public.transactions (vehicle_id);
create index if not exists idx_transactions_status
  on public.transactions (status);

drop trigger if exists trg_set_transactions_updated_at on public.transactions;
create trigger trg_set_transactions_updated_at
before update on public.transactions
for each row
execute function public.set_vehicles_updated_at();

alter table public.transactions enable row level security;

-- Lecture : chacun ne voit que ses propres transactions. Aucune policy
-- INSERT/UPDATE/DELETE : toute écriture passe par les RPC ci-dessous.
drop policy if exists "transactions_select_own" on public.transactions;
create policy "transactions_select_own"
on public.transactions
for select
to authenticated
using (user_id = auth.uid());

revoke all on table public.transactions from anon;
revoke all on table public.transactions from authenticated;
grant select on table public.transactions to authenticated;

-- ---------------------------------------------------------------------
-- RPC : création d'une transaction. Le montant et le tarif sont calculés
-- côté serveur à partir de critères explicites (poste + catégorie du
-- véhicule + type de trajet + date/heure) : le client ne fournit jamais
-- le montant ni l'identifiant du tarif.
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
  where id = p_vehicle_id
    and user_id = auth.uid()
    and is_active;
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

  insert into public.transactions (
    user_id, vehicle_id, tariff_id, registration_post_id,
    trip_type, amount_due, currency
  )
  values (
    auth.uid(), v_vehicle.id, v_tariff.id, p_post_id,
    p_trip_type, v_tariff.amount, v_tariff.currency
  )
  returning * into v_result;

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------
-- RPC : abandon par l'usager (Initiée -> Annulée), seule transition
-- permise à l'utilisateur dans ce bloc.
-- ---------------------------------------------------------------------
create or replace function public.cancel_transaction(p_transaction_id uuid)
returns public.transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result public.transactions;
begin
  if auth.uid() is null then
    raise exception 'Non authentifié';
  end if;

  update public.transactions
  set status = 'annulee'
  where id = p_transaction_id
    and user_id = auth.uid()
    and status = 'initiee'
  returning * into v_result;

  if v_result.id is null then
    raise exception 'Transaction introuvable ou non annulable';
  end if;

  return v_result;
end;
$$;

revoke all on function public.create_transaction(uuid, uuid, text) from public, anon;
grant execute on function public.create_transaction(uuid, uuid, text) to authenticated;

revoke all on function public.cancel_transaction(uuid) from public, anon;
grant execute on function public.cancel_transaction(uuid) to authenticated;
