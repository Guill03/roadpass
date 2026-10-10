-- Bloc F — Justificatif (code QR), vérification par l'agent, passage.
-- Cycle : payee --scan--> verifiee --contrôle--> passage_valide | refusee
-- (Figure 13 du Chapitre 3).

-- ---------------------------------------------------------------------
-- 1) Justificatifs (entité JUSTIFICATIF), un par transaction payée (RG7)
-- ---------------------------------------------------------------------
create table if not exists public.receipts (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null unique references public.transactions(id),
  qr_code text not null unique,
  status text not null default 'valide'
    check (status in ('valide', 'utilise', 'invalide')),
  generated_at timestamptz not null default now()
);

alter table public.receipts enable row level security;

drop policy if exists "receipts_select_own" on public.receipts;
create policy "receipts_select_own"
on public.receipts
for select
to authenticated
using (
  exists (
    select 1
    from public.transactions t
    where t.id = receipts.transaction_id
      and t.user_id = auth.uid()
  )
);

revoke all on table public.receipts from anon, authenticated;
grant select on table public.receipts to authenticated;

-- Génération automatique dès qu'une transaction passe à « payee », quelle que
-- soit l'origine du paiement (simulation aujourd'hui, prestataire demain).
-- Le code est aléatoire et non devinable (identifiant aléatoire de 122 bits).
create or replace function public.generate_receipt_on_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.receipts (transaction_id, qr_code)
  values (
    new.id,
    'RP-' || upper(replace(gen_random_uuid()::text, '-', ''))
  )
  on conflict (transaction_id) do nothing;
  return new;
end;
$$;

revoke all on function public.generate_receipt_on_payment()
  from public, anon, authenticated;

drop trigger if exists trg_generate_receipt_on_payment on public.transactions;
create trigger trg_generate_receipt_on_payment
after update of status on public.transactions
for each row
when (new.status = 'payee' and old.status is distinct from 'payee')
execute function public.generate_receipt_on_payment();

-- Justificatifs des transactions déjà payées avant ce bloc (rattrapage).
insert into public.receipts (transaction_id, qr_code)
select t.id, 'RP-' || upper(replace(gen_random_uuid()::text, '-', ''))
from public.transactions t
where t.status = 'payee'
on conflict (transaction_id) do nothing;

-- ---------------------------------------------------------------------
-- 2) Passages (entité PASSAGE)
-- ---------------------------------------------------------------------
create table if not exists public.passages (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null unique references public.receipts(id),
  agent_id uuid not null references public.profiles(id),
  -- Poste d'enregistrement de la transaction : aucun lien agent-poste
  -- n'existe encore dans le modèle.
  post_id uuid not null references public.toll_posts(id),
  result text not null check (result in ('autorise', 'refuse')),
  refusal_reason text,
  created_at timestamptz not null default now(),
  constraint passages_reason_coherent check (
    (result = 'refuse' and refusal_reason is not null)
    or (result = 'autorise' and refusal_reason is null)
  )
);

create index if not exists idx_passages_agent_created
  on public.passages (agent_id, created_at desc);

alter table public.passages enable row level security;

-- Un agent voit ses propres vérifications ; l'usager voit le passage de ses
-- propres transactions.
drop policy if exists "passages_select_agent_or_owner" on public.passages;
create policy "passages_select_agent_or_owner"
on public.passages
for select
to authenticated
using (
  agent_id = auth.uid()
  or exists (
    select 1
    from public.receipts r
    join public.transactions t on t.id = r.transaction_id
    where r.id = passages.receipt_id
      and t.user_id = auth.uid()
  )
);

revoke all on table public.passages from anon, authenticated;
grant select on table public.passages to authenticated;

-- ---------------------------------------------------------------------
-- 3) RPC agent : scan du code QR (payee -> verifiee), lecture seule des
--    informations utiles au contrôle. Réservé au rôle « agent » : un
--    administrateur ne reçoit pas ce droit automatiquement.
-- ---------------------------------------------------------------------
create or replace function public.scan_receipt(p_qr_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_receipt public.receipts;
  v_tx public.transactions;
  v_vehicle public.vehicles;
  v_category public.vehicle_categories;
  v_post public.toll_posts;
begin
  if auth.uid() is null then
    raise exception 'Non authentifié';
  end if;
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'agent'
  ) then
    raise exception 'Action réservée aux agents';
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

-- ---------------------------------------------------------------------
-- 4) RPC agent : décision (verifiee -> passage_valide | refusee)
-- ---------------------------------------------------------------------
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
  v_receipt public.receipts;
  v_tx public.transactions;
  v_passage public.passages;
begin
  if auth.uid() is null then
    raise exception 'Non authentifié';
  end if;
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'agent'
  ) then
    raise exception 'Action réservée aux agents';
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

revoke all on function public.scan_receipt(text) from public, anon;
grant execute on function public.scan_receipt(text) to authenticated;

revoke all on function public.decide_passage(text, boolean, text) from public, anon;
grant execute on function public.decide_passage(text, boolean, text) to authenticated;
