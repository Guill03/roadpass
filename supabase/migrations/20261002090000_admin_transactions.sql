-- Supervision administrateur : lecture des transactions via deux fonctions
-- dont le rôle est vérifié par la base. Aucune policy SELECT n'est élargie :
-- l'admin ne lit toujours pas public.transactions directement.

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
        t.amount_due,
        t.currency,
        t.created_at,
        v.registration_number,
        v.brand,
        v.model,
        trim(p.prenom || ' ' || p.nom) as user_name,
        tp.name as post_name,
        ps.result as passage_result,
        ps.refusal_reason
      from public.transactions t
      join public.vehicles v on v.id = t.vehicle_id
      join public.profiles p on p.id = t.user_id
      join public.toll_posts tp on tp.id = t.registration_post_id
      left join public.receipts r on r.transaction_id = t.id
      left join public.passages ps on ps.receipt_id = r.id
      where p_status is null or t.status = p_status
      order by t.created_at desc
      limit least(greatest(coalesce(p_limit, 100), 1), 500)
    ) x
  );
end;
$$;

create or replace function public.admin_transactions_summary()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Action réservée aux administrateurs';
  end if;

  return jsonb_build_object(
    'total', (select count(*) from public.transactions),
    'by_status', coalesce((
      select jsonb_object_agg(s.status, s.n)
      from (
        select status, count(*) as n
        from public.transactions
        group by status
      ) s
    ), '{}'::jsonb),
    -- Montants réellement encaissés par paiement (hors exemption et compte
    -- prépayé), par devise.
    'collected', coalesce((
      select jsonb_agg(jsonb_build_object('currency', c.currency, 'amount', c.total))
      from (
        select currency, sum(amount_due) as total
        from public.transactions
        where settlement_type = 'paiement'
          and status in ('payee', 'verifiee', 'passage_valide')
        group by currency
      ) c
    ), '[]'::jsonb),
    'exempted', (
      select count(*) from public.transactions where settlement_type = 'exemption'
    ),
    'prepaid', (
      select count(*) from public.transactions where settlement_type = 'sous_provision'
    )
  );
end;
$$;

revoke all on function public.admin_list_transactions(text, integer) from public, anon;
grant execute on function public.admin_list_transactions(text, integer) to authenticated;
revoke all on function public.admin_transactions_summary() from public, anon;
grant execute on function public.admin_transactions_summary() to authenticated;
