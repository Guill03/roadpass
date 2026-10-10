-- Bloc E — Paiement SIMULÉ.
-- Aucun prestataire réel n'est branché. La structure (table payments,
-- statuts, référence externe) est celle qui servira à RAWBANK ou à un autre
-- prestataire ; seule la RPC de simulation sera retirée à ce moment-là.

-- ---------------------------------------------------------------------
-- 1) Réglages serveur (non lisibles par les clients)
-- ---------------------------------------------------------------------
create table if not exists public.app_settings (
  key text primary key,
  value text not null
);

alter table public.app_settings enable row level security;
-- Aucune policy et aucun grant : seules les fonctions SECURITY DEFINER
-- (et le service_role / l'éditeur SQL) y accèdent.
revoke all on table public.app_settings from anon, authenticated;

insert into public.app_settings (key, value)
values ('payment_simulation_enabled', 'true')
on conflict (key) do nothing;
-- EN PRODUCTION : update public.app_settings set value = 'false'
--                 where key = 'payment_simulation_enabled';

-- ---------------------------------------------------------------------
-- 2) Paiements (entité PAIEMENT du Chapitre 3)
-- ---------------------------------------------------------------------
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references public.transactions(id),
  payment_method text not null check (payment_method in ('simulation')),
  external_reference text not null,
  status text not null check (status in ('en_attente', 'reussi', 'refuse')),
  created_at timestamptz not null default now()
);

create index if not exists idx_payments_transaction
  on public.payments (transaction_id);

-- RG6 : une transaction peut avoir plusieurs tentatives, mais une seule
-- tentative réussie.
create unique index if not exists idx_payments_one_success_per_transaction
  on public.payments (transaction_id)
  where status = 'reussi';

alter table public.payments enable row level security;

drop policy if exists "payments_select_own" on public.payments;
create policy "payments_select_own"
on public.payments
for select
to authenticated
using (
  exists (
    select 1
    from public.transactions t
    where t.id = payments.transaction_id
      and t.user_id = auth.uid()
  )
);

revoke all on table public.payments from anon, authenticated;
grant select on table public.payments to authenticated;

-- ---------------------------------------------------------------------
-- 3) RPC de simulation : Initiée -> (En attente) -> Payée | Échouée
--    Atomique : la transaction est verrouillée, le paiement créé et le
--    statut mis à jour dans le même appel.
-- ---------------------------------------------------------------------
create or replace function public.pay_transaction_simulated(
  p_transaction_id uuid,
  p_succeed boolean default true
)
returns public.payments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tx public.transactions;
  v_payment public.payments;
begin
  if auth.uid() is null then
    raise exception 'Non authentifié';
  end if;

  if coalesce(
    (select value from public.app_settings
     where key = 'payment_simulation_enabled'),
    'false'
  ) <> 'true' then
    raise exception 'La simulation de paiement est désactivée';
  end if;

  select * into v_tx
  from public.transactions
  where id = p_transaction_id
    and user_id = auth.uid()
  for update;
  if not found then
    raise exception 'Transaction introuvable';
  end if;

  if v_tx.status <> 'initiee' then
    raise exception 'Cette transaction ne peut plus être payée';
  end if;

  insert into public.payments (
    transaction_id, payment_method, external_reference, status
  )
  values (
    v_tx.id,
    'simulation',
    'SIM-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)),
    case when p_succeed then 'reussi' else 'refuse' end
  )
  returning * into v_payment;

  update public.transactions
  set status = case when p_succeed then 'payee' else 'echouee' end
  where id = v_tx.id;

  return v_payment;
end;
$$;

revoke all on function public.pay_transaction_simulated(uuid, boolean) from public, anon;
grant execute on function public.pay_transaction_simulated(uuid, boolean) to authenticated;
