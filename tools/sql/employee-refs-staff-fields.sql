-- Employee refs extension for King staff management.
-- Run this after supabase-schema-classification.sql / noble-rpc-fix.sql.

create extension if not exists pgcrypto;
create schema if not exists staff;

do $$
declare
  public_employee_kind text;
  public_request_kind text;
begin
  select c.relkind
    into public_employee_kind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'employee_refs';

  select c.relkind
    into public_request_kind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'noble_access_requests';

  if to_regclass('staff.noble_access_requests') is not null then
    alter table staff.noble_access_requests
      add column if not exists phone_number text;
  end if;

  if to_regclass('public.noble_access_requests') is not null
     and public_request_kind in ('r', 'p') then
    alter table public.noble_access_requests
      add column if not exists phone_number text;
  end if;

  if to_regclass('staff.employee_refs') is not null then
    alter table staff.employee_refs
      add column if not exists sin_number text,
      add column if not exists phone_number text,
      add column if not exists active boolean not null default true,
      add column if not exists created_at timestamptz not null default now(),
      add column if not exists inactive_at timestamptz,
      add column if not exists updated_at timestamptz not null default now();
  end if;

  if to_regclass('public.employee_refs') is not null
     and public_employee_kind in ('r', 'p') then
    alter table public.employee_refs
      add column if not exists sin_number text,
      add column if not exists phone_number text,
      add column if not exists active boolean not null default true,
      add column if not exists created_at timestamptz not null default now(),
      add column if not exists inactive_at timestamptz,
      add column if not exists updated_at timestamptz not null default now();
  end if;
end;
$$;

create or replace function staff.touch_employee_refs_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare
  public_employee_kind text;
begin
  select c.relkind
    into public_employee_kind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'employee_refs';

  if to_regclass('staff.employee_refs') is not null then
    drop trigger if exists employee_refs_touch_updated_at on staff.employee_refs;
    create trigger employee_refs_touch_updated_at
    before update on staff.employee_refs
    for each row execute function staff.touch_employee_refs_updated_at();
  end if;

  if to_regclass('public.employee_refs') is not null
     and public_employee_kind in ('r', 'p') then
    drop trigger if exists employee_refs_touch_updated_at on public.employee_refs;
    create trigger employee_refs_touch_updated_at
    before update on public.employee_refs
    for each row execute function staff.touch_employee_refs_updated_at();
  end if;
end;
$$;

do $$
declare
  public_employee_kind text;
  public_request_kind text;
begin
  select c.relkind
    into public_employee_kind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'employee_refs';

  select c.relkind
    into public_request_kind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'noble_access_requests';

  if to_regclass('staff.employee_refs') is not null
     and (public_employee_kind is null or public_employee_kind = 'v') then
    execute 'drop view if exists public.employee_refs';
    execute 'create view public.employee_refs with (security_invoker = true) as select * from staff.employee_refs';
  end if;

  if to_regclass('staff.noble_access_requests') is not null
     and (public_request_kind is null or public_request_kind = 'v') then
    execute 'drop view if exists public.noble_access_requests';
    execute 'create view public.noble_access_requests with (security_invoker = true) as select * from staff.noble_access_requests';
  end if;

  if to_regclass('public.employee_refs') is not null then
    execute 'grant select, insert, update, delete on public.employee_refs to authenticated';
    execute 'revoke all on public.employee_refs from anon';
  end if;

  if to_regclass('public.noble_access_requests') is not null then
    execute 'grant select, insert, update, delete on public.noble_access_requests to authenticated';
    execute 'revoke all on public.noble_access_requests from anon';
  end if;

  execute 'grant usage on schema staff to authenticated';

  if to_regclass('staff.employee_refs') is not null then
    execute 'grant select, insert, update, delete on staff.employee_refs to authenticated';
  end if;

  if to_regclass('staff.noble_access_requests') is not null then
    execute 'grant select, insert, update, delete on staff.noble_access_requests to authenticated';
  end if;
end;
$$;

do $$
declare
  public_employee_kind text;
  public_request_kind text;
begin
  select c.relkind
    into public_employee_kind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'employee_refs';

  select c.relkind
    into public_request_kind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'noble_access_requests';

  if to_regclass('staff.employee_refs') is not null then
    execute 'alter table staff.employee_refs enable row level security';

    execute 'drop policy if exists employee_refs_authenticated_all on staff.employee_refs';
    execute 'create policy employee_refs_authenticated_all
      on staff.employee_refs
      for all
      to authenticated
      using (true)
      with check (true)';
  end if;

  if to_regclass('public.employee_refs') is not null
     and public_employee_kind in ('r', 'p') then
    execute 'alter table public.employee_refs enable row level security';

    execute 'drop policy if exists employee_refs_authenticated_all on public.employee_refs';
    execute 'create policy employee_refs_authenticated_all
      on public.employee_refs
      for all
      to authenticated
      using (true)
      with check (true)';
  end if;

  if to_regclass('staff.noble_access_requests') is not null then
    execute 'alter table staff.noble_access_requests enable row level security';

    execute 'drop policy if exists noble_access_requests_anon_insert on staff.noble_access_requests';
    execute 'create policy noble_access_requests_anon_insert
      on staff.noble_access_requests
      for insert
      to anon
      with check (true)';

    execute 'drop policy if exists noble_access_requests_authenticated_all on staff.noble_access_requests';
    execute 'create policy noble_access_requests_authenticated_all
      on staff.noble_access_requests
      for all
      to authenticated
      using (true)
      with check (true)';
  end if;

  if to_regclass('public.noble_access_requests') is not null
     and public_request_kind in ('r', 'p') then
    execute 'alter table public.noble_access_requests enable row level security';

    execute 'drop policy if exists noble_access_requests_anon_insert on public.noble_access_requests';
    execute 'create policy noble_access_requests_anon_insert
      on public.noble_access_requests
      for insert
      to anon
      with check (true)';

    execute 'drop policy if exists noble_access_requests_authenticated_all on public.noble_access_requests';
    execute 'create policy noble_access_requests_authenticated_all
      on public.noble_access_requests
      for all
      to authenticated
      using (true)
      with check (true)';
  end if;
end;
$$;

create or replace function public.king_get_employee_refs()
returns table (
  id uuid,
  ref_code text,
  staff_key text,
  job_role text,
  branch_scope text,
  active boolean,
  sin_number text,
  phone_number text,
  inactive_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = public, staff
as $$
  select
    e.id,
    e.ref_code,
    e.staff_key,
    e.job_role,
    e.branch_scope,
    e.active,
    e.sin_number,
    e.phone_number,
    e.inactive_at,
    e.created_at,
    e.updated_at
  from public.employee_refs e
  order by e.active desc, e.branch_scope, e.staff_key;
$$;

create or replace function public.king_get_access_requests()
returns table (
  id uuid,
  name text,
  branch_scope text,
  phone_number text,
  smart_server_number text,
  status text,
  note text,
  created_at timestamptz
)
language sql
security definer
set search_path = public, staff
as $$
  select
    r.id,
    r.name,
    r.branch_scope,
    r.phone_number,
    r.smart_server_number,
    r.status,
    r.note,
    r.created_at
  from public.noble_access_requests r
  where r.status in ('pending', 'approved')
  order by r.created_at desc;
$$;

grant execute on function public.king_get_employee_refs() to authenticated;
grant execute on function public.king_get_access_requests() to authenticated;

create or replace function public.noble_get_latest_schedule(input_ref text)
returns table (
  shift_date date,
  branch text,
  staff_key text,
  staff_name text,
  job_role text,
  shift_label text,
  start_time time,
  end_time time,
  note text,
  week_start date
)
language plpgsql
security definer
set search_path = public
as $$
declare
  employee record;
  latest_week date;
begin
  select *
    into employee
  from public.lookup_employee_ref(input_ref)
  limit 1;

  if employee.staff_key is null then
    raise exception 'invalid reference code';
  end if;

  select max(w.week_start)
    into latest_week
  from public.noble_schedule_weeks w
  where w.status = 'published';

  if latest_week is null then
    return;
  end if;

  return query
    select
      s.shift_date,
      s.branch,
      s.staff_key,
      s.staff_name,
      s.job_role,
      s.shift_label,
      s.start_time,
      s.end_time,
      s.note,
      w.week_start
    from public.noble_schedule_shifts s
    join public.noble_schedule_weeks w on w.id = s.week_id
    where w.week_start = latest_week
      and w.status = 'published'
    order by s.branch, s.shift_date, s.sort_order, s.staff_name;
end;
$$;

revoke all on function public.noble_get_latest_schedule(text) from public;
grant execute on function public.noble_get_latest_schedule(text) to anon, authenticated;

create or replace function public.noble_submit_access_request_v2(
  p_name text,
  p_branch_scope text,
  p_smart_server_number text,
  p_phone_number text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, staff
as $$
declare
  new_id uuid;
  normalized_branch text := lower(trim(p_branch_scope));
begin
  if nullif(trim(p_name), '') is null then
    raise exception 'name is required';
  end if;

  if normalized_branch not in ('uptown', 'downtown', 'both') then
    raise exception 'invalid branch_scope';
  end if;

  if nullif(trim(p_smart_server_number), '') is null then
    raise exception 'smart_server_number is required';
  end if;

  if nullif(trim(coalesce(p_phone_number, '')), '') is null then
    raise exception 'phone_number is required';
  end if;

  insert into public.noble_access_requests (
    name,
    branch_scope,
    smart_server_number,
    phone_number
  )
  values (
    trim(p_name),
    normalized_branch,
    trim(p_smart_server_number),
    trim(p_phone_number)
  )
  returning id into new_id;

  return new_id;
end;
$$;

revoke all on function public.noble_submit_access_request_v2(text, text, text, text) from public;
grant execute on function public.noble_submit_access_request_v2(text, text, text, text) to anon, authenticated;
