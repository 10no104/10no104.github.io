-- Run once in Supabase SQL Editor after supabase-schema-classification.sql.
-- Stores staff-submitted substitute requests for published schedule shifts.

create extension if not exists pgcrypto;

create table if not exists schedule.shift_substitute_requests (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid not null unique references schedule.schedule_shifts(id) on delete cascade,
  requester_staff_key text not null,
  requester_name text not null,
  shift_date date not null,
  branch text not null check (branch in ('uptown', 'downtown')),
  status text not null default 'open' check (status in ('open', 'cancelled', 'resolved')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists shift_substitute_requests_requester_idx
  on schedule.shift_substitute_requests (requester_staff_key, shift_date);

create or replace function schedule.touch_shift_substitute_request_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists shift_substitute_requests_touch_updated_at on schedule.shift_substitute_requests;
create trigger shift_substitute_requests_touch_updated_at
before update on schedule.shift_substitute_requests
for each row execute function schedule.touch_shift_substitute_request_updated_at();

alter table schedule.shift_substitute_requests enable row level security;
revoke all on schedule.shift_substitute_requests from anon;
grant select, insert, update, delete on schedule.shift_substitute_requests to authenticated;

create or replace function public.noble_get_my_substitute_requests_v1(input_ref text)
returns table (
  shift_date date,
  branch text,
  status text,
  week_start date
)
language plpgsql
security definer
set search_path = public, schedule
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
      r.shift_date,
      r.branch,
      r.status,
      w.week_start
    from schedule.shift_substitute_requests r
    join schedule.schedule_shifts s on s.id = r.shift_id
    join schedule.schedule_weeks w on w.id = s.week_id
    where r.requester_staff_key = employee.staff_key
      and r.status = 'open'
      and w.status = 'published'
    order by r.shift_date, r.branch;
end;
$$;

create or replace function public.noble_request_substitute_v1(
  input_ref text,
  p_week_start date,
  p_shift_date date,
  p_branch text
)
returns boolean
language plpgsql
security definer
set search_path = public, schedule
as $$
declare
  employee record;
  target_shift record;
begin
  select *
    into employee
  from public.lookup_employee_ref(input_ref)
  limit 1;

  if employee.staff_key is null then
    raise exception 'invalid reference code';
  end if;

  select s.id, s.staff_name
    into target_shift
  from schedule.schedule_shifts s
  join schedule.schedule_weeks w on w.id = s.week_id
  where s.staff_key = employee.staff_key
    and s.shift_date = p_shift_date
    and s.branch = lower(trim(p_branch))
    and w.week_start = p_week_start
    and w.status = 'published'
  limit 1;

  if target_shift.id is null then
    raise exception 'published shift not found for this staff member';
  end if;

  insert into schedule.shift_substitute_requests (
    shift_id,
    requester_staff_key,
    requester_name,
    shift_date,
    branch,
    status
  )
  values (
    target_shift.id,
    employee.staff_key,
    coalesce(nullif(target_shift.staff_name, ''), employee.staff_key),
    p_shift_date,
    lower(trim(p_branch)),
    'open'
  )
  on conflict (shift_id) do update
    set status = 'open',
        updated_at = now();

  return true;
end;
$$;

revoke all on function public.noble_get_my_substitute_requests_v1(text) from public;
grant execute on function public.noble_get_my_substitute_requests_v1(text) to anon, authenticated;

revoke all on function public.noble_request_substitute_v1(text, date, date, text) from public;
grant execute on function public.noble_request_substitute_v1(text, date, date, text) to anon, authenticated;
