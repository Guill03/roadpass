begin;

select plan(10);

insert into auth.users (id, aud, role, email)
values
  ('00000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'user@roadpass.test'),
  ('00000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'agent@roadpass.test'),
  ('00000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'admin@roadpass.test'),
  ('00000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'other@roadpass.test');

select set_config('request.jwt.claim.role', 'service_role', true);

update public.profiles
set role = 'agent'
where id = '00000000-0000-0000-0000-000000000002';

update public.profiles
set role = 'admin'
where id = '00000000-0000-0000-0000-000000000003';

select set_config('request.jwt.claim.role', 'authenticated', true);

select ok(
  not has_table_privilege('anon', 'public.profiles', 'select'),
  'anon cannot read profiles'
);

select ok(
  has_table_privilege('authenticated', 'public.profiles', 'select'),
  'authenticated can read profiles through RLS'
);

select ok(
  not has_table_privilege('authenticated', 'public.profiles', 'update'),
  'authenticated cannot update profiles directly'
);

select ok(
  not has_function_privilege('anon', 'public.is_admin()', 'execute'),
  'anon cannot execute is_admin'
);

select ok(
  has_function_privilege('authenticated', 'public.is_admin()', 'execute'),
  'authenticated can execute the RLS role check'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'profiles_select_own_or_admin'
      and qual like '%is_admin%'
  ),
  'profiles policy delegates the administrator check to is_admin'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001',
  true
);

select is(
  (select count(*)::int from public.profiles),
  1,
  'user sees only its own profile'
);

select is(
  (select role from public.profiles where id = '00000000-0000-0000-0000-000000000001'),
  'user',
  'user role comes from profiles'
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000002',
  true
);

select is(
  (select count(*)::int from public.profiles),
  1,
  'agent sees only its own profile'
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000003',
  true
);

select is(
  (select count(*)::int from public.profiles),
  4,
  'admin can read all profiles'
);

select * from finish();

rollback;
