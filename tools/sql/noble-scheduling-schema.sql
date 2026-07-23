-- Noble scheduling / availability schema for Supabase.
-- Assumes the existing RPC public.lookup_employee_ref(input_ref text)
-- returns at least: staff_key, branch_scope, job_role.

create extension if not exists pgcrypto;

create table if not exists public.noble_access_requests (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  branch_scope text not null check (branch_scope in ('uptown', 'downtown', 'both')),
  smart_server_number text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'done')),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.noble_staff_availability (
  id uuid primary key default gen_random_uuid(),
  staff_key text not null,
  staff_name text,
  branch_scope text not null default 'both' check (branch_scope in ('uptown', 'downtown', 'both')),
  availability_date date not null,
  status text not null check (status in ('default', 'unavailable', 'preferred')),
  available_start time,
  available_end time,
  note text,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (staff_key, availability_date)
);

create table if not exists public.noble_schedule_weeks (
  id uuid primary key default gen_random_uuid(),
  week_start date not null unique,
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  note text,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.noble_schedule_shifts (
  id uuid primary key default gen_random_uuid(),
  week_id uuid not null references public.noble_schedule_weeks(id) on delete cascade,
  shift_date date not null,
  branch text not null check (branch in ('uptown', 'downtown')),
  staff_key text not null,
  staff_name text not null,
  job_role text,
  shift_label text,
  start_time time,
  end_time time,
  sort_order integer not null default 0,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists noble_staff_availability_date_idx
  on public.noble_staff_availability (availability_date, branch_scope);

create index if not exists noble_staff_availability_staff_idx
  on public.noble_staff_availability (staff_key, availability_date);

create index if not exists noble_schedule_shifts_week_branch_date_idx
  on public.noble_schedule_shifts (week_id, branch, shift_date, sort_order);

create index if not exists noble_schedule_shifts_staff_date_idx
  on public.noble_schedule_shifts (staff_key, shift_date);

create or replace function public.noble_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists noble_access_requests_touch_updated_at on public.noble_access_requests;
create trigger noble_access_requests_touch_updated_at
before update on public.noble_access_requests
for each row execute function public.noble_touch_updated_at();

drop trigger if exists noble_staff_availability_touch_updated_at on public.noble_staff_availability;
create trigger noble_staff_availability_touch_updated_at
before update on public.noble_staff_availability
for each row execute function public.noble_touch_updated_at();

drop trigger if exists noble_schedule_weeks_touch_updated_at on public.noble_schedule_weeks;
create trigger noble_schedule_weeks_touch_updated_at
before update on public.noble_schedule_weeks
for each row execute function public.noble_touch_updated_at();

drop trigger if exists noble_schedule_shifts_touch_updated_at on public.noble_schedule_shifts;
create trigger noble_schedule_shifts_touch_updated_at
before update on public.noble_schedule_shifts
for each row execute function public.noble_touch_updated_at();

alter table public.noble_access_requests enable row level security;
alter table public.noble_staff_availability enable row level security;
alter table public.noble_schedule_weeks enable row level security;
alter table public.noble_schedule_shifts enable row level security;

drop policy if exists noble_access_requests_anon_insert on public.noble_access_requests;
create policy noble_access_requests_anon_insert
on public.noble_access_requests
for insert
to anon
with check (true);

drop policy if exists noble_access_requests_admin_all on public.noble_access_requests;
create policy noble_access_requests_admin_all
on public.noble_access_requests
for all
to authenticated
using (true)
with check (true);

drop policy if exists noble_staff_availability_admin_all on public.noble_staff_availability;
create policy noble_staff_availability_admin_all
on public.noble_staff_availability
for all
to authenticated
using (true)
with check (true);

drop policy if exists noble_schedule_weeks_admin_all on public.noble_schedule_weeks;
create policy noble_schedule_weeks_admin_all
on public.noble_schedule_weeks
for all
to authenticated
using (true)
with check (true);

drop policy if exists noble_schedule_shifts_admin_all on public.noble_schedule_shifts;
create policy noble_schedule_shifts_admin_all
on public.noble_schedule_shifts
for all
to authenticated
using (true)
with check (true);

create or replace function public.noble_submit_access_request(
  p_name text,
  p_branch_scope text,
  p_smart_server_number text
)
returns uuid
language plpgsql
security definer
set search_path = public
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

  insert into public.noble_access_requests (name, branch_scope, smart_server_number)
  values (trim(p_name), normalized_branch, trim(p_smart_server_number))
  returning id into new_id;

  return new_id;
end;
$$;

create or replace function public.noble_submit_availability(
  input_ref text,
  p_unavailable_dates date[] default '{}',
  p_preferred_dates date[] default '{}',
  p_date_details jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  employee record;
  item_date date;
  detail_key text;
  detail_value jsonb;
  detail_status text;
  detail_start time;
  detail_end time;
  detail_note text;
begin
  select *
    into employee
  from public.lookup_employee_ref(input_ref)
  limit 1;

  if employee.staff_key is null then
    raise exception 'invalid reference code';
  end if;

  delete from public.noble_staff_availability
  where staff_key = employee.staff_key;

  foreach item_date in array coalesce(p_unavailable_dates, '{}') loop
    insert into public.noble_staff_availability (
      staff_key,
      staff_name,
      branch_scope,
      availability_date,
      status
    )
    values (
      employee.staff_key,
      employee.staff_key,
      coalesce(nullif(lower(employee.branch_scope), ''), 'both'),
      item_date,
      'unavailable'
    )
    on conflict (staff_key, availability_date) do update
      set status = excluded.status,
          available_start = null,
          available_end = null,
          note = null,
          submitted_at = now();
  end loop;

  foreach item_date in array coalesce(p_preferred_dates, '{}') loop
    insert into public.noble_staff_availability (
      staff_key,
      staff_name,
      branch_scope,
      availability_date,
      status
    )
    values (
      employee.staff_key,
      employee.staff_key,
      coalesce(nullif(lower(employee.branch_scope), ''), 'both'),
      item_date,
      'preferred'
    )
    on conflict (staff_key, availability_date) do update
      set status = excluded.status,
          submitted_at = now();
  end loop;

  for detail_key, detail_value in
    select key, value from jsonb_each(coalesce(p_date_details, '{}'::jsonb))
  loop
    item_date := detail_key::date;
    detail_status := coalesce(nullif(detail_value->>'status', ''), 'default');
    detail_note := nullif(trim(coalesce(detail_value->>'note', '')), '');

    if detail_status not in ('default', 'unavailable', 'preferred') then
      detail_status := 'default';
    end if;

    detail_start := null;
    detail_end := null;

    if detail_status = 'preferred' then
      if nullif(detail_value->>'startTime', '') is not null then
        detail_start := (detail_value->>'startTime')::time;
      end if;

      if nullif(detail_value->>'endTime', '') is not null then
        detail_end := (detail_value->>'endTime')::time;
      end if;
    end if;

    if detail_status = 'default' and detail_start is null and detail_end is null and detail_note is null then
      delete from public.noble_staff_availability
      where staff_key = employee.staff_key
        and availability_date = item_date;
      continue;
    end if;

    insert into public.noble_staff_availability (
      staff_key,
      staff_name,
      branch_scope,
      availability_date,
      status,
      available_start,
      available_end,
      note
    )
    values (
      employee.staff_key,
      employee.staff_key,
      coalesce(nullif(lower(employee.branch_scope), ''), 'both'),
      item_date,
      detail_status,
      detail_start,
      detail_end,
      detail_note
    )
    on conflict (staff_key, availability_date) do update
      set status = excluded.status,
          available_start = excluded.available_start,
          available_end = excluded.available_end,
          note = excluded.note,
          submitted_at = now();
  end loop;
end;
$$;

create or replace function public.noble_get_my_schedule(
  input_ref text,
  p_from_date date default current_date - 14,
  p_to_date date default current_date + 14
)
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
begin
  select *
    into employee
  from public.lookup_employee_ref(input_ref)
  limit 1;

  if employee.staff_key is null then
    raise exception 'invalid reference code';
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
    where s.staff_key = employee.staff_key
      and w.status = 'published'
      and s.shift_date between p_from_date and p_to_date
    order by s.shift_date, s.branch, s.sort_order, s.staff_name;
end;
$$;

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

revoke all on function public.noble_submit_access_request(text, text, text) from public;
grant execute on function public.noble_submit_access_request(text, text, text) to anon, authenticated;

revoke all on function public.noble_submit_availability(text, date[], date[], jsonb) from public;
grant execute on function public.noble_submit_availability(text, date[], date[], jsonb) to anon, authenticated;

revoke all on function public.noble_get_my_schedule(text, date, date) from public;
grant execute on function public.noble_get_my_schedule(text, date, date) to anon, authenticated;

revoke all on function public.noble_get_latest_schedule(text) from public;
grant execute on function public.noble_get_latest_schedule(text) to anon, authenticated;
