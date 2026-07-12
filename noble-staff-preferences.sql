-- Noble staff preference table + RPCs.
-- Run this in Supabase SQL Editor after supabase-schema-classification.sql / noble-rpc-fix.sql.

create schema if not exists schedule;

create table if not exists schedule.staff_preferences (
  staff_key text primary key,
  staff_name text,
  branch_scope text not null default 'both' check (branch_scope in ('uptown', 'downtown', 'both')),
  fixed_unavailable_weekdays integer[] not null default '{}'::integer[],
  fixed_preferred_weekdays integer[] not null default '{}'::integer[],
  work_style text check (work_style is null or work_style in ('cluster', 'spread')),
  preferred_branch text check (preferred_branch is null or preferred_branch in ('uptown', 'downtown', 'both')),
  max_weekly_shifts integer check (max_weekly_shifts is null or max_weekly_shifts between 1 and 7),
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists staff_preferences_branch_idx
  on schedule.staff_preferences (branch_scope);

create or replace function schedule.touch_staff_preferences_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists staff_preferences_touch_updated_at on schedule.staff_preferences;
create trigger staff_preferences_touch_updated_at
before update on schedule.staff_preferences
for each row execute function schedule.touch_staff_preferences_updated_at();

alter table schedule.staff_preferences enable row level security;

revoke all on schedule.staff_preferences from anon;
revoke all on schedule.staff_preferences from authenticated;
grant select on schedule.staff_preferences to authenticated;

drop policy if exists staff_preferences_admin_select on schedule.staff_preferences;
drop policy if exists staff_preferences_admin_all on schedule.staff_preferences;
drop policy if exists staff_preferences_authenticated_select on schedule.staff_preferences;
create policy staff_preferences_authenticated_select
on schedule.staff_preferences
for select
to authenticated
using (true);

create or replace view public.noble_staff_preferences
with (security_invoker = true)
as
select
  staff_key,
  staff_name,
  branch_scope,
  fixed_unavailable_weekdays,
  fixed_preferred_weekdays,
  work_style,
  preferred_branch,
  max_weekly_shifts,
  submitted_at,
  updated_at
from schedule.staff_preferences;

revoke all on public.noble_staff_preferences from anon;
grant select on public.noble_staff_preferences to authenticated;

create or replace function public.noble_get_staff_preferences_v1(input_ref text)
returns table (
  staff_key text,
  staff_name text,
  branch_scope text,
  fixed_unavailable_weekdays integer[],
  fixed_preferred_weekdays integer[],
  work_style text,
  preferred_branch text,
  max_weekly_shifts integer,
  submitted_at timestamptz,
  updated_at timestamptz
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
      p.staff_key,
      p.staff_name,
      p.branch_scope,
      p.fixed_unavailable_weekdays,
      p.fixed_preferred_weekdays,
      p.work_style,
      p.preferred_branch,
      p.max_weekly_shifts,
      p.submitted_at,
      p.updated_at
    from schedule.staff_preferences p
    where p.staff_key = employee.staff_key;
end;
$$;

create or replace function public.noble_submit_staff_preferences_v1(
  input_ref text,
  p_fixed_unavailable_weekdays jsonb default '[]'::jsonb,
  p_fixed_preferred_weekdays jsonb default '[]'::jsonb,
  p_work_style text default null,
  p_preferred_branch text default null,
  p_max_weekly_shifts integer default null
)
returns void
language plpgsql
security definer
set search_path = public, schedule
as $$
declare
  employee record;
  normalized_branch_scope text;
  normalized_work_style text := nullif(lower(trim(coalesce(p_work_style, ''))), '');
  normalized_preferred_branch text := nullif(lower(trim(coalesce(p_preferred_branch, ''))), '');
  normalized_max_weekly_shifts integer;
  unavailable_weekdays integer[];
  preferred_weekdays integer[];
begin
  select *
    into employee
  from public.lookup_employee_ref(input_ref)
  limit 1;

  if employee.staff_key is null then
    raise exception 'invalid reference code';
  end if;

  normalized_branch_scope := coalesce(nullif(lower(employee.branch_scope), ''), 'both');
  if normalized_branch_scope not in ('uptown', 'downtown', 'both') then
    normalized_branch_scope := 'both';
  end if;

  if normalized_work_style not in ('cluster', 'spread') then
    normalized_work_style := null;
  end if;

  if normalized_preferred_branch not in ('uptown', 'downtown', 'both') then
    normalized_preferred_branch := null;
  end if;

  if p_max_weekly_shifts is not null then
    normalized_max_weekly_shifts := greatest(1, least(7, p_max_weekly_shifts));
  end if;

  select coalesce(array_agg(distinct weekday order by weekday), '{}'::integer[])
    into unavailable_weekdays
  from (
    select value::integer as weekday
    from jsonb_array_elements_text(coalesce(p_fixed_unavailable_weekdays, '[]'::jsonb))
    where value ~ '^[0-6]$'
  ) items;

  select coalesce(array_agg(distinct weekday order by weekday), '{}'::integer[])
    into preferred_weekdays
  from (
    select value::integer as weekday
    from jsonb_array_elements_text(coalesce(p_fixed_preferred_weekdays, '[]'::jsonb))
    where value ~ '^[0-6]$'
  ) items;

  insert into schedule.staff_preferences (
    staff_key,
    staff_name,
    branch_scope,
    fixed_unavailable_weekdays,
    fixed_preferred_weekdays,
    work_style,
    preferred_branch,
    max_weekly_shifts,
    submitted_at
  )
  values (
    employee.staff_key,
    employee.staff_key,
    normalized_branch_scope,
    unavailable_weekdays,
    preferred_weekdays,
    normalized_work_style,
    normalized_preferred_branch,
    normalized_max_weekly_shifts,
    now()
  )
  on conflict (staff_key) do update
    set staff_name = excluded.staff_name,
        branch_scope = excluded.branch_scope,
        fixed_unavailable_weekdays = excluded.fixed_unavailable_weekdays,
        fixed_preferred_weekdays = excluded.fixed_preferred_weekdays,
        work_style = excluded.work_style,
        preferred_branch = excluded.preferred_branch,
        max_weekly_shifts = excluded.max_weekly_shifts,
        submitted_at = now();
end;
$$;

grant execute on function public.noble_get_staff_preferences_v1(text) to anon, authenticated;
grant execute on function public.noble_submit_staff_preferences_v1(text, jsonb, jsonb, text, text, integer) to anon, authenticated;
