create extension if not exists pgcrypto;

create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  brand text not null,
  model text not null,
  registration_number text not null,
  category text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vehicles_user_fk
    foreign key (user_id) references public.profiles(id) on delete cascade
);

create index if not exists idx_vehicles_user_id
  on public.vehicles (user_id);

create index if not exists idx_vehicles_active
  on public.vehicles (user_id, is_active);

alter table public.vehicles enable row level security;

create or replace function public.set_vehicles_updated_at()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_set_vehicles_updated_at
before update on public.vehicles
for each row
execute function public.set_vehicles_updated_at();

create policy "vehicles_select_own"
on public.vehicles
for select
to authenticated
using (user_id = auth.uid());

create policy "vehicles_insert_own"
on public.vehicles
for insert
to authenticated
with check (
  user_id = auth.uid()
  and brand <> ''
  and model <> ''
  and registration_number <> ''
  and category <> ''
);

create policy "vehicles_update_own"
on public.vehicles
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());


create policy "vehicles_block_delete"
on public.vehicles
for delete
to authenticated
using (false);

-- The client cannot rely on user_id from Flutter; it is determined by auth.uid().
-- The only acceptable user_id is the connected user’s own identity.
