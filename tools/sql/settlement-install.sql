-- EHWA settlement one-shot installer.
-- Run this file once in the Supabase SQL Editor.
-- Includes schema, unchanged workbook calculations, 211 historical days,
-- 864 staff-day records, Noble wage history, and King employee linkage.
-- The calculation model mirrors the Downtown sales workbook:
-- card tip fee 2%, kitchen pool 40%, hall pool 60%, then hourly distribution.

create extension if not exists pgcrypto;
create schema if not exists settlement;

grant usage on schema settlement to authenticated;
revoke all on schema settlement from anon;

create or replace function settlement.touch_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists settlement.staff_members (
  id uuid primary key default gen_random_uuid(),
  employee_ref_id uuid,
  branch text not null default 'downtown'
    check (branch in ('downtown', 'uptown')),
  department text not null
    check (department in ('kitchen', 'hall')),
  staff_key text not null,
  display_name text not null,
  tip_eligible_default boolean not null default true,
  active boolean not null default true,
  sort_order integer not null default 0,
  source_column text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch, department, staff_key)
);

alter table settlement.staff_members
  add column if not exists employee_ref_id uuid;

create table if not exists settlement.daily_entries (
  id uuid primary key default gen_random_uuid(),
  branch text not null default 'downtown'
    check (branch in ('downtown', 'uptown')),
  business_date date not null,
  total_sales numeric(14, 2) not null default 0,
  card_sales numeric(14, 2) not null default 0,
  cash_remainder numeric(14, 2) not null default 0,
  receipt_amount numeric(14, 2) not null default 0,
  card_tip numeric(14, 2) not null default 0,
  card_tip_fee_rate numeric(8, 6) not null default 0.02
    check (card_tip_fee_rate between 0 and 1),
  kitchen_share_rate numeric(8, 6) not null default 0.40
    check (kitchen_share_rate between 0 and 1),
  hall_share_rate numeric(8, 6) not null default 0.60
    check (hall_share_rate between 0 and 1),
  net_tip_adjustment numeric(14, 4) not null default 0,
  note text not null default '',
  source text not null default 'manual'
    check (source in ('manual', 'xlsx', 'google_sheet')),
  source_row integer,
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch, business_date),
  check (abs((kitchen_share_rate + hall_share_rate) - 1) < 0.000001)
);

create table if not exists settlement.daily_staff_entries (
  id uuid primary key default gen_random_uuid(),
  daily_entry_id uuid not null
    references settlement.daily_entries(id) on delete cascade,
  staff_id uuid not null
    references settlement.staff_members(id) on delete restrict,
  hours numeric(8, 2) not null default 0
    check (hours >= 0 and hours <= 24),
  tip_eligible boolean not null default true,
  tip_adjustment numeric(14, 4) not null default 0,
  tip_override numeric(14, 4),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (daily_entry_id, staff_id)
);

create index if not exists settlement_daily_entries_date_idx
  on settlement.daily_entries (business_date desc, branch);
create index if not exists settlement_daily_staff_entry_idx
  on settlement.daily_staff_entries (daily_entry_id);
create index if not exists settlement_daily_staff_staff_idx
  on settlement.daily_staff_entries (staff_id);
create index if not exists settlement_staff_roster_idx
  on settlement.staff_members (branch, department, active desc, sort_order);
create index if not exists settlement_staff_employee_ref_idx
  on settlement.staff_members (employee_ref_id, branch, active desc)
  where employee_ref_id is not null;

drop trigger if exists settlement_staff_members_touch_updated_at
  on settlement.staff_members;
create trigger settlement_staff_members_touch_updated_at
before update on settlement.staff_members
for each row execute function settlement.touch_updated_at();

drop trigger if exists settlement_daily_entries_touch_updated_at
  on settlement.daily_entries;
create trigger settlement_daily_entries_touch_updated_at
before update on settlement.daily_entries
for each row execute function settlement.touch_updated_at();

drop trigger if exists settlement_daily_staff_entries_touch_updated_at
  on settlement.daily_staff_entries;
create trigger settlement_daily_staff_entries_touch_updated_at
before update on settlement.daily_staff_entries
for each row execute function settlement.touch_updated_at();

alter table settlement.staff_members enable row level security;
alter table settlement.daily_entries enable row level security;
alter table settlement.daily_staff_entries enable row level security;

drop policy if exists settlement_staff_authenticated_all
  on settlement.staff_members;
create policy settlement_staff_authenticated_all
on settlement.staff_members
for all
to authenticated
using (true)
with check (true);

drop policy if exists settlement_daily_authenticated_all
  on settlement.daily_entries;
create policy settlement_daily_authenticated_all
on settlement.daily_entries
for all
to authenticated
using (true)
with check (true);

drop policy if exists settlement_daily_staff_authenticated_all
  on settlement.daily_staff_entries;
create policy settlement_daily_staff_authenticated_all
on settlement.daily_staff_entries
for all
to authenticated
using (true)
with check (true);

grant select, insert, update, delete
  on settlement.staff_members,
     settlement.daily_entries,
     settlement.daily_staff_entries
  to authenticated;
revoke all
  on settlement.staff_members,
     settlement.daily_entries,
     settlement.daily_staff_entries
  from anon;

create or replace function settlement.period_start(input_date date)
returns date
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select date '2025-12-31'
    + (floor(((input_date - date '2025-12-31')::numeric) / 14)::integer * 14);
$$;

create or replace view settlement.daily_calculations
with (security_invoker = true)
as
with staff_totals as (
  select
    se.daily_entry_id,
    coalesce(sum(se.hours) filter (
      where sm.department = 'kitchen' and se.tip_eligible
    ), 0)::numeric as kitchen_hours,
    coalesce(sum(se.hours) filter (
      where sm.department = 'hall' and se.tip_eligible
    ), 0)::numeric as hall_hours,
    count(*) filter (
      where sm.department = 'kitchen' and se.hours > 0
    )::integer as kitchen_staff_count,
    count(*) filter (
      where sm.department = 'hall' and se.hours > 0
    )::integer as hall_staff_count
  from settlement.daily_staff_entries se
  join settlement.staff_members sm on sm.id = se.staff_id
  group by se.daily_entry_id
),
base as (
  select
    d.*,
    settlement.period_start(d.business_date) as period_start,
    settlement.period_start(d.business_date) + 13 as period_end,
    d.total_sales - d.card_sales as cash_sales,
    d.card_sales - d.total_sales + d.cash_remainder + d.receipt_amount as gross_tip,
    d.card_tip * d.card_tip_fee_rate as card_tip_fee,
    d.card_sales - d.total_sales
      + d.cash_remainder
      + d.receipt_amount
      - (d.card_tip * d.card_tip_fee_rate)
      + d.net_tip_adjustment as net_tip,
    coalesce(st.kitchen_hours, 0) as kitchen_hours,
    coalesce(st.hall_hours, 0) as hall_hours,
    coalesce(st.kitchen_staff_count, 0) as kitchen_staff_count,
    coalesce(st.hall_staff_count, 0) as hall_staff_count
  from settlement.daily_entries d
  left join staff_totals st on st.daily_entry_id = d.id
)
select
  base.*,
  base.net_tip * base.kitchen_share_rate as kitchen_tip,
  base.net_tip * base.hall_share_rate as hall_tip,
  case
    when base.kitchen_hours > 0
      then (base.net_tip * base.kitchen_share_rate) / base.kitchen_hours
    else 0
  end as kitchen_hourly_tip,
  case
    when base.hall_hours > 0
      then (base.net_tip * base.hall_share_rate) / base.hall_hours
    else 0
  end as hall_hourly_tip,
  case
    when base.total_sales <> 0 then (base.net_tip / base.total_sales) * 100
    else 0
  end as tip_percent
from base;

create or replace view settlement.staff_calculations
with (security_invoker = true)
as
select
  se.id,
  se.daily_entry_id,
  d.business_date,
  d.period_start,
  d.period_end,
  d.branch,
  sm.id as staff_id,
  sm.employee_ref_id,
  sm.staff_key,
  sm.display_name,
  sm.department,
  sm.sort_order,
  se.hours,
  se.tip_eligible,
  se.tip_adjustment,
  se.tip_override,
  case sm.department
    when 'kitchen' then d.kitchen_hourly_tip
    else d.hall_hourly_tip
  end as hourly_tip,
  case
    when se.tip_override is not null then se.tip_override
    when se.tip_eligible then
      se.hours * case sm.department
        when 'kitchen' then d.kitchen_hourly_tip
        else d.hall_hourly_tip
      end + se.tip_adjustment
    else se.tip_adjustment
  end as tip_amount
from settlement.daily_staff_entries se
join settlement.staff_members sm on sm.id = se.staff_id
join settlement.daily_calculations d on d.id = se.daily_entry_id;

create or replace view settlement.period_summaries
with (security_invoker = true)
as
select
  d.branch,
  d.period_start,
  d.period_end,
  count(*)::integer as entered_days,
  sum(d.total_sales) as total_sales,
  sum(d.card_sales) as card_sales,
  sum(d.net_tip) as net_tip,
  sum(d.kitchen_tip) as kitchen_tip,
  sum(d.hall_tip) as hall_tip,
  sum(d.kitchen_hours) as kitchen_hours,
  sum(d.hall_hours) as hall_hours,
  count(*) filter (where nullif(trim(d.note), '') is not null)::integer as note_count
from settlement.daily_calculations d
group by d.branch, d.period_start, d.period_end;

create or replace view settlement.period_staff_summaries
with (security_invoker = true)
as
select
  s.branch,
  s.period_start,
  s.period_end,
  s.staff_id,
  s.staff_key,
  s.display_name,
  s.department,
  min(s.sort_order) as sort_order,
  count(*) filter (where s.hours > 0)::integer as worked_days,
  sum(s.hours) as total_hours,
  sum(s.tip_amount) as total_tip,
  case when sum(s.hours) > 0 then sum(s.tip_amount) / sum(s.hours) else 0 end as average_tip_per_hour
from settlement.staff_calculations s
group by
  s.branch,
  s.period_start,
  s.period_end,
  s.staff_id,
  s.staff_key,
  s.display_name,
  s.department;

create or replace view public.settlement_staff_members
with (security_invoker = true)
as select * from settlement.staff_members;

create or replace view public.settlement_daily_entries
with (security_invoker = true)
as select * from settlement.daily_entries;

create or replace view public.settlement_daily_staff_entries
with (security_invoker = true)
as select * from settlement.daily_staff_entries;

create or replace view public.settlement_daily_calculations
with (security_invoker = true)
as select * from settlement.daily_calculations;

create or replace view public.settlement_staff_calculations
with (security_invoker = true)
as select * from settlement.staff_calculations;

grant select on
  public.settlement_staff_members,
  public.settlement_daily_entries,
  public.settlement_daily_staff_entries,
  public.settlement_daily_calculations,
  public.settlement_staff_calculations
to authenticated;

revoke all on
  public.settlement_staff_members,
  public.settlement_daily_entries,
  public.settlement_daily_staff_entries,
  public.settlement_daily_calculations,
  public.settlement_staff_calculations
from anon;

create or replace function public.settlement_get_day_v1(
  input_branch text,
  input_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public, settlement
as $$
declare
  normalized_branch text := lower(trim(coalesce(input_branch, 'downtown')));
  target_entry_id uuid;
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  if normalized_branch not in ('downtown', 'uptown') then
    raise exception 'invalid branch';
  end if;
  if input_date is null then
    raise exception 'date is required';
  end if;

  select id
  into target_entry_id
  from settlement.daily_entries
  where branch = normalized_branch
    and business_date = input_date;

  select jsonb_build_object(
    'entry',
    (
      select to_jsonb(d)
      from settlement.daily_calculations d
      where d.id = target_entry_id
    ),
    'staff',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'staff_id', sm.id,
            'employee_ref_id', sm.employee_ref_id,
            'staff_key', sm.staff_key,
            'display_name', sm.display_name,
            'department', sm.department,
            'active', sm.active,
            'sort_order', sm.sort_order,
            'hours', coalesce(se.hours, 0),
            'tip_eligible', coalesce(se.tip_eligible, sm.tip_eligible_default),
            'tip_adjustment', coalesce(se.tip_adjustment, 0),
            'tip_override', se.tip_override,
            'tip_amount', coalesce(sc.tip_amount, 0)
          )
          order by
            case sm.department when 'kitchen' then 0 else 1 end,
            sm.sort_order,
            sm.display_name
        )
        from settlement.staff_members sm
        left join settlement.daily_staff_entries se
          on se.staff_id = sm.id
         and se.daily_entry_id = target_entry_id
        left join settlement.staff_calculations sc on sc.id = se.id
        where sm.branch = normalized_branch
          and (sm.active or se.id is not null)
      ),
      '[]'::jsonb
    )
  )
  into result;

  return result;
end;
$$;

create or replace function public.settlement_save_day_v1(input_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, settlement
as $$
declare
  normalized_branch text := lower(trim(coalesce(input_payload ->> 'branch', 'downtown')));
  target_date date;
  target_entry_id uuid;
  item jsonb;
  item_staff_id uuid;
  saved_staff_ids uuid[] := '{}'::uuid[];
  item_hours numeric;
  item_adjustment numeric;
  item_override numeric;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  if normalized_branch not in ('downtown', 'uptown') then
    raise exception 'invalid branch';
  end if;

  target_date := nullif(input_payload ->> 'business_date', '')::date;
  if target_date is null then
    raise exception 'date is required';
  end if;

  insert into settlement.daily_entries (
    branch,
    business_date,
    total_sales,
    card_sales,
    cash_remainder,
    receipt_amount,
    card_tip,
    card_tip_fee_rate,
    kitchen_share_rate,
    hall_share_rate,
    net_tip_adjustment,
    note,
    source,
    updated_by
  )
  values (
    normalized_branch,
    target_date,
    coalesce(nullif(input_payload ->> 'total_sales', '')::numeric, 0),
    coalesce(nullif(input_payload ->> 'card_sales', '')::numeric, 0),
    coalesce(nullif(input_payload ->> 'cash_remainder', '')::numeric, 0),
    coalesce(nullif(input_payload ->> 'receipt_amount', '')::numeric, 0),
    coalesce(nullif(input_payload ->> 'card_tip', '')::numeric, 0),
    coalesce(nullif(input_payload ->> 'card_tip_fee_rate', '')::numeric, 0.02),
    coalesce(nullif(input_payload ->> 'kitchen_share_rate', '')::numeric, 0.40),
    coalesce(nullif(input_payload ->> 'hall_share_rate', '')::numeric, 0.60),
    coalesce(nullif(input_payload ->> 'net_tip_adjustment', '')::numeric, 0),
    left(coalesce(input_payload ->> 'note', ''), 2000),
    'manual',
    auth.uid()
  )
  on conflict (branch, business_date)
  do update set
    total_sales = excluded.total_sales,
    card_sales = excluded.card_sales,
    cash_remainder = excluded.cash_remainder,
    receipt_amount = excluded.receipt_amount,
    card_tip = excluded.card_tip,
    card_tip_fee_rate = excluded.card_tip_fee_rate,
    kitchen_share_rate = excluded.kitchen_share_rate,
    hall_share_rate = excluded.hall_share_rate,
    net_tip_adjustment = excluded.net_tip_adjustment,
    note = excluded.note,
    updated_by = auth.uid()
  returning id into target_entry_id;

  for item in
    select value
    from jsonb_array_elements(coalesce(input_payload -> 'staff', '[]'::jsonb))
  loop
    item_staff_id := nullif(item ->> 'staff_id', '')::uuid;
    if item_staff_id is null or not exists (
      select 1
      from settlement.staff_members sm
      where sm.id = item_staff_id
        and sm.branch = normalized_branch
    ) then
      raise exception 'invalid staff member';
    end if;

    item_hours := coalesce(nullif(item ->> 'hours', '')::numeric, 0);
    item_adjustment := coalesce(nullif(item ->> 'tip_adjustment', '')::numeric, 0);
    item_override := nullif(item ->> 'tip_override', '')::numeric;

    if item_hours = 0 and item_adjustment = 0 and item_override is null then
      delete from settlement.daily_staff_entries
      where daily_entry_id = target_entry_id
        and staff_id = item_staff_id;
    else
      insert into settlement.daily_staff_entries (
        daily_entry_id,
        staff_id,
        hours,
        tip_eligible,
        tip_adjustment,
        tip_override
      )
      values (
        target_entry_id,
        item_staff_id,
        item_hours,
        coalesce((item ->> 'tip_eligible')::boolean, true),
        item_adjustment,
        item_override
      )
      on conflict (daily_entry_id, staff_id)
      do update set
        hours = excluded.hours,
        tip_eligible = excluded.tip_eligible,
        tip_adjustment = excluded.tip_adjustment,
        tip_override = excluded.tip_override;
    end if;

    saved_staff_ids := array_append(saved_staff_ids, item_staff_id);
  end loop;

  delete from settlement.daily_staff_entries
  where daily_entry_id = target_entry_id
    and not (staff_id = any(saved_staff_ids));

  return public.settlement_get_day_v1(normalized_branch, target_date);
end;
$$;

create or replace function public.settlement_save_staff_v1(input_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, settlement
as $$
declare
  normalized_branch text := lower(trim(coalesce(input_payload ->> 'branch', 'downtown')));
  normalized_department text := lower(trim(coalesce(input_payload ->> 'department', 'hall')));
  target_id uuid := nullif(input_payload ->> 'id', '')::uuid;
  result settlement.staff_members%rowtype;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  if normalized_branch not in ('downtown', 'uptown') then
    raise exception 'invalid branch';
  end if;
  if normalized_department not in ('kitchen', 'hall') then
    raise exception 'invalid department';
  end if;
  if nullif(trim(input_payload ->> 'display_name'), '') is null then
    raise exception 'staff name is required';
  end if;

  if target_id is null then
    insert into settlement.staff_members (
      employee_ref_id,
      branch,
      department,
      staff_key,
      display_name,
      tip_eligible_default,
      active,
      sort_order
    )
    values (
      nullif(input_payload ->> 'employee_ref_id', '')::uuid,
      normalized_branch,
      normalized_department,
      coalesce(
        nullif(trim(input_payload ->> 'staff_key'), ''),
        trim(input_payload ->> 'display_name')
      ),
      trim(input_payload ->> 'display_name'),
      coalesce((input_payload ->> 'tip_eligible_default')::boolean, true),
      coalesce((input_payload ->> 'active')::boolean, true),
      coalesce(nullif(input_payload ->> 'sort_order', '')::integer, 0)
    )
    on conflict (branch, department, staff_key)
    do update set
      employee_ref_id = coalesce(excluded.employee_ref_id, settlement.staff_members.employee_ref_id),
      display_name = excluded.display_name,
      tip_eligible_default = excluded.tip_eligible_default,
      active = excluded.active,
      sort_order = excluded.sort_order
    returning * into result;
  else
    update settlement.staff_members
    set
      employee_ref_id = coalesce(
        nullif(input_payload ->> 'employee_ref_id', '')::uuid,
        employee_ref_id
      ),
      department = normalized_department,
      staff_key = coalesce(
        nullif(trim(input_payload ->> 'staff_key'), ''),
        staff_key
      ),
      display_name = trim(input_payload ->> 'display_name'),
      tip_eligible_default = coalesce(
        (input_payload ->> 'tip_eligible_default')::boolean,
        tip_eligible_default
      ),
      active = coalesce((input_payload ->> 'active')::boolean, active),
      sort_order = coalesce(
        nullif(input_payload ->> 'sort_order', '')::integer,
        sort_order
      )
    where id = target_id
      and branch = normalized_branch
    returning * into result;
  end if;

  if result.id is null then
    raise exception 'staff member not found';
  end if;
  return to_jsonb(result);
end;
$$;

create or replace function public.settlement_get_summary_v1(
  input_branch text default 'downtown',
  input_from date default null,
  input_to date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, settlement
as $$
declare
  normalized_branch text := lower(trim(coalesce(input_branch, 'downtown')));
  first_date date;
  last_date date;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  if normalized_branch not in ('downtown', 'uptown') then
    raise exception 'invalid branch';
  end if;

  select
    min(business_date),
    max(business_date)
  into first_date, last_date
  from settlement.daily_entries
  where branch = normalized_branch;

  first_date := coalesce(input_from, first_date, current_date);
  last_date := coalesce(input_to, last_date, current_date);

  return jsonb_build_object(
    'range',
    jsonb_build_object(
      'first_date', first_date,
      'last_date', last_date
    ),
    'daily',
    coalesce(
      (
        select jsonb_agg(to_jsonb(d) order by d.business_date desc)
        from settlement.daily_calculations d
        where d.branch = normalized_branch
          and d.business_date between first_date and last_date
      ),
      '[]'::jsonb
    ),
    'periods',
    coalesce(
      (
        select jsonb_agg(to_jsonb(p) order by p.period_start desc)
        from settlement.period_summaries p
        where p.branch = normalized_branch
          and p.period_end >= first_date
          and p.period_start <= last_date
      ),
      '[]'::jsonb
    ),
    'staff',
    coalesce(
      (
        select jsonb_agg(
          to_jsonb(s)
          order by
            s.period_start desc,
            case s.department when 'kitchen' then 0 else 1 end,
            s.sort_order,
            s.display_name
        )
        from settlement.period_staff_summaries s
        where s.branch = normalized_branch
          and s.period_end >= first_date
          and s.period_start <= last_date
      ),
      '[]'::jsonb
    )
  );
end;
$$;

create or replace function public.noble_get_wage_history_v1(input_ref text)
returns table (
  work_date date,
  branch text,
  staff_key text,
  staff_name text,
  department text,
  hours numeric,
  tips numeric,
  hourly_tip numeric,
  department_tip numeric,
  period_start date,
  period_end date
)
language plpgsql
security definer
set search_path = public, staff, settlement
as $$
declare
  employee record;
  normalized_staff_key text;
begin
  select
    e.id,
    e.staff_key,
    e.branch_scope
  into employee
  from public.employee_refs e
  where lower(trim(e.ref_code)) = lower(trim(input_ref))
  limit 1;

  if employee.id is null then
    raise exception 'invalid reference code';
  end if;

  normalized_staff_key := regexp_replace(lower(employee.staff_key), '\s+', '', 'g');

  return query
  select
    s.business_date,
    s.branch,
    s.staff_key,
    s.display_name,
    s.department,
    s.hours,
    s.tip_amount,
    s.hourly_tip,
    case s.department
      when 'kitchen' then d.kitchen_tip
      else d.hall_tip
    end,
    s.period_start,
    s.period_end
  from settlement.staff_calculations s
  join settlement.daily_calculations d on d.id = s.daily_entry_id
  where (
      s.employee_ref_id = employee.id
      or (
        s.employee_ref_id is null
        and (
          regexp_replace(lower(s.staff_key), '\s+', '', 'g') = normalized_staff_key
          or regexp_replace(lower(s.display_name), '\s+', '', 'g') = normalized_staff_key
        )
      )
    )
    and (
      lower(coalesce(employee.branch_scope, 'both')) = 'both'
      or lower(employee.branch_scope) = s.branch
    )
    and (s.hours <> 0 or s.tip_amount <> 0)
  order by s.business_date desc, s.branch;
end;
$$;

drop function if exists public.king_get_employee_refs();
create function public.king_get_employee_refs()
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
  updated_at timestamptz,
  settlement_department text,
  settlement_tip_eligible boolean,
  settlement_linked boolean
)
language sql
security definer
set search_path = public, staff, settlement
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
    e.updated_at,
    coalesce(
      linked_staff.department,
      case when lower(coalesce(e.job_role, '')) = 'kitchen' then 'kitchen' else 'hall' end
    ) as settlement_department,
    coalesce(linked_staff.tip_eligible_default, true) as settlement_tip_eligible,
    (linked_staff.id is not null) as settlement_linked
  from public.employee_refs e
  left join lateral (
    select sm.id, sm.department, sm.tip_eligible_default
    from settlement.staff_members sm
    where sm.employee_ref_id = e.id
    order by sm.active desc, sm.updated_at desc, sm.sort_order
    limit 1
  ) linked_staff on true
  order by e.active desc, e.branch_scope, e.staff_key;
$$;

create or replace function public.king_save_employee_with_settlement_v1(
  input_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, staff, settlement
as $$
declare
  target_employee_id uuid := nullif(input_payload ->> 'id', '')::uuid;
  target_request_id uuid := nullif(input_payload ->> 'request_id', '')::uuid;
  normalized_name text := trim(coalesce(input_payload ->> 'staff_key', ''));
  normalized_ref text := trim(coalesce(input_payload ->> 'ref_code', ''));
  normalized_branch_scope text := lower(trim(coalesce(input_payload ->> 'branch_scope', 'both')));
  normalized_department text := lower(trim(coalesce(input_payload ->> 'settlement_department', 'hall')));
  normalized_job_role text;
  normalized_name_key text;
  requested_active boolean := coalesce(nullif(input_payload ->> 'active', '')::boolean, true);
  requested_tip_eligible boolean := coalesce(
    nullif(input_payload ->> 'settlement_tip_eligible', '')::boolean,
    true
  );
  target_branches text[];
  target_branch text;
  target_staff_id uuid;
  employee_row record;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  if normalized_name = '' or normalized_ref = '' then
    raise exception 'name and reference code are required';
  end if;
  if normalized_branch_scope not in ('downtown', 'uptown', 'both') then
    raise exception 'invalid branch_scope';
  end if;
  if normalized_department not in ('kitchen', 'hall') then
    raise exception 'invalid settlement department';
  end if;

  normalized_job_role := case
    when normalized_department = 'kitchen' then 'kitchen'
    else coalesce(nullif(trim(input_payload ->> 'job_role'), ''), 'server')
  end;
  normalized_name_key := regexp_replace(lower(normalized_name), '\s+', '', 'g');
  target_branches := case
    when normalized_branch_scope = 'both' then array['downtown', 'uptown']::text[]
    else array[normalized_branch_scope]::text[]
  end;

  if target_employee_id is null then
    insert into public.employee_refs (
      ref_code,
      staff_key,
      job_role,
      branch_scope,
      phone_number,
      sin_number,
      active,
      inactive_at
    )
    values (
      normalized_ref,
      normalized_name,
      normalized_job_role,
      normalized_branch_scope,
      nullif(trim(coalesce(input_payload ->> 'phone_number', '')), ''),
      nullif(trim(coalesce(input_payload ->> 'sin_number', '')), ''),
      requested_active,
      case
        when requested_active then null
        else coalesce(nullif(input_payload ->> 'inactive_at', '')::timestamptz, now())
      end
    )
    returning * into employee_row;
  else
    update public.employee_refs
    set
      ref_code = normalized_ref,
      staff_key = normalized_name,
      job_role = normalized_job_role,
      branch_scope = normalized_branch_scope,
      phone_number = nullif(trim(coalesce(input_payload ->> 'phone_number', '')), ''),
      sin_number = nullif(trim(coalesce(input_payload ->> 'sin_number', '')), ''),
      active = requested_active,
      inactive_at = case
        when requested_active then null
        else coalesce(
          inactive_at,
          nullif(input_payload ->> 'inactive_at', '')::timestamptz,
          now()
        )
      end
    where id = target_employee_id
    returning * into employee_row;
  end if;

  if employee_row.id is null then
    raise exception 'employee not found';
  end if;

  update settlement.staff_members
  set active = false
  where employee_ref_id = employee_row.id
    and (
      not requested_active
      or not (branch = any(target_branches))
      or department <> normalized_department
    );

  if requested_active then
    foreach target_branch in array target_branches
    loop
      target_staff_id := null;

      select sm.id
      into target_staff_id
      from settlement.staff_members sm
      where sm.employee_ref_id = employee_row.id
        and sm.branch = target_branch
        and sm.department = normalized_department
      order by sm.active desc, sm.updated_at desc
      limit 1;

      if target_staff_id is null then
        select sm.id
        into target_staff_id
        from settlement.staff_members sm
        where sm.employee_ref_id is null
          and sm.branch = target_branch
          and sm.department = normalized_department
          and regexp_replace(lower(sm.staff_key), '\s+', '', 'g') = normalized_name_key
        order by sm.active desc, sm.sort_order
        limit 1;
      end if;

      if target_staff_id is null then
        insert into settlement.staff_members (
          employee_ref_id,
          branch,
          department,
          staff_key,
          display_name,
          tip_eligible_default,
          active,
          sort_order
        )
        values (
          employee_row.id,
          target_branch,
          normalized_department,
          normalized_name,
          normalized_name,
          requested_tip_eligible,
          true,
          coalesce(
            (
              select max(sm.sort_order) + 1
              from settlement.staff_members sm
              where sm.branch = target_branch
                and sm.department = normalized_department
            ),
            0
          )
        )
        returning id into target_staff_id;
      else
        update settlement.staff_members
        set
          employee_ref_id = employee_row.id,
          staff_key = normalized_name,
          display_name = normalized_name,
          tip_eligible_default = requested_tip_eligible,
          active = true
        where id = target_staff_id;
      end if;
    end loop;
  end if;

  if target_request_id is not null then
    update public.noble_access_requests
    set status = 'done'
    where id = target_request_id;
  end if;

  return jsonb_build_object(
    'employee',
    to_jsonb(employee_row),
    'settlement_staff',
    coalesce(
      (
        select jsonb_agg(to_jsonb(sm) order by sm.branch, sm.department)
        from settlement.staff_members sm
        where sm.employee_ref_id = employee_row.id
          and sm.active
      ),
      '[]'::jsonb
    )
  );
end;
$$;

revoke all on function public.settlement_get_day_v1(text, date) from public;
revoke all on function public.settlement_save_day_v1(jsonb) from public;
revoke all on function public.settlement_save_staff_v1(jsonb) from public;
revoke all on function public.settlement_get_summary_v1(text, date, date) from public;
revoke all on function public.noble_get_wage_history_v1(text) from public;
revoke all on function public.king_get_employee_refs() from public;
revoke all on function public.king_save_employee_with_settlement_v1(jsonb) from public;

grant execute on function public.settlement_get_day_v1(text, date)
  to authenticated;
grant execute on function public.settlement_save_day_v1(jsonb)
  to authenticated;
grant execute on function public.settlement_save_staff_v1(jsonb)
  to authenticated;
grant execute on function public.settlement_get_summary_v1(text, date, date)
  to authenticated;
grant execute on function public.noble_get_wage_history_v1(text)
  to anon, authenticated;
grant execute on function public.king_get_employee_refs()
  to authenticated;
grant execute on function public.king_save_employee_with_settlement_v1(jsonb)
  to authenticated;

comment on schema settlement is
  'Daily settlement inputs, staff hours, tip calculations, and biweekly history.';
comment on column settlement.staff_members.employee_ref_id is
  'Logical link to the King/Noble employee_refs row. Nullable for workbook-only historical staff.';
comment on column settlement.daily_entries.net_tip_adjustment is
  'Manual correction added after the standard 2% card-tip fee calculation.';
comment on column settlement.daily_staff_entries.tip_override is
  'Exact historical tip value imported from the workbook; null for normal calculated entries.';
comment on function public.king_save_employee_with_settlement_v1(jsonb) is
  'Atomically saves a King employee and activates matching settlement wage roster rows.';

-- Generated from G:/Downloads/Downtown이화매출.xlsx.
-- Source sheets: 매출 26, 주방 26, 홀 26.
-- 211 daily records and 864 staff-day records.
-- Embedded after the schema in settlement-install.sql. Safe to rerun.

begin;

insert into settlement.staff_members (
  branch,
  department,
  staff_key,
  display_name,
  tip_eligible_default,
  active,
  sort_order,
  source_column
)
select
  x.branch,
  x.department,
  x.staff_key,
  x.display_name,
  x.tip_eligible_default,
  x.active,
  x.sort_order,
  x.source_column
from jsonb_to_recordset(
  $staff$[{"branch":"downtown","department":"kitchen","staff_key":"신성경","display_name":"신성경","tip_eligible_default":true,"active":true,"sort_order":0,"source_column":"H:I"},{"branch":"downtown","department":"kitchen","staff_key":"이현구","display_name":"이현구","tip_eligible_default":true,"active":true,"sort_order":1,"source_column":"J:K"},{"branch":"downtown","department":"kitchen","staff_key":"사장님","display_name":"사장님","tip_eligible_default":true,"active":false,"sort_order":2,"source_column":"L:M"},{"branch":"downtown","department":"kitchen","staff_key":"부경","display_name":"부경","tip_eligible_default":true,"active":true,"sort_order":3,"source_column":"N:O"},{"branch":"downtown","department":"kitchen","staff_key":"허준서","display_name":"허준서","tip_eligible_default":false,"active":true,"sort_order":4,"source_column":"P:Q"},{"branch":"downtown","department":"kitchen","staff_key":"태연","display_name":"태연","tip_eligible_default":false,"active":false,"sort_order":5,"source_column":"R:S"},{"branch":"downtown","department":"kitchen","staff_key":"예슬","display_name":"예슬","tip_eligible_default":false,"active":false,"sort_order":6,"source_column":"T:U"},{"branch":"downtown","department":"kitchen","staff_key":"성우","display_name":"성우","tip_eligible_default":false,"active":false,"sort_order":7,"source_column":"V:W"},{"branch":"downtown","department":"kitchen","staff_key":"은성","display_name":"은성","tip_eligible_default":false,"active":false,"sort_order":8,"source_column":"X:Y"},{"branch":"downtown","department":"hall","staff_key":"영환","display_name":"영환","tip_eligible_default":true,"active":true,"sort_order":9,"source_column":"H:I"},{"branch":"downtown","department":"hall","staff_key":"서윤","display_name":"서윤","tip_eligible_default":true,"active":true,"sort_order":10,"source_column":"J:K"},{"branch":"downtown","department":"hall","staff_key":"우진","display_name":"우진","tip_eligible_default":true,"active":false,"sort_order":11,"source_column":"L:M"},{"branch":"downtown","department":"hall","staff_key":"은성","display_name":"은성","tip_eligible_default":true,"active":true,"sort_order":12,"source_column":"N:O"},{"branch":"downtown","department":"hall","staff_key":"혜지","display_name":"혜지","tip_eligible_default":true,"active":false,"sort_order":13,"source_column":"P:Q"},{"branch":"downtown","department":"hall","staff_key":"선빈","display_name":"선빈","tip_eligible_default":true,"active":false,"sort_order":14,"source_column":"R:S"},{"branch":"downtown","department":"hall","staff_key":"예림","display_name":"예림","tip_eligible_default":true,"active":true,"sort_order":15,"source_column":"T:U"},{"branch":"downtown","department":"hall","staff_key":"수현","display_name":"수현","tip_eligible_default":true,"active":false,"sort_order":16,"source_column":"V:W"},{"branch":"downtown","department":"hall","staff_key":"민영","display_name":"민영","tip_eligible_default":true,"active":false,"sort_order":17,"source_column":"X:Y"},{"branch":"downtown","department":"hall","staff_key":"제윤","display_name":"제윤","tip_eligible_default":true,"active":true,"sort_order":18,"source_column":"Z:AA"},{"branch":"downtown","department":"hall","staff_key":"주은","display_name":"주은","tip_eligible_default":true,"active":true,"sort_order":19,"source_column":"AB:AC"},{"branch":"downtown","department":"hall","staff_key":"소정","display_name":"소정","tip_eligible_default":true,"active":true,"sort_order":20,"source_column":"AD:AE"},{"branch":"downtown","department":"hall","staff_key":"지민","display_name":"지민","tip_eligible_default":false,"active":true,"sort_order":21,"source_column":"AF"},{"branch":"downtown","department":"hall","staff_key":"이준서","display_name":"이준서","tip_eligible_default":false,"active":true,"sort_order":22,"source_column":"AG"},{"branch":"downtown","department":"hall","staff_key":"민재","display_name":"민재","tip_eligible_default":true,"active":false,"sort_order":23,"source_column":"AI:AJ"}]$staff$::jsonb
) as x(
  branch text,
  department text,
  staff_key text,
  display_name text,
  tip_eligible_default boolean,
  active boolean,
  sort_order integer,
  source_column text
)
on conflict (branch, department, staff_key)
do update set
  display_name = excluded.display_name,
  tip_eligible_default = excluded.tip_eligible_default,
  active = excluded.active,
  sort_order = excluded.sort_order,
  source_column = excluded.source_column;

insert into settlement.daily_entries (
  branch,
  business_date,
  total_sales,
  card_sales,
  cash_remainder,
  receipt_amount,
  card_tip,
  card_tip_fee_rate,
  kitchen_share_rate,
  hall_share_rate,
  net_tip_adjustment,
  note,
  source,
  source_row
)
select
  x.branch,
  x.business_date,
  x.total_sales,
  x.card_sales,
  x.cash_remainder,
  x.receipt_amount,
  x.card_tip,
  0.02,
  0.40,
  0.60,
  x.net_tip_adjustment,
  '',
  'xlsx',
  x.source_row
from jsonb_to_recordset(
  $daily$[{"branch":"downtown","business_date":"2025-12-31","total_sales":5858.52,"card_sales":6358.81,"cash_remainder":267.4,"receipt_amount":20.99,"card_tip":779.05,"net_tip_adjustment":0,"source_row":2},{"branch":"downtown","business_date":"2026-01-01","total_sales":1118.12,"card_sales":1228.12,"cash_remainder":20,"receipt_amount":0,"card_tip":129.99,"net_tip_adjustment":0,"source_row":3},{"branch":"downtown","business_date":"2026-01-02","total_sales":2706.57,"card_sales":2549.71,"cash_remainder":539,"receipt_amount":0,"card_tip":324.25,"net_tip_adjustment":0,"source_row":4},{"branch":"downtown","business_date":"2026-01-03","total_sales":2632.21,"card_sales":3172.95,"cash_remainder":-156,"receipt_amount":0,"card_tip":382.87,"net_tip_adjustment":0,"source_row":5},{"branch":"downtown","business_date":"2026-01-04","total_sales":1909.94,"card_sales":2010.37,"cash_remainder":190,"receipt_amount":0,"card_tip":259.66,"net_tip_adjustment":0,"source_row":6},{"branch":"downtown","business_date":"2026-01-05","total_sales":1693.81,"card_sales":1573.39,"cash_remainder":0,"receipt_amount":0,"card_tip":158.17,"net_tip_adjustment":330.42,"source_row":7},{"branch":"downtown","business_date":"2026-01-06","total_sales":1700.93,"card_sales":1963.58,"cash_remainder":0,"receipt_amount":0,"card_tip":262.64,"net_tip_adjustment":0,"source_row":8},{"branch":"downtown","business_date":"2026-01-07","total_sales":1406.14,"card_sales":1412.78,"cash_remainder":105,"receipt_amount":0,"card_tip":106.04,"net_tip_adjustment":0,"source_row":9},{"branch":"downtown","business_date":"2026-01-08","total_sales":803.43,"card_sales":931.87,"cash_remainder":0,"receipt_amount":0,"card_tip":128.45,"net_tip_adjustment":0,"source_row":10},{"branch":"downtown","business_date":"2026-01-09","total_sales":5867.17,"card_sales":6442.31,"cash_remainder":196.4,"receipt_amount":15.97,"card_tip":770.77,"net_tip_adjustment":0,"source_row":11},{"branch":"downtown","business_date":"2026-01-10","total_sales":2667.12,"card_sales":2860.68,"cash_remainder":175,"receipt_amount":0,"card_tip":337,"net_tip_adjustment":0,"source_row":12},{"branch":"downtown","business_date":"2026-01-11","total_sales":1208.24,"card_sales":1372.59,"cash_remainder":0,"receipt_amount":0,"card_tip":164.37,"net_tip_adjustment":0,"source_row":13},{"branch":"downtown","business_date":"2026-01-12","total_sales":2027.28,"card_sales":2295.21,"cash_remainder":0,"receipt_amount":0,"card_tip":271.67,"net_tip_adjustment":3.74,"source_row":14},{"branch":"downtown","business_date":"2026-01-13","total_sales":2038.59,"card_sales":2135.95,"cash_remainder":150,"receipt_amount":0,"card_tip":229.45,"net_tip_adjustment":0,"source_row":15},{"branch":"downtown","business_date":"2026-01-14","total_sales":1806.09,"card_sales":1914.16,"cash_remainder":134.45,"receipt_amount":0,"card_tip":226.11,"net_tip_adjustment":0,"source_row":17},{"branch":"downtown","business_date":"2026-01-15","total_sales":1597.24,"card_sales":1806.94,"cash_remainder":0,"receipt_amount":0,"card_tip":209.7,"net_tip_adjustment":0,"source_row":18},{"branch":"downtown","business_date":"2026-01-16","total_sales":5409.91,"card_sales":5824.11,"cash_remainder":288,"receipt_amount":0,"card_tip":691.5,"net_tip_adjustment":0,"source_row":19},{"branch":"downtown","business_date":"2026-01-17","total_sales":5047.64,"card_sales":5314.25,"cash_remainder":280,"receipt_amount":0,"card_tip":504.54,"net_tip_adjustment":0,"source_row":20},{"branch":"downtown","business_date":"2026-01-18","total_sales":1811.1,"card_sales":2030.04,"cash_remainder":-30,"receipt_amount":29.98,"card_tip":218.94,"net_tip_adjustment":0,"source_row":21},{"branch":"downtown","business_date":"2026-01-19","total_sales":1350.89,"card_sales":1458.23,"cash_remainder":0,"receipt_amount":0,"card_tip":176.58,"net_tip_adjustment":72.66,"source_row":22},{"branch":"downtown","business_date":"2026-01-20","total_sales":896.29,"card_sales":1030.75,"cash_remainder":0,"receipt_amount":0,"card_tip":134.76,"net_tip_adjustment":0,"source_row":23},{"branch":"downtown","business_date":"2026-01-21","total_sales":2629.56,"card_sales":2887.48,"cash_remainder":120,"receipt_amount":0,"card_tip":353.1,"net_tip_adjustment":0,"source_row":24},{"branch":"downtown","business_date":"2026-01-22","total_sales":2075.6,"card_sales":2300.56,"cash_remainder":0,"receipt_amount":0,"card_tip":281.46,"net_tip_adjustment":0.04,"source_row":25},{"branch":"downtown","business_date":"2026-01-23","total_sales":5274.61,"card_sales":5769.48,"cash_remainder":310,"receipt_amount":0,"card_tip":679.62,"net_tip_adjustment":0,"source_row":26},{"branch":"downtown","business_date":"2026-01-24","total_sales":4139.95,"card_sales":4545.9,"cash_remainder":131,"receipt_amount":0,"card_tip":559.04,"net_tip_adjustment":0,"source_row":27},{"branch":"downtown","business_date":"2026-01-25","total_sales":2277.39,"card_sales":2480.22,"cash_remainder":31,"receipt_amount":14.99,"card_tip":244.62,"net_tip_adjustment":0,"source_row":28},{"branch":"downtown","business_date":"2026-01-26","total_sales":1002.19,"card_sales":1152.55,"cash_remainder":0,"receipt_amount":0,"card_tip":150.34,"net_tip_adjustment":0,"source_row":29},{"branch":"downtown","business_date":"2026-01-27","total_sales":1901.02,"card_sales":2166.3,"cash_remainder":15,"receipt_amount":0,"card_tip":265.3,"net_tip_adjustment":0,"source_row":30},{"branch":"downtown","business_date":"2026-01-28","total_sales":834.09,"card_sales":953.01,"cash_remainder":-6,"receipt_amount":15.98,"card_tip":128.95,"net_tip_adjustment":0,"source_row":32},{"branch":"downtown","business_date":"2026-01-29","total_sales":2463.46,"card_sales":2774.65,"cash_remainder":0,"receipt_amount":0,"card_tip":311.15,"net_tip_adjustment":0,"source_row":33},{"branch":"downtown","business_date":"2026-01-30","total_sales":5115.88,"card_sales":5766.92,"cash_remainder":29.4,"receipt_amount":0,"card_tip":668.71,"net_tip_adjustment":0,"source_row":34},{"branch":"downtown","business_date":"2026-01-31","total_sales":1908.33,"card_sales":2193.87,"cash_remainder":-5,"receipt_amount":5,"card_tip":285.53,"net_tip_adjustment":0,"source_row":35},{"branch":"downtown","business_date":"2026-02-01","total_sales":1990.69,"card_sales":2058.77,"cash_remainder":190,"receipt_amount":0,"card_tip":243.21,"net_tip_adjustment":0,"source_row":36},{"branch":"downtown","business_date":"2026-02-02","total_sales":2545.85,"card_sales":2224.62,"cash_remainder":635,"receipt_amount":19.98,"card_tip":256.39,"net_tip_adjustment":0,"source_row":37},{"branch":"downtown","business_date":"2026-02-03","total_sales":958.92,"card_sales":797.78,"cash_remainder":237.8,"receipt_amount":7.19,"card_tip":73.77,"net_tip_adjustment":0,"source_row":38},{"branch":"downtown","business_date":"2026-02-04","total_sales":1067.81,"card_sales":1187.55,"cash_remainder":30,"receipt_amount":0,"card_tip":149.1,"net_tip_adjustment":0,"source_row":39},{"branch":"downtown","business_date":"2026-02-05","total_sales":2654.89,"card_sales":2894.47,"cash_remainder":125,"receipt_amount":0,"card_tip":349.15,"net_tip_adjustment":0,"source_row":40},{"branch":"downtown","business_date":"2026-02-06","total_sales":5580.15,"card_sales":6206.11,"cash_remainder":0,"receipt_amount":0,"card_tip":625.88,"net_tip_adjustment":0,"source_row":41},{"branch":"downtown","business_date":"2026-02-07","total_sales":5490.31,"card_sales":5832.09,"cash_remainder":59.6,"receipt_amount":50.4,"card_tip":444.56,"net_tip_adjustment":0,"source_row":42},{"branch":"downtown","business_date":"2026-02-08","total_sales":641.47,"card_sales":644.26,"cash_remainder":106,"receipt_amount":0,"card_tip":84.08,"net_tip_adjustment":0,"source_row":43},{"branch":"downtown","business_date":"2026-02-09","total_sales":1045.41,"card_sales":729.37,"cash_remainder":510,"receipt_amount":0,"card_tip":86.04,"net_tip_adjustment":0,"source_row":44},{"branch":"downtown","business_date":"2026-02-10","total_sales":1134.54,"card_sales":1228.71,"cash_remainder":50,"receipt_amount":0,"card_tip":135.96,"net_tip_adjustment":0,"source_row":45},{"branch":"downtown","business_date":"2026-02-11","total_sales":989.36,"card_sales":1130.99,"cash_remainder":-26.3,"receipt_amount":26.28,"card_tip":141.62,"net_tip_adjustment":0,"source_row":47},{"branch":"downtown","business_date":"2026-02-12","total_sales":1470.73,"card_sales":1693.6,"cash_remainder":-1.65,"receipt_amount":1.65,"card_tip":222.83,"net_tip_adjustment":0,"source_row":48},{"branch":"downtown","business_date":"2026-02-13","total_sales":3452.6,"card_sales":3862.49,"cash_remainder":100,"receipt_amount":0,"card_tip":493.49,"net_tip_adjustment":0,"source_row":49},{"branch":"downtown","business_date":"2026-02-14","total_sales":3784.68,"card_sales":4141.09,"cash_remainder":141.05,"receipt_amount":0,"card_tip":448.97,"net_tip_adjustment":0,"source_row":50},{"branch":"downtown","business_date":"2026-02-15","total_sales":2979.26,"card_sales":3284.77,"cash_remainder":38.15,"receipt_amount":18.53,"card_tip":380.08,"net_tip_adjustment":-17.89,"source_row":51},{"branch":"downtown","business_date":"2026-02-16","total_sales":1477.28,"card_sales":1670.71,"cash_remainder":-52.4,"receipt_amount":52.34,"card_tip":193.41,"net_tip_adjustment":0,"source_row":52},{"branch":"downtown","business_date":"2026-02-17","total_sales":2455.39,"card_sales":2682.65,"cash_remainder":-10,"receipt_amount":9.99,"card_tip":227.2,"net_tip_adjustment":0,"source_row":53},{"branch":"downtown","business_date":"2026-02-18","total_sales":1048.08,"card_sales":1061.86,"cash_remainder":94.5,"receipt_amount":0,"card_tip":106.38,"net_tip_adjustment":0,"source_row":54},{"branch":"downtown","business_date":"2026-02-19","total_sales":1807.14,"card_sales":1956.54,"cash_remainder":123.95,"receipt_amount":7.09,"card_tip":251.07,"net_tip_adjustment":0,"source_row":55},{"branch":"downtown","business_date":"2026-02-20","total_sales":4036.52,"card_sales":4464.41,"cash_remainder":147.5,"receipt_amount":0,"card_tip":561.09,"net_tip_adjustment":0,"source_row":56},{"branch":"downtown","business_date":"2026-02-21","total_sales":4194.54,"card_sales":4695.69,"cash_remainder":63.4,"receipt_amount":6.61,"card_tip":559.57,"net_tip_adjustment":0,"source_row":57},{"branch":"downtown","business_date":"2026-02-22","total_sales":1734.22,"card_sales":1699.68,"cash_remainder":255,"receipt_amount":0,"card_tip":196.47,"net_tip_adjustment":0,"source_row":58},{"branch":"downtown","business_date":"2026-02-23","total_sales":580.5,"card_sales":658.63,"cash_remainder":0,"receipt_amount":0,"card_tip":78.09,"net_tip_adjustment":0,"source_row":59},{"branch":"downtown","business_date":"2026-02-24","total_sales":543.33,"card_sales":571.47,"cash_remainder":75,"receipt_amount":0,"card_tip":81.2,"net_tip_adjustment":0,"source_row":60},{"branch":"downtown","business_date":"2026-02-25","total_sales":1996.3,"card_sales":2126.41,"cash_remainder":123.5,"receipt_amount":0,"card_tip":238.5,"net_tip_adjustment":0,"source_row":62},{"branch":"downtown","business_date":"2026-02-26","total_sales":1874.34,"card_sales":2093.9,"cash_remainder":0,"receipt_amount":0,"card_tip":219.56,"net_tip_adjustment":0,"source_row":63},{"branch":"downtown","business_date":"2026-02-27","total_sales":5675.28,"card_sales":6310.45,"cash_remainder":93.7,"receipt_amount":11.29,"card_tip":723.7,"net_tip_adjustment":0,"source_row":64},{"branch":"downtown","business_date":"2026-02-28","total_sales":3831.33,"card_sales":4302.88,"cash_remainder":-8,"receipt_amount":7.98,"card_tip":471.54,"net_tip_adjustment":0,"source_row":65},{"branch":"downtown","business_date":"2026-03-01","total_sales":1132.21,"card_sales":1273.1,"cash_remainder":10,"receipt_amount":0,"card_tip":149.88,"net_tip_adjustment":0,"source_row":66},{"branch":"downtown","business_date":"2026-03-02","total_sales":1155.34,"card_sales":1305.43,"cash_remainder":0,"receipt_amount":0,"card_tip":150.07,"net_tip_adjustment":0,"source_row":67},{"branch":"downtown","business_date":"2026-03-03","total_sales":1444.46,"card_sales":1594.64,"cash_remainder":34.4,"receipt_amount":0,"card_tip":182.26,"net_tip_adjustment":0,"source_row":68},{"branch":"downtown","business_date":"2026-03-04","total_sales":1467.08,"card_sales":1476.11,"cash_remainder":185.9,"receipt_amount":0,"card_tip":181.72,"net_tip_adjustment":0,"source_row":69},{"branch":"downtown","business_date":"2026-03-05","total_sales":1249.24,"card_sales":1431.9,"cash_remainder":-6.4,"receipt_amount":6.16,"card_tip":182.69,"net_tip_adjustment":0,"source_row":70},{"branch":"downtown","business_date":"2026-03-06","total_sales":6643.2,"card_sales":7204.13,"cash_remainder":88.7,"receipt_amount":11.29,"card_tip":652.4,"net_tip_adjustment":0,"source_row":71},{"branch":"downtown","business_date":"2026-03-07","total_sales":4316.8,"card_sales":4730.03,"cash_remainder":135,"receipt_amount":0,"card_tip":533.99,"net_tip_adjustment":0,"source_row":72},{"branch":"downtown","business_date":"2026-03-08","total_sales":1861.36,"card_sales":2051.22,"cash_remainder":-14.2,"receipt_amount":13.99,"card_tip":189.86,"net_tip_adjustment":0,"source_row":73},{"branch":"downtown","business_date":"2026-03-09","total_sales":1222.7,"card_sales":1292.05,"cash_remainder":120,"receipt_amount":0,"card_tip":161.96,"net_tip_adjustment":0,"source_row":74},{"branch":"downtown","business_date":"2026-03-10","total_sales":1730.75,"card_sales":1982.71,"cash_remainder":0,"receipt_amount":0,"card_tip":251.98,"net_tip_adjustment":0,"source_row":75},{"branch":"downtown","business_date":"2026-03-11","total_sales":1935.93,"card_sales":2110.87,"cash_remainder":40.75,"receipt_amount":0,"card_tip":215.58,"net_tip_adjustment":0,"source_row":77},{"branch":"downtown","business_date":"2026-03-12","total_sales":1604.4,"card_sales":1691.3,"cash_remainder":90.05,"receipt_amount":6.13,"card_tip":172.71,"net_tip_adjustment":0,"source_row":78},{"branch":"downtown","business_date":"2026-03-13","total_sales":2033.05,"card_sales":2353.62,"cash_remainder":0,"receipt_amount":0,"card_tip":321.01,"net_tip_adjustment":0,"source_row":79},{"branch":"downtown","business_date":"2026-03-14","total_sales":6459.07,"card_sales":7302.43,"cash_remainder":0,"receipt_amount":0,"card_tip":843.34,"net_tip_adjustment":0,"source_row":80},{"branch":"downtown","business_date":"2026-03-15","total_sales":1989.98,"card_sales":2167.36,"cash_remainder":80,"receipt_amount":0,"card_tip":249.07,"net_tip_adjustment":0,"source_row":81},{"branch":"downtown","business_date":"2026-03-16","total_sales":1138.46,"card_sales":1311.7,"cash_remainder":0,"receipt_amount":0,"card_tip":173.24,"net_tip_adjustment":0,"source_row":82},{"branch":"downtown","business_date":"2026-03-17","total_sales":2011.61,"card_sales":2045.7,"cash_remainder":224.45,"receipt_amount":0,"card_tip":236.6,"net_tip_adjustment":0,"source_row":83},{"branch":"downtown","business_date":"2026-03-18","total_sales":771.93,"card_sales":856.89,"cash_remainder":0,"receipt_amount":0,"card_tip":84.95,"net_tip_adjustment":0,"source_row":84},{"branch":"downtown","business_date":"2026-03-19","total_sales":1185.33,"card_sales":1007.03,"cash_remainder":350,"receipt_amount":0,"card_tip":137.91,"net_tip_adjustment":0,"source_row":85},{"branch":"downtown","business_date":"2026-03-20","total_sales":7918.94,"card_sales":8710.06,"cash_remainder":150,"receipt_amount":0,"card_tip":926.51,"net_tip_adjustment":0,"source_row":86},{"branch":"downtown","business_date":"2026-03-21","total_sales":3904.19,"card_sales":4248.83,"cash_remainder":117.75,"receipt_amount":0,"card_tip":430.83,"net_tip_adjustment":0,"source_row":87},{"branch":"downtown","business_date":"2026-03-22","total_sales":3637.83,"card_sales":4176.78,"cash_remainder":20,"receipt_amount":0,"card_tip":558.22,"net_tip_adjustment":0,"source_row":88},{"branch":"downtown","business_date":"2026-03-23","total_sales":3338.31,"card_sales":3669.22,"cash_remainder":49.95,"receipt_amount":0,"card_tip":380.6,"net_tip_adjustment":0,"source_row":89},{"branch":"downtown","business_date":"2026-03-24","total_sales":2199.12,"card_sales":2275.87,"cash_remainder":213.8,"receipt_amount":6.2,"card_tip":272.15,"net_tip_adjustment":0,"source_row":90},{"branch":"downtown","business_date":"2026-03-25","total_sales":924.1,"card_sales":1073.23,"cash_remainder":0,"receipt_amount":0,"card_tip":149.12,"net_tip_adjustment":0,"source_row":92},{"branch":"downtown","business_date":"2026-03-26","total_sales":966.18,"card_sales":1107.16,"cash_remainder":0,"receipt_amount":0,"card_tip":140.98,"net_tip_adjustment":0,"source_row":93},{"branch":"downtown","business_date":"2026-03-27","total_sales":5395.09,"card_sales":6112.76,"cash_remainder":0,"receipt_amount":0,"card_tip":717.05,"net_tip_adjustment":0,"source_row":94},{"branch":"downtown","business_date":"2026-03-28","total_sales":5098.06,"card_sales":5326.84,"cash_remainder":396.2,"receipt_amount":3.79,"card_tip":610.59,"net_tip_adjustment":0,"source_row":95},{"branch":"downtown","business_date":"2026-03-29","total_sales":3390.3,"card_sales":3619.63,"cash_remainder":202.4,"receipt_amount":7.59,"card_tip":438.29,"net_tip_adjustment":0,"source_row":96},{"branch":"downtown","business_date":"2026-03-30","total_sales":1514.02,"card_sales":1734.44,"cash_remainder":10,"receipt_amount":0,"card_tip":220.33,"net_tip_adjustment":0,"source_row":97},{"branch":"downtown","business_date":"2026-03-31","total_sales":1393.21,"card_sales":1570.73,"cash_remainder":0,"receipt_amount":0,"card_tip":177.53,"net_tip_adjustment":0,"source_row":98},{"branch":"downtown","business_date":"2026-04-01","total_sales":1337.68,"card_sales":1406.94,"cash_remainder":103,"receipt_amount":0,"card_tip":165.77,"net_tip_adjustment":0,"source_row":99},{"branch":"downtown","business_date":"2026-04-02","total_sales":5549.48,"card_sales":6121.37,"cash_remainder":60,"receipt_amount":0,"card_tip":625.23,"net_tip_adjustment":0,"source_row":100},{"branch":"downtown","business_date":"2026-04-03","total_sales":4419.45,"card_sales":4996.02,"cash_remainder":6,"receipt_amount":4.01,"card_tip":584.73,"net_tip_adjustment":0,"source_row":101},{"branch":"downtown","business_date":"2026-04-04","total_sales":4348.69,"card_sales":4859.83,"cash_remainder":42,"receipt_amount":0,"card_tip":497.8,"net_tip_adjustment":0,"source_row":102},{"branch":"downtown","business_date":"2026-04-05","total_sales":1914.43,"card_sales":2203.79,"cash_remainder":0,"receipt_amount":0,"card_tip":289.36,"net_tip_adjustment":0,"source_row":103},{"branch":"downtown","business_date":"2026-04-06","total_sales":1527.16,"card_sales":1742.23,"cash_remainder":-23.96,"receipt_amount":23.96,"card_tip":215.04,"net_tip_adjustment":0,"source_row":104},{"branch":"downtown","business_date":"2026-04-07","total_sales":1229.46,"card_sales":1118.37,"cash_remainder":245.9,"receipt_amount":4.1,"card_tip":117.08,"net_tip_adjustment":0,"source_row":105},{"branch":"downtown","business_date":"2026-04-08","total_sales":1696.01,"card_sales":1913.2,"cash_remainder":0,"receipt_amount":0,"card_tip":217.2,"net_tip_adjustment":0,"source_row":107},{"branch":"downtown","business_date":"2026-04-09","total_sales":2174.63,"card_sales":2453.38,"cash_remainder":0,"receipt_amount":0,"card_tip":278.73,"net_tip_adjustment":0,"source_row":108},{"branch":"downtown","business_date":"2026-04-10","total_sales":4389.33,"card_sales":4975.7,"cash_remainder":-4.95,"receipt_amount":4.99,"card_tip":586.34,"net_tip_adjustment":0,"source_row":109},{"branch":"downtown","business_date":"2026-04-11","total_sales":3804.81,"card_sales":4371.49,"cash_remainder":0,"receipt_amount":0,"card_tip":566.68,"net_tip_adjustment":0,"source_row":110},{"branch":"downtown","business_date":"2026-04-12","total_sales":1856.86,"card_sales":2106.48,"cash_remainder":-16.95,"receipt_amount":11.98,"card_tip":249.6,"net_tip_adjustment":0,"source_row":111},{"branch":"downtown","business_date":"2026-04-13","total_sales":1562.61,"card_sales":1773.69,"cash_remainder":0,"receipt_amount":0,"card_tip":211.07,"net_tip_adjustment":0,"source_row":112},{"branch":"downtown","business_date":"2026-04-14","total_sales":1651.78,"card_sales":1868.58,"cash_remainder":21,"receipt_amount":4.04,"card_tip":239.95,"net_tip_adjustment":0,"source_row":113},{"branch":"downtown","business_date":"2026-04-15","total_sales":2358.92,"card_sales":2549.74,"cash_remainder":82.85,"receipt_amount":8.01,"card_tip":266.49,"net_tip_adjustment":0,"source_row":114},{"branch":"downtown","business_date":"2026-04-16","total_sales":1312.19,"card_sales":1479.54,"cash_remainder":15.7,"receipt_amount":7.99,"card_tip":191.05,"net_tip_adjustment":0,"source_row":115},{"branch":"downtown","business_date":"2026-04-17","total_sales":5941.81,"card_sales":6594.31,"cash_remainder":143.95,"receipt_amount":4.07,"card_tip":734.65,"net_tip_adjustment":0,"source_row":116},{"branch":"downtown","business_date":"2026-04-18","total_sales":3322.79,"card_sales":3784.99,"cash_remainder":10,"receipt_amount":0,"card_tip":462.17,"net_tip_adjustment":0,"source_row":117},{"branch":"downtown","business_date":"2026-04-19","total_sales":2964.29,"card_sales":3340.33,"cash_remainder":0,"receipt_amount":0,"card_tip":376.19,"net_tip_adjustment":0,"source_row":118},{"branch":"downtown","business_date":"2026-04-20","total_sales":1957.04,"card_sales":2069.09,"cash_remainder":137,"receipt_amount":0,"card_tip":237.02,"net_tip_adjustment":0,"source_row":119},{"branch":"downtown","business_date":"2026-04-21","total_sales":1328.33,"card_sales":1453.03,"cash_remainder":58.5,"receipt_amount":0,"card_tip":174.4,"net_tip_adjustment":0,"source_row":120},{"branch":"downtown","business_date":"2026-04-22","total_sales":1306.24,"card_sales":1459.27,"cash_remainder":42,"receipt_amount":0,"card_tip":188.04,"net_tip_adjustment":0,"source_row":122},{"branch":"downtown","business_date":"2026-04-23","total_sales":2208.92,"card_sales":2410.95,"cash_remainder":73.9,"receipt_amount":0,"card_tip":235.9,"net_tip_adjustment":0,"source_row":123},{"branch":"downtown","business_date":"2026-04-24","total_sales":5314.3,"card_sales":5511.17,"cash_remainder":470,"receipt_amount":0,"card_tip":600.57,"net_tip_adjustment":0,"source_row":124},{"branch":"downtown","business_date":"2026-04-25","total_sales":4995.34,"card_sales":5304.04,"cash_remainder":336,"receipt_amount":0,"card_tip":602.2,"net_tip_adjustment":0,"source_row":125},{"branch":"downtown","business_date":"2026-04-26","total_sales":3066.99,"card_sales":3370.45,"cash_remainder":117.65,"receipt_amount":7.35,"card_tip":415.41,"net_tip_adjustment":0,"source_row":126},{"branch":"downtown","business_date":"2026-04-27","total_sales":1379.1,"card_sales":1172.36,"cash_remainder":340.95,"receipt_amount":9.03,"card_tip":137.18,"net_tip_adjustment":0,"source_row":127},{"branch":"downtown","business_date":"2026-04-28","total_sales":948.04,"card_sales":1048.68,"cash_remainder":39.5,"receipt_amount":0,"card_tip":133.38,"net_tip_adjustment":0,"source_row":128},{"branch":"downtown","business_date":"2026-04-29","total_sales":684.45,"card_sales":779.63,"cash_remainder":-3,"receipt_amount":3.56,"card_tip":95.18,"net_tip_adjustment":0,"source_row":129},{"branch":"downtown","business_date":"2026-04-30","total_sales":1665.49,"card_sales":1900.36,"cash_remainder":-20,"receipt_amount":19.98,"card_tip":234.91,"net_tip_adjustment":0,"source_row":130},{"branch":"downtown","business_date":"2026-05-01","total_sales":4037.35,"card_sales":4497.1,"cash_remainder":0,"receipt_amount":0,"card_tip":459.37,"net_tip_adjustment":0,"source_row":131},{"branch":"downtown","business_date":"2026-05-02","total_sales":2308.58,"card_sales":2623.12,"cash_remainder":0,"receipt_amount":0,"card_tip":314.25,"net_tip_adjustment":0,"source_row":132},{"branch":"downtown","business_date":"2026-05-03","total_sales":2582.02,"card_sales":2942.12,"cash_remainder":0,"receipt_amount":0,"card_tip":332.98,"net_tip_adjustment":0,"source_row":133},{"branch":"downtown","business_date":"2026-05-04","total_sales":992.35,"card_sales":1068.29,"cash_remainder":41,"receipt_amount":8.99,"card_tip":121.13,"net_tip_adjustment":0,"source_row":134},{"branch":"downtown","business_date":"2026-05-05","total_sales":986.12,"card_sales":1135.88,"cash_remainder":0,"receipt_amount":0,"card_tip":127.18,"net_tip_adjustment":0,"source_row":135},{"branch":"downtown","business_date":"2026-05-06","total_sales":1343.78,"card_sales":1530.67,"cash_remainder":23.4,"receipt_amount":4.51,"card_tip":209.51,"net_tip_adjustment":0,"source_row":137},{"branch":"downtown","business_date":"2026-05-07","total_sales":1989.5,"card_sales":2197.76,"cash_remainder":60.1,"receipt_amount":0,"card_tip":259.13,"net_tip_adjustment":0,"source_row":138},{"branch":"downtown","business_date":"2026-05-08","total_sales":4257.52,"card_sales":4801.64,"cash_remainder":91.15,"receipt_amount":6.64,"card_tip":599.46,"net_tip_adjustment":0,"source_row":139},{"branch":"downtown","business_date":"2026-05-09","total_sales":2251.13,"card_sales":2552.27,"cash_remainder":10.75,"receipt_amount":0,"card_tip":311.85,"net_tip_adjustment":0,"source_row":140},{"branch":"downtown","business_date":"2026-05-10","total_sales":1915.66,"card_sales":2138.19,"cash_remainder":26.75,"receipt_amount":0,"card_tip":246.83,"net_tip_adjustment":0,"source_row":141},{"branch":"downtown","business_date":"2026-05-11","total_sales":1902.68,"card_sales":2203.13,"cash_remainder":10,"receipt_amount":0,"card_tip":300.48,"net_tip_adjustment":0,"source_row":142},{"branch":"downtown","business_date":"2026-05-12","total_sales":1359.88,"card_sales":1476.92,"cash_remainder":79,"receipt_amount":5.99,"card_tip":198.35,"net_tip_adjustment":0,"source_row":143},{"branch":"downtown","business_date":"2026-05-13","total_sales":1073.18,"card_sales":1231.91,"cash_remainder":-11.6,"receipt_amount":11.58,"card_tip":158.74,"net_tip_adjustment":0,"source_row":144},{"branch":"downtown","business_date":"2026-05-14","total_sales":1491.32,"card_sales":1573.1,"cash_remainder":161.95,"receipt_amount":0,"card_tip":205.67,"net_tip_adjustment":0,"source_row":145},{"branch":"downtown","business_date":"2026-05-15","total_sales":3193.65,"card_sales":3680.36,"cash_remainder":0,"receipt_amount":0,"card_tip":486.63,"net_tip_adjustment":0,"source_row":146},{"branch":"downtown","business_date":"2026-05-16","total_sales":3249.48,"card_sales":3213.37,"cash_remainder":520,"receipt_amount":0,"card_tip":414.5,"net_tip_adjustment":0,"source_row":147},{"branch":"downtown","business_date":"2026-05-17","total_sales":3400.27,"card_sales":3833.78,"cash_remainder":67,"receipt_amount":0,"card_tip":491.37,"net_tip_adjustment":0,"source_row":148},{"branch":"downtown","business_date":"2026-05-18","total_sales":1870.12,"card_sales":1962.56,"cash_remainder":160,"receipt_amount":0,"card_tip":229.15,"net_tip_adjustment":0,"source_row":149},{"branch":"downtown","business_date":"2026-05-19","total_sales":880.93,"card_sales":1002.72,"cash_remainder":-7.6,"receipt_amount":7.59,"card_tip":121.77,"net_tip_adjustment":0,"source_row":150},{"branch":"downtown","business_date":"2026-05-20","total_sales":618.42,"card_sales":701.11,"cash_remainder":-3.1,"receipt_amount":2.75,"card_tip":82.7,"net_tip_adjustment":0,"source_row":152},{"branch":"downtown","business_date":"2026-05-21","total_sales":2169.8,"card_sales":2382.35,"cash_remainder":56.4,"receipt_amount":71.9,"card_tip":316.52,"net_tip_adjustment":0,"source_row":153},{"branch":"downtown","business_date":"2026-05-22","total_sales":7447.64,"card_sales":7752.11,"cash_remainder":772.6,"receipt_amount":0,"card_tip":1004.77,"net_tip_adjustment":0,"source_row":154},{"branch":"downtown","business_date":"2026-05-23","total_sales":2270.88,"card_sales":2527.15,"cash_remainder":0,"receipt_amount":0,"card_tip":256.31,"net_tip_adjustment":0,"source_row":155},{"branch":"downtown","business_date":"2026-05-24","total_sales":1203.49,"card_sales":1288.34,"cash_remainder":67,"receipt_amount":7.98,"card_tip":151.47,"net_tip_adjustment":0,"source_row":156},{"branch":"downtown","business_date":"2026-05-25","total_sales":2352.64,"card_sales":2562.49,"cash_remainder":128.7,"receipt_amount":1.29,"card_tip":321.67,"net_tip_adjustment":0,"source_row":157},{"branch":"downtown","business_date":"2026-05-26","total_sales":1213.19,"card_sales":1152.03,"cash_remainder":200.35,"receipt_amount":0,"card_tip":125.32,"net_tip_adjustment":0,"source_row":158},{"branch":"downtown","business_date":"2026-05-27","total_sales":1848.91,"card_sales":2134.45,"cash_remainder":0,"receipt_amount":0,"card_tip":285.53,"net_tip_adjustment":0,"source_row":159},{"branch":"downtown","business_date":"2026-05-28","total_sales":871.91,"card_sales":965.73,"cash_remainder":40,"receipt_amount":0,"card_tip":133.8,"net_tip_adjustment":0,"source_row":160},{"branch":"downtown","business_date":"2026-05-29","total_sales":2952.51,"card_sales":3322.19,"cash_remainder":35,"receipt_amount":0,"card_tip":391.06,"net_tip_adjustment":0,"source_row":161},{"branch":"downtown","business_date":"2026-05-30","total_sales":3976.33,"card_sales":4354.01,"cash_remainder":187.15,"receipt_amount":0,"card_tip":528.97,"net_tip_adjustment":0,"source_row":162},{"branch":"downtown","business_date":"2026-05-31","total_sales":2417.73,"card_sales":2748.1,"cash_remainder":34.7,"receipt_amount":0,"card_tip":360.88,"net_tip_adjustment":0,"source_row":163},{"branch":"downtown","business_date":"2026-06-01","total_sales":810.99,"card_sales":936.38,"cash_remainder":0,"receipt_amount":0,"card_tip":125.4,"net_tip_adjustment":0,"source_row":164},{"branch":"downtown","business_date":"2026-06-02","total_sales":2401.98,"card_sales":2056.75,"cash_remainder":600,"receipt_amount":0,"card_tip":222.94,"net_tip_adjustment":0,"source_row":165},{"branch":"downtown","business_date":"2026-06-03","total_sales":1441.29,"card_sales":1285.35,"cash_remainder":332,"receipt_amount":0,"card_tip":142.81,"net_tip_adjustment":0,"source_row":167},{"branch":"downtown","business_date":"2026-06-04","total_sales":1286.51,"card_sales":1358,"cash_remainder":80,"receipt_amount":0,"card_tip":135.89,"net_tip_adjustment":0,"source_row":168},{"branch":"downtown","business_date":"2026-06-05","total_sales":4094.92,"card_sales":4435.75,"cash_remainder":290.7,"receipt_amount":0,"card_tip":606.3,"net_tip_adjustment":0,"source_row":169},{"branch":"downtown","business_date":"2026-06-06","total_sales":6680.94,"card_sales":7298.89,"cash_remainder":65.65,"receipt_amount":3.81,"card_tip":685.41,"net_tip_adjustment":0,"source_row":170},{"branch":"downtown","business_date":"2026-06-07","total_sales":1911.72,"card_sales":2155.46,"cash_remainder":25,"receipt_amount":0,"card_tip":268.74,"net_tip_adjustment":0,"source_row":171},{"branch":"downtown","business_date":"2026-06-08","total_sales":1200.12,"card_sales":1227.52,"cash_remainder":162.95,"receipt_amount":0,"card_tip":160.35,"net_tip_adjustment":0,"source_row":172},{"branch":"downtown","business_date":"2026-06-09","total_sales":1754.3,"card_sales":2008.49,"cash_remainder":-7.6,"receipt_amount":7.59,"card_tip":254.17,"net_tip_adjustment":0,"source_row":173},{"branch":"downtown","business_date":"2026-06-10","total_sales":914.9,"card_sales":991.69,"cash_remainder":45,"receipt_amount":5,"card_tip":116.28,"net_tip_adjustment":0,"source_row":174},{"branch":"downtown","business_date":"2026-06-11","total_sales":4353.28,"card_sales":4792.79,"cash_remainder":140,"receipt_amount":0,"card_tip":535.43,"net_tip_adjustment":0,"source_row":175},{"branch":"downtown","business_date":"2026-06-12","total_sales":3422.89,"card_sales":3907.55,"cash_remainder":25,"receipt_amount":0,"card_tip":508.35,"net_tip_adjustment":0,"source_row":176},{"branch":"downtown","business_date":"2026-06-13","total_sales":3411.6,"card_sales":3589.88,"cash_remainder":357.9,"receipt_amount":0,"card_tip":486.56,"net_tip_adjustment":0,"source_row":177},{"branch":"downtown","business_date":"2026-06-14","total_sales":1380.2,"card_sales":1501.93,"cash_remainder":20,"receipt_amount":0,"card_tip":136.11,"net_tip_adjustment":0,"source_row":178},{"branch":"downtown","business_date":"2026-06-15","total_sales":1752.38,"card_sales":1812.25,"cash_remainder":200,"receipt_amount":0,"card_tip":228.13,"net_tip_adjustment":0,"source_row":179},{"branch":"downtown","business_date":"2026-06-16","total_sales":1045.96,"card_sales":1198.53,"cash_remainder":-10,"receipt_amount":10,"card_tip":152.57,"net_tip_adjustment":0,"source_row":180},{"branch":"downtown","business_date":"2026-06-17","total_sales":2055.47,"card_sales":2057.36,"cash_remainder":210,"receipt_amount":0,"card_tip":183.22,"net_tip_adjustment":0,"source_row":182},{"branch":"downtown","business_date":"2026-06-18","total_sales":5365.14,"card_sales":6039.16,"cash_remainder":13.8,"receipt_amount":11.18,"card_tip":697.76,"net_tip_adjustment":0,"source_row":183},{"branch":"downtown","business_date":"2026-06-19","total_sales":4812.23,"card_sales":5158.65,"cash_remainder":262.75,"receipt_amount":2.25,"card_tip":591.47,"net_tip_adjustment":0,"source_row":184},{"branch":"downtown","business_date":"2026-06-20","total_sales":3886.67,"card_sales":4283.44,"cash_remainder":144,"receipt_amount":5.98,"card_tip":525.52,"net_tip_adjustment":0,"source_row":185},{"branch":"downtown","business_date":"2026-06-21","total_sales":497.51,"card_sales":538.14,"cash_remainder":56.75,"receipt_amount":0,"card_tip":82.43,"net_tip_adjustment":0,"source_row":186},{"branch":"downtown","business_date":"2026-06-22","total_sales":1752.41,"card_sales":1867.4,"cash_remainder":114.75,"receipt_amount":5.24,"card_tip":218.88,"net_tip_adjustment":0,"source_row":187},{"branch":"downtown","business_date":"2026-06-23","total_sales":991.93,"card_sales":1002.25,"cash_remainder":102.2,"receipt_amount":1.82,"card_tip":101.82,"net_tip_adjustment":0,"source_row":188},{"branch":"downtown","business_date":"2026-06-24","total_sales":4612.79,"card_sales":4724.22,"cash_remainder":484,"receipt_amount":0,"card_tip":559.4,"net_tip_adjustment":0,"source_row":189},{"branch":"downtown","business_date":"2026-06-25","total_sales":2536.21,"card_sales":1931.19,"cash_remainder":950,"receipt_amount":0,"card_tip":253.93,"net_tip_adjustment":0,"source_row":190},{"branch":"downtown","business_date":"2026-06-26","total_sales":5302.24,"card_sales":5602.77,"cash_remainder":406,"receipt_amount":6.99,"card_tip":668.34,"net_tip_adjustment":0,"source_row":191},{"branch":"downtown","business_date":"2026-06-27","total_sales":4918.49,"card_sales":5562.82,"cash_remainder":24.5,"receipt_amount":0,"card_tip":665.31,"net_tip_adjustment":0,"source_row":192},{"branch":"downtown","business_date":"2026-06-28","total_sales":2628.29,"card_sales":3049.68,"cash_remainder":10,"receipt_amount":0,"card_tip":421.38,"net_tip_adjustment":0,"source_row":193},{"branch":"downtown","business_date":"2026-06-29","total_sales":1614.48,"card_sales":1630.72,"cash_remainder":169.65,"receipt_amount":45.36,"card_tip":199.12,"net_tip_adjustment":0,"source_row":194},{"branch":"downtown","business_date":"2026-06-30","total_sales":2591.68,"card_sales":2966.97,"cash_remainder":5,"receipt_amount":0,"card_tip":375.29,"net_tip_adjustment":0,"source_row":195},{"branch":"downtown","business_date":"2026-07-01","total_sales":3791.81,"card_sales":3907.66,"cash_remainder":280,"receipt_amount":0,"card_tip":409.31,"net_tip_adjustment":0,"source_row":197},{"branch":"downtown","business_date":"2026-07-02","total_sales":1781.73,"card_sales":2034.42,"cash_remainder":-27.95,"receipt_amount":27.91,"card_tip":279.8,"net_tip_adjustment":0,"source_row":198},{"branch":"downtown","business_date":"2026-07-03","total_sales":3046.8,"card_sales":3333.56,"cash_remainder":119.4,"receipt_amount":4.59,"card_tip":392.92,"net_tip_adjustment":0,"source_row":199},{"branch":"downtown","business_date":"2026-07-04","total_sales":3490.99,"card_sales":3988.08,"cash_remainder":0,"receipt_amount":0,"card_tip":497.08,"net_tip_adjustment":0,"source_row":200},{"branch":"downtown","business_date":"2026-07-05","total_sales":2355.66,"card_sales":2593.52,"cash_remainder":143.9,"receipt_amount":0,"card_tip":359.83,"net_tip_adjustment":0,"source_row":201},{"branch":"downtown","business_date":"2026-07-06","total_sales":1267.26,"card_sales":1291.08,"cash_remainder":145,"receipt_amount":0,"card_tip":152.55,"net_tip_adjustment":0,"source_row":202},{"branch":"downtown","business_date":"2026-07-07","total_sales":1692.46,"card_sales":1776.01,"cash_remainder":170,"receipt_amount":0,"card_tip":225.85,"net_tip_adjustment":0,"source_row":203},{"branch":"downtown","business_date":"2026-07-08","total_sales":1403.4,"card_sales":1519,"cash_remainder":89,"receipt_amount":0,"card_tip":194.69,"net_tip_adjustment":0,"source_row":204},{"branch":"downtown","business_date":"2026-07-09","total_sales":1799.8,"card_sales":2032.1,"cash_remainder":0,"receipt_amount":0,"card_tip":239.06,"net_tip_adjustment":0,"source_row":205},{"branch":"downtown","business_date":"2026-07-10","total_sales":4950.08,"card_sales":5654,"cash_remainder":0,"receipt_amount":0,"card_tip":703.89,"net_tip_adjustment":0,"source_row":206},{"branch":"downtown","business_date":"2026-07-11","total_sales":2846.04,"card_sales":3066.27,"cash_remainder":200,"receipt_amount":0,"card_tip":368.42,"net_tip_adjustment":0,"source_row":207},{"branch":"downtown","business_date":"2026-07-12","total_sales":2806.46,"card_sales":3007.27,"cash_remainder":205,"receipt_amount":0,"card_tip":389.42,"net_tip_adjustment":0,"source_row":208},{"branch":"downtown","business_date":"2026-07-13","total_sales":1896.33,"card_sales":1987.91,"cash_remainder":185,"receipt_amount":0,"card_tip":243.45,"net_tip_adjustment":0,"source_row":209},{"branch":"downtown","business_date":"2026-07-14","total_sales":1687.77,"card_sales":1498.28,"cash_remainder":385,"receipt_amount":0,"card_tip":137.17,"net_tip_adjustment":0,"source_row":210},{"branch":"downtown","business_date":"2026-07-15","total_sales":1366.22,"card_sales":1363.8,"cash_remainder":197,"receipt_amount":0,"card_tip":169.31,"net_tip_adjustment":0,"source_row":212},{"branch":"downtown","business_date":"2026-07-16","total_sales":2249.23,"card_sales":2558.8,"cash_remainder":-1.55,"receipt_amount":1.54,"card_tip":310.55,"net_tip_adjustment":0,"source_row":213},{"branch":"downtown","business_date":"2026-07-17","total_sales":3653.89,"card_sales":4195.37,"cash_remainder":-2.15,"receipt_amount":2.17,"card_tip":541.49,"net_tip_adjustment":0,"source_row":214},{"branch":"downtown","business_date":"2026-07-18","total_sales":3989.35,"card_sales":4225.26,"cash_remainder":346.95,"receipt_amount":3.23,"card_tip":539.56,"net_tip_adjustment":0,"source_row":215},{"branch":"downtown","business_date":"2026-07-19","total_sales":1768.2,"card_sales":1950.58,"cash_remainder":20,"receipt_amount":0,"card_tip":200.02,"net_tip_adjustment":0,"source_row":216},{"branch":"downtown","business_date":"2026-07-20","total_sales":1838.27,"card_sales":1748.53,"cash_remainder":382,"receipt_amount":0,"card_tip":246.8,"net_tip_adjustment":0,"source_row":217},{"branch":"downtown","business_date":"2026-07-21","total_sales":1451.46,"card_sales":1543.11,"cash_remainder":128.65,"receipt_amount":1.37,"card_tip":207.99,"net_tip_adjustment":0,"source_row":218},{"branch":"downtown","business_date":"2026-07-22","total_sales":3034.57,"card_sales":3042.11,"cash_remainder":425.8,"receipt_amount":0,"card_tip":367.07,"net_tip_adjustment":0,"source_row":219},{"branch":"downtown","business_date":"2026-07-23","total_sales":1925.74,"card_sales":2136.92,"cash_remainder":20,"receipt_amount":0,"card_tip":229.19,"net_tip_adjustment":0,"source_row":220},{"branch":"downtown","business_date":"2026-07-24","total_sales":5217.61,"card_sales":5834.93,"cash_remainder":100,"receipt_amount":0,"card_tip":705.37,"net_tip_adjustment":0,"source_row":221},{"branch":"downtown","business_date":"2026-07-25","total_sales":3745.37,"card_sales":4218.73,"cash_remainder":0,"receipt_amount":0,"card_tip":473.64,"net_tip_adjustment":0,"source_row":222},{"branch":"downtown","business_date":"2026-07-26","total_sales":1675.64,"card_sales":1727.44,"cash_remainder":165,"receipt_amount":0,"card_tip":191.87,"net_tip_adjustment":0,"source_row":223},{"branch":"downtown","business_date":"2026-07-27","total_sales":831.84,"card_sales":955.09,"cash_remainder":0,"receipt_amount":0,"card_tip":123.24,"net_tip_adjustment":0,"source_row":224},{"branch":"downtown","business_date":"2026-07-28","total_sales":1234.88,"card_sales":1427.8,"cash_remainder":0,"receipt_amount":0,"card_tip":192.91,"net_tip_adjustment":0,"source_row":225},{"branch":"downtown","business_date":"2026-07-29","total_sales":1080.36,"card_sales":1162.93,"cash_remainder":80,"receipt_amount":0,"card_tip":148.1,"net_tip_adjustment":0,"source_row":227}]$daily$::jsonb
) as x(
  branch text,
  business_date date,
  total_sales numeric,
  card_sales numeric,
  cash_remainder numeric,
  receipt_amount numeric,
  card_tip numeric,
  net_tip_adjustment numeric,
  source_row integer
)
on conflict (branch, business_date)
do update set
  total_sales = excluded.total_sales,
  card_sales = excluded.card_sales,
  cash_remainder = excluded.cash_remainder,
  receipt_amount = excluded.receipt_amount,
  card_tip = excluded.card_tip,
  card_tip_fee_rate = excluded.card_tip_fee_rate,
  kitchen_share_rate = excluded.kitchen_share_rate,
  hall_share_rate = excluded.hall_share_rate,
  net_tip_adjustment = excluded.net_tip_adjustment,
  source = excluded.source,
  source_row = excluded.source_row;

insert into settlement.daily_staff_entries (
  daily_entry_id,
  staff_id,
  hours,
  tip_eligible,
  tip_adjustment,
  tip_override
)
select
  d.id,
  sm.id,
  x.hours,
  x.tip_eligible,
  0,
  x.tip_override
from jsonb_to_recordset(
  $entries$[{"branch":"downtown","business_date":"2025-12-31","department":"kitchen","staff_key":"신성경","hours":9.5,"tip_eligible":true,"tip_override":139.7106},{"branch":"downtown","business_date":"2026-01-02","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":75.131},{"branch":"downtown","business_date":"2026-01-03","department":"kitchen","staff_key":"신성경","hours":6.5,"tip_eligible":true,"tip_override":70.0296},{"branch":"downtown","business_date":"2026-01-04","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":57.0474},{"branch":"downtown","business_date":"2026-01-05","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":71.7027},{"branch":"downtown","business_date":"2026-01-09","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":139.6353},{"branch":"downtown","business_date":"2026-01-10","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":72.364},{"branch":"downtown","business_date":"2026-01-11","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":32.2125},{"branch":"downtown","business_date":"2026-01-12","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":90.5223},{"branch":"downtown","business_date":"2026-01-16","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":93.7355},{"branch":"downtown","business_date":"2026-01-17","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":78.0392},{"branch":"downtown","business_date":"2026-01-18","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":42.9082},{"branch":"downtown","business_date":"2026-01-19","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":48.6262},{"branch":"downtown","business_date":"2026-01-22","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":43.8742},{"branch":"downtown","business_date":"2026-01-23","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":153.1505},{"branch":"downtown","business_date":"2026-01-24","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":73.3631},{"branch":"downtown","business_date":"2026-01-25","department":"kitchen","staff_key":"신성경","hours":9.5,"tip_eligible":true,"tip_override":48.79},{"branch":"downtown","business_date":"2026-01-26","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":40.1872},{"branch":"downtown","business_date":"2026-01-27","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":54.9948},{"branch":"downtown","business_date":"2026-01-28","department":"kitchen","staff_key":"신성경","hours":3.5,"tip_eligible":true,"tip_override":16.0772},{"branch":"downtown","business_date":"2026-01-30","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":88.9421},{"branch":"downtown","business_date":"2026-01-31","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":55.9659},{"branch":"downtown","business_date":"2026-02-01","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":50.6432},{"branch":"downtown","business_date":"2026-02-02","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":89.6242},{"branch":"downtown","business_date":"2026-02-03","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":21.489},{"branch":"downtown","business_date":"2026-02-04","department":"kitchen","staff_key":"신성경","hours":3,"tip_eligible":true,"tip_override":16.7723},{"branch":"downtown","business_date":"2026-02-06","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":81.7923},{"branch":"downtown","business_date":"2026-02-07","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":59.0518},{"branch":"downtown","business_date":"2026-02-08","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":29.2114},{"branch":"downtown","business_date":"2026-02-09","department":"kitchen","staff_key":"신성경","hours":3,"tip_eligible":true,"tip_override":21.9702},{"branch":"downtown","business_date":"2026-02-10","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":28.2902},{"branch":"downtown","business_date":"2026-02-11","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":39.6507},{"branch":"downtown","business_date":"2026-02-13","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":68.1846},{"branch":"downtown","business_date":"2026-02-14","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":97.6961},{"branch":"downtown","business_date":"2026-02-15","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":67.3397},{"branch":"downtown","business_date":"2026-02-16","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":53.6922},{"branch":"downtown","business_date":"2026-02-17","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":44.5412},{"branch":"downtown","business_date":"2026-02-19","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":55.0837},{"branch":"downtown","business_date":"2026-02-20","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":112.8336},{"branch":"downtown","business_date":"2026-02-21","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":111.9937},{"branch":"downtown","business_date":"2026-02-22","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":61.8659},{"branch":"downtown","business_date":"2026-02-23","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":18.3764},{"branch":"downtown","business_date":"2026-02-27","department":"kitchen","staff_key":"신성경","hours":7,"tip_eligible":true,"tip_override":140.1325},{"branch":"downtown","business_date":"2026-02-28","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":92.4198},{"branch":"downtown","business_date":"2026-03-01","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":29.5785},{"branch":"downtown","business_date":"2026-03-02","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":32.6864},{"branch":"downtown","business_date":"2026-03-03","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":43.4244},{"branch":"downtown","business_date":"2026-03-06","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":129.5744},{"branch":"downtown","business_date":"2026-03-07","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":107.51},{"branch":"downtown","business_date":"2026-03-08","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":37.1706},{"branch":"downtown","business_date":"2026-03-09","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":51.285},{"branch":"downtown","business_date":"2026-03-10","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":98.7682},{"branch":"downtown","business_date":"2026-03-13","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":62.83},{"branch":"downtown","business_date":"2026-03-14","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":165.2986},{"branch":"downtown","business_date":"2026-03-15","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":50.4797},{"branch":"downtown","business_date":"2026-03-16","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":67.9101},{"branch":"downtown","business_date":"2026-03-17","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":75.1656},{"branch":"downtown","business_date":"2026-03-20","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":184.518},{"branch":"downtown","business_date":"2026-03-21","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":90.7547},{"branch":"downtown","business_date":"2026-03-22","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":109.5571},{"branch":"downtown","business_date":"2026-03-23","department":"kitchen","staff_key":"신성경","hours":9.5,"tip_eligible":true,"tip_override":149.2992},{"branch":"downtown","business_date":"2026-03-24","department":"kitchen","staff_key":"신성경","hours":9.5,"tip_eligible":true,"tip_override":81.0204},{"branch":"downtown","business_date":"2026-03-27","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":140.6658},{"branch":"downtown","business_date":"2026-03-28","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":123.3116},{"branch":"downtown","business_date":"2026-03-29","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":86.1108},{"branch":"downtown","business_date":"2026-03-30","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":90.4054},{"branch":"downtown","business_date":"2026-03-31","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":69.5878},{"branch":"downtown","business_date":"2026-04-03","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":114.9771},{"branch":"downtown","business_date":"2026-04-04","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":108.6368},{"branch":"downtown","business_date":"2026-04-05","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":69.8025},{"branch":"downtown","business_date":"2026-04-06","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":84.3077},{"branch":"downtown","business_date":"2026-04-07","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":54.6274},{"branch":"downtown","business_date":"2026-04-10","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":114.9366},{"branch":"downtown","business_date":"2026-04-11","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":111.0693},{"branch":"downtown","business_date":"2026-04-12","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":47.93},{"branch":"downtown","business_date":"2026-04-13","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":82.7434},{"branch":"downtown","business_date":"2026-04-14","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":94.8164},{"branch":"downtown","business_date":"2026-04-17","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":157.1654},{"branch":"downtown","business_date":"2026-04-18","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":92.5913},{"branch":"downtown","business_date":"2026-04-19","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":73.7032},{"branch":"downtown","business_date":"2026-04-22","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":38.2538},{"branch":"downtown","business_date":"2026-04-23","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":54.2424},{"branch":"downtown","business_date":"2026-04-24","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":130.9717},{"branch":"downtown","business_date":"2026-04-25","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":126.5312},{"branch":"downtown","business_date":"2026-04-26","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":84.0304},{"branch":"downtown","business_date":"2026-04-29","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":18.7673},{"branch":"downtown","business_date":"2026-04-30","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":46.0304},{"branch":"downtown","business_date":"2026-05-01","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":90.1125},{"branch":"downtown","business_date":"2026-05-02","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":61.651},{"branch":"downtown","business_date":"2026-05-03","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":70.6881},{"branch":"downtown","business_date":"2026-05-06","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":74.8835},{"branch":"downtown","business_date":"2026-05-07","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":71.4348},{"branch":"downtown","business_date":"2026-05-08","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":125.9842},{"branch":"downtown","business_date":"2026-05-09","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":61.1306},{"branch":"downtown","business_date":"2026-05-10","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":48.8687},{"branch":"downtown","business_date":"2026-05-13","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":31.107},{"branch":"downtown","business_date":"2026-05-14","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":47.9233},{"branch":"downtown","business_date":"2026-05-15","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":95.3955},{"branch":"downtown","business_date":"2026-05-16","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":95.12},{"branch":"downtown","business_date":"2026-05-17","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":98.1365},{"branch":"downtown","business_date":"2026-05-20","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":32.2744},{"branch":"downtown","business_date":"2026-05-21","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":66.9039},{"branch":"downtown","business_date":"2026-05-22","department":"kitchen","staff_key":"신성경","hours":9,"tip_eligible":true,"tip_override":171.7587},{"branch":"downtown","business_date":"2026-05-23","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":50.2288},{"branch":"downtown","business_date":"2026-05-24","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":31.3601},{"branch":"downtown","business_date":"2026-05-27","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":79.6441},{"branch":"downtown","business_date":"2026-05-28","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":37.3266},{"branch":"downtown","business_date":"2026-05-29","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":79.3718},{"branch":"downtown","business_date":"2026-05-30","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":110.8501},{"branch":"downtown","business_date":"2026-06-10","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":24.8929},{"branch":"downtown","business_date":"2026-06-11","department":"kitchen","staff_key":"신성경","hours":9,"tip_eligible":true,"tip_override":113.7603},{"branch":"downtown","business_date":"2026-06-12","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":99.8986},{"branch":"downtown","business_date":"2026-06-13","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":105.2898},{"branch":"downtown","business_date":"2026-06-14","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":27.8016},{"branch":"downtown","business_date":"2026-06-17","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":83.2902},{"branch":"downtown","business_date":"2026-06-18","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":137.009},{"branch":"downtown","business_date":"2026-06-19","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":116.2842},{"branch":"downtown","business_date":"2026-06-20","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":107.2479},{"branch":"downtown","business_date":"2026-06-21","department":"kitchen","staff_key":"신성경","hours":7.5,"tip_eligible":true,"tip_override":19.1463},{"branch":"downtown","business_date":"2026-06-24","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":116.8484},{"branch":"downtown","business_date":"2026-06-25","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":67.9803},{"branch":"downtown","business_date":"2026-06-27","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":131.1048},{"branch":"downtown","business_date":"2026-06-28","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":84.5925},{"branch":"downtown","business_date":"2026-06-30","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":149.1137},{"branch":"downtown","business_date":"2026-07-01","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":77.5328},{"branch":"downtown","business_date":"2026-07-02","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":49.4108},{"branch":"downtown","business_date":"2026-07-03","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":80.5783},{"branch":"downtown","business_date":"2026-07-04","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":97.4297},{"branch":"downtown","business_date":"2026-07-05","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":74.9127},{"branch":"downtown","business_date":"2026-07-08","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":40.1412},{"branch":"downtown","business_date":"2026-07-09","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":45.5038},{"branch":"downtown","business_date":"2026-07-10","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":137.9684},{"branch":"downtown","business_date":"2026-07-11","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":82.5723},{"branch":"downtown","business_date":"2026-07-12","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":79.6043},{"branch":"downtown","business_date":"2026-07-15","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":76.4775},{"branch":"downtown","business_date":"2026-07-16","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":60.6698},{"branch":"downtown","business_date":"2026-07-17","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":106.134},{"branch":"downtown","business_date":"2026-07-18","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":115.0598},{"branch":"downtown","business_date":"2026-07-19","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":39.6759},{"branch":"downtown","business_date":"2026-07-22","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":170.3994},{"branch":"downtown","business_date":"2026-07-23","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":45.3192},{"branch":"downtown","business_date":"2026-07-24","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":140.6425},{"branch":"downtown","business_date":"2026-07-25","department":"kitchen","staff_key":"신성경","hours":8.5,"tip_eligible":true,"tip_override":92.7774},{"branch":"downtown","business_date":"2026-07-26","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":42.5925},{"branch":"downtown","business_date":"2026-07-29","department":"kitchen","staff_key":"신성경","hours":8,"tip_eligible":true,"tip_override":63.8432},{"branch":"downtown","business_date":"2025-12-31","department":"kitchen","staff_key":"이현구","hours":9.5,"tip_eligible":true,"tip_override":139.7106},{"branch":"downtown","business_date":"2026-01-01","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":25.48},{"branch":"downtown","business_date":"2026-01-02","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":75.131},{"branch":"downtown","business_date":"2026-01-03","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":80.8034},{"branch":"downtown","business_date":"2026-01-04","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":57.0474},{"branch":"downtown","business_date":"2026-01-07","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":43.8077},{"branch":"downtown","business_date":"2026-01-08","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":25.1742},{"branch":"downtown","business_date":"2026-01-09","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":139.6353},{"branch":"downtown","business_date":"2026-01-10","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":72.364},{"branch":"downtown","business_date":"2026-01-11","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":32.2125},{"branch":"downtown","business_date":"2026-01-14","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":49.2409},{"branch":"downtown","business_date":"2026-01-15","department":"kitchen","staff_key":"이현구","hours":9,"tip_eligible":true,"tip_override":82.2024},{"branch":"downtown","business_date":"2026-01-16","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":93.7355},{"branch":"downtown","business_date":"2026-01-17","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":78.0392},{"branch":"downtown","business_date":"2026-01-18","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":42.9082},{"branch":"downtown","business_date":"2026-01-21","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":101.1431},{"branch":"downtown","business_date":"2026-01-24","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":73.3631},{"branch":"downtown","business_date":"2026-01-25","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":48.79},{"branch":"downtown","business_date":"2026-01-26","department":"kitchen","staff_key":"이현구","hours":3.5,"tip_eligible":true,"tip_override":18.754},{"branch":"downtown","business_date":"2026-01-28","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":34.4512},{"branch":"downtown","business_date":"2026-01-29","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":60.9934},{"branch":"downtown","business_date":"2026-01-30","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":88.9421},{"branch":"downtown","business_date":"2026-01-31","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":55.9659},{"branch":"downtown","business_date":"2026-02-01","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":50.6432},{"branch":"downtown","business_date":"2026-02-02","department":"kitchen","staff_key":"이현구","hours":3.5,"tip_eligible":true,"tip_override":41.8246},{"branch":"downtown","business_date":"2026-02-04","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":41.9309},{"branch":"downtown","business_date":"2026-02-05","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":71.5194},{"branch":"downtown","business_date":"2026-02-06","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":81.7923},{"branch":"downtown","business_date":"2026-02-07","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":59.0518},{"branch":"downtown","business_date":"2026-02-08","department":"kitchen","staff_key":"이현구","hours":3.5,"tip_eligible":true,"tip_override":13.632},{"branch":"downtown","business_date":"2026-02-09","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":54.9255},{"branch":"downtown","business_date":"2026-02-11","department":"kitchen","staff_key":"이현구","hours":3,"tip_eligible":true,"tip_override":15.8603},{"branch":"downtown","business_date":"2026-02-12","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":43.6827},{"branch":"downtown","business_date":"2026-02-13","department":"kitchen","staff_key":"이현구","hours":7,"tip_eligible":true,"tip_override":63.6389},{"branch":"downtown","business_date":"2026-02-14","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":97.6961},{"branch":"downtown","business_date":"2026-02-15","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":67.3397},{"branch":"downtown","business_date":"2026-02-16","department":"kitchen","staff_key":"이현구","hours":3.5,"tip_eligible":true,"tip_override":22.1085},{"branch":"downtown","business_date":"2026-02-18","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":27.6919},{"branch":"downtown","business_date":"2026-02-19","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":55.0837},{"branch":"downtown","business_date":"2026-02-20","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":112.8336},{"branch":"downtown","business_date":"2026-02-21","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":111.9937},{"branch":"downtown","business_date":"2026-02-22","department":"kitchen","staff_key":"이현구","hours":3,"tip_eligible":true,"tip_override":30},{"branch":"downtown","business_date":"2026-02-25","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":53.3229},{"branch":"downtown","business_date":"2026-02-26","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":43.0338},{"branch":"downtown","business_date":"2026-02-27","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":150.1419},{"branch":"downtown","business_date":"2026-02-28","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":92.4198},{"branch":"downtown","business_date":"2026-03-01","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":29.5785},{"branch":"downtown","business_date":"2026-03-04","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":49.9032},{"branch":"downtown","business_date":"2026-03-05","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":35.7532},{"branch":"downtown","business_date":"2026-03-06","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":129.5744},{"branch":"downtown","business_date":"2026-03-07","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":107.51},{"branch":"downtown","business_date":"2026-03-08","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":37.1706},{"branch":"downtown","business_date":"2026-03-11","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":46.649},{"branch":"downtown","business_date":"2026-03-12","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":35.9252},{"branch":"downtown","business_date":"2026-03-13","department":"kitchen","staff_key":"이현구","hours":10.5,"tip_eligible":true,"tip_override":62.83},{"branch":"downtown","business_date":"2026-03-14","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":165.2986},{"branch":"downtown","business_date":"2026-03-15","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":50.4797},{"branch":"downtown","business_date":"2026-03-18","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":21.776},{"branch":"downtown","business_date":"2026-03-19","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":33.7884},{"branch":"downtown","business_date":"2026-03-20","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":184.518},{"branch":"downtown","business_date":"2026-03-21","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":90.7547},{"branch":"downtown","business_date":"2026-03-22","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":109.5571},{"branch":"downtown","business_date":"2026-03-25","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":38.9727},{"branch":"downtown","business_date":"2026-03-26","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":27.6321},{"branch":"downtown","business_date":"2026-03-27","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":140.6658},{"branch":"downtown","business_date":"2026-03-28","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":123.3116},{"branch":"downtown","business_date":"2026-03-29","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":86.1108},{"branch":"downtown","business_date":"2026-04-01","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":33.7889},{"branch":"downtown","business_date":"2026-04-02","department":"kitchen","staff_key":"이현구","hours":9,"tip_eligible":true,"tip_override":123.8771},{"branch":"downtown","business_date":"2026-04-03","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":114.9771},{"branch":"downtown","business_date":"2026-04-04","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":108.6368},{"branch":"downtown","business_date":"2026-04-08","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":42.5692},{"branch":"downtown","business_date":"2026-04-09","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":54.6351},{"branch":"downtown","business_date":"2026-04-10","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":114.9366},{"branch":"downtown","business_date":"2026-04-11","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":111.0693},{"branch":"downtown","business_date":"2026-04-12","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":47.93},{"branch":"downtown","business_date":"2026-04-15","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":55.27},{"branch":"downtown","business_date":"2026-04-16","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":37.4438},{"branch":"downtown","business_date":"2026-04-17","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":157.1654},{"branch":"downtown","business_date":"2026-04-18","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":92.5913},{"branch":"downtown","business_date":"2026-04-19","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":73.7032},{"branch":"downtown","business_date":"2026-04-20","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":97.7238},{"branch":"downtown","business_date":"2026-04-21","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":71.8848},{"branch":"downtown","business_date":"2026-04-24","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":130.9717},{"branch":"downtown","business_date":"2026-04-25","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":126.5312},{"branch":"downtown","business_date":"2026-04-26","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":84.0304},{"branch":"downtown","business_date":"2026-04-27","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":56.1986},{"branch":"downtown","business_date":"2026-04-28","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":54.989},{"branch":"downtown","business_date":"2026-05-01","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":90.1125},{"branch":"downtown","business_date":"2026-05-02","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":61.651},{"branch":"downtown","business_date":"2026-05-03","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":70.6881},{"branch":"downtown","business_date":"2026-05-04","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":49.403},{"branch":"downtown","business_date":"2026-05-05","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":58.8866},{"branch":"downtown","business_date":"2026-05-08","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":125.9842},{"branch":"downtown","business_date":"2026-05-09","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":61.1306},{"branch":"downtown","business_date":"2026-05-10","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":48.8687},{"branch":"downtown","business_date":"2026-05-11","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":121.7762},{"branch":"downtown","business_date":"2026-05-12","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":79.2252},{"branch":"downtown","business_date":"2026-05-15","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":95.3955},{"branch":"downtown","business_date":"2026-05-16","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":95.12},{"branch":"downtown","business_date":"2026-05-17","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":98.1365},{"branch":"downtown","business_date":"2026-05-18","department":"kitchen","staff_key":"이현구","hours":9,"tip_eligible":true,"tip_override":99.1428},{"branch":"downtown","business_date":"2026-05-19","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":47.7378},{"branch":"downtown","business_date":"2026-05-22","department":"kitchen","staff_key":"이현구","hours":9,"tip_eligible":true,"tip_override":171.7587},{"branch":"downtown","business_date":"2026-05-23","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":50.2288},{"branch":"downtown","business_date":"2026-05-24","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":31.3601},{"branch":"downtown","business_date":"2026-05-25","department":"kitchen","staff_key":"이현구","hours":9,"tip_eligible":true,"tip_override":133.3626},{"branch":"downtown","business_date":"2026-05-26","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":54.6734},{"branch":"downtown","business_date":"2026-05-29","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":79.3718},{"branch":"downtown","business_date":"2026-05-30","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":110.8501},{"branch":"downtown","business_date":"2026-05-31","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":143.141},{"branch":"downtown","business_date":"2026-06-01","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":49.1528},{"branch":"downtown","business_date":"2026-06-02","department":"kitchen","staff_key":"이현구","hours":5.5,"tip_eligible":true,"tip_override":59.4484},{"branch":"downtown","business_date":"2026-06-05","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":127.877},{"branch":"downtown","business_date":"2026-06-06","department":"kitchen","staff_key":"이현구","hours":9,"tip_eligible":true,"tip_override":142.6663},{"branch":"downtown","business_date":"2026-06-07","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":67.4215},{"branch":"downtown","business_date":"2026-06-08","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":74.8572},{"branch":"downtown","business_date":"2026-06-09","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":99.6386},{"branch":"downtown","business_date":"2026-06-10","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":24.8929},{"branch":"downtown","business_date":"2026-06-12","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":99.8986},{"branch":"downtown","business_date":"2026-06-13","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":105.2898},{"branch":"downtown","business_date":"2026-06-14","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":27.8016},{"branch":"downtown","business_date":"2026-06-15","department":"kitchen","staff_key":"이현구","hours":9,"tip_eligible":true,"tip_override":102.123},{"branch":"downtown","business_date":"2026-06-16","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":59.8074},{"branch":"downtown","business_date":"2026-06-19","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":123.552},{"branch":"downtown","business_date":"2026-06-20","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":107.2479},{"branch":"downtown","business_date":"2026-06-21","department":"kitchen","staff_key":"이현구","hours":7.5,"tip_eligible":true,"tip_override":19.1463},{"branch":"downtown","business_date":"2026-06-22","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":92.241},{"branch":"downtown","business_date":"2026-06-23","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":44.9214},{"branch":"downtown","business_date":"2026-06-24","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":116.8484},{"branch":"downtown","business_date":"2026-06-26","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":144.274},{"branch":"downtown","business_date":"2026-06-27","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":131.1048},{"branch":"downtown","business_date":"2026-06-28","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":84.5925},{"branch":"downtown","business_date":"2026-06-29","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":90.907},{"branch":"downtown","business_date":"2026-07-01","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":77.5328},{"branch":"downtown","business_date":"2026-07-03","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":80.5783},{"branch":"downtown","business_date":"2026-07-04","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":97.4297},{"branch":"downtown","business_date":"2026-07-05","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":74.9127},{"branch":"downtown","business_date":"2026-07-06","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":66.3076},{"branch":"downtown","business_date":"2026-07-07","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":99.6132},{"branch":"downtown","business_date":"2026-07-08","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":40.1412},{"branch":"downtown","business_date":"2026-07-10","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":137.9684},{"branch":"downtown","business_date":"2026-07-11","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":82.5723},{"branch":"downtown","business_date":"2026-07-12","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":79.6043},{"branch":"downtown","business_date":"2026-07-13","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":108.6844},{"branch":"downtown","business_date":"2026-07-14","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":77.1066},{"branch":"downtown","business_date":"2026-07-17","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":106.134},{"branch":"downtown","business_date":"2026-07-18","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":115.0598},{"branch":"downtown","business_date":"2026-07-19","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":39.6759},{"branch":"downtown","business_date":"2026-07-20","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":114.9296},{"branch":"downtown","business_date":"2026-07-21","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":87.0041},{"branch":"downtown","business_date":"2026-07-24","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":140.6425},{"branch":"downtown","business_date":"2026-07-25","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":92.7774},{"branch":"downtown","business_date":"2026-07-26","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":42.5925},{"branch":"downtown","business_date":"2026-07-27","department":"kitchen","staff_key":"이현구","hours":8,"tip_eligible":true,"tip_override":48.3141},{"branch":"downtown","business_date":"2026-07-28","department":"kitchen","staff_key":"이현구","hours":8.5,"tip_eligible":true,"tip_override":75.6247},{"branch":"downtown","business_date":"2025-12-31","department":"kitchen","staff_key":"사장님","hours":9,"tip_eligible":true,"tip_override":29.82},{"branch":"downtown","business_date":"2026-01-05","department":"kitchen","staff_key":"사장님","hours":6,"tip_eligible":true,"tip_override":11.031},{"branch":"downtown","business_date":"2026-01-06","department":"kitchen","staff_key":"사장님","hours":7.5,"tip_eligible":true,"tip_override":102.9589},{"branch":"downtown","business_date":"2026-01-09","department":"kitchen","staff_key":"사장님","hours":7.5,"tip_eligible":true,"tip_override":29.571},{"branch":"downtown","business_date":"2026-01-12","department":"kitchen","staff_key":"사장님","hours":7.5,"tip_eligible":true,"tip_override":15.975},{"branch":"downtown","business_date":"2026-01-13","department":"kitchen","staff_key":"사장님","hours":7.5,"tip_eligible":true,"tip_override":97.1084},{"branch":"downtown","business_date":"2026-01-14","department":"kitchen","staff_key":"사장님","hours":7,"tip_eligible":true,"tip_override":45.9582},{"branch":"downtown","business_date":"2026-01-16","department":"kitchen","staff_key":"사장님","hours":7.5,"tip_eligible":true,"tip_override":87.877},{"branch":"downtown","business_date":"2026-01-17","department":"kitchen","staff_key":"사장님","hours":6,"tip_eligible":true,"tip_override":58.5294},{"branch":"downtown","business_date":"2026-01-19","department":"kitchen","staff_key":"사장님","hours":6,"tip_eligible":true,"tip_override":21.959},{"branch":"downtown","business_date":"2026-01-20","department":"kitchen","staff_key":"사장님","hours":7.5,"tip_eligible":true,"tip_override":52.7059},{"branch":"downtown","business_date":"2026-01-21","department":"kitchen","staff_key":"사장님","hours":3.5,"tip_eligible":true,"tip_override":47.2001},{"branch":"downtown","business_date":"2026-01-22","department":"kitchen","staff_key":"사장님","hours":7.5,"tip_eligible":true,"tip_override":43.8742},{"branch":"downtown","business_date":"2026-01-23","department":"kitchen","staff_key":"사장님","hours":8,"tip_eligible":true,"tip_override":163.3605},{"branch":"downtown","business_date":"2026-01-24","department":"kitchen","staff_key":"사장님","hours":6.5,"tip_eligible":true,"tip_override":63.5814},{"branch":"downtown","business_date":"2026-02-23","department":"kitchen","staff_key":"사장님","hours":5,"tip_eligible":true,"tip_override":12.2509},{"branch":"downtown","business_date":"2026-02-25","department":"kitchen","staff_key":"사장님","hours":6.5,"tip_eligible":true,"tip_override":46.2131},{"branch":"downtown","business_date":"2026-03-02","department":"kitchen","staff_key":"사장님","hours":6,"tip_eligible":true,"tip_override":26.1491},{"branch":"downtown","business_date":"2026-03-03","department":"kitchen","staff_key":"사장님","hours":5,"tip_eligible":true,"tip_override":28.9496},{"branch":"downtown","business_date":"2026-03-04","department":"kitchen","staff_key":"사장님","hours":4,"tip_eligible":true,"tip_override":26.615},{"branch":"downtown","business_date":"2026-03-09","department":"kitchen","staff_key":"사장님","hours":6,"tip_eligible":true,"tip_override":23.163},{"branch":"downtown","business_date":"2026-03-11","department":"kitchen","staff_key":"사장님","hours":6.5,"tip_eligible":true,"tip_override":37.9023},{"branch":"downtown","business_date":"2026-03-17","department":"kitchen","staff_key":"사장님","hours":4.5,"tip_eligible":true,"tip_override":26.355},{"branch":"downtown","business_date":"2026-03-24","department":"kitchen","staff_key":"사장님","hours":6.5,"tip_eligible":true,"tip_override":35.505},{"branch":"downtown","business_date":"2026-03-25","department":"kitchen","staff_key":"사장님","hours":4,"tip_eligible":true,"tip_override":19.4863},{"branch":"downtown","business_date":"2026-04-05","department":"kitchen","staff_key":"사장님","hours":5,"tip_eligible":true,"tip_override":43.6266},{"branch":"downtown","business_date":"2026-05-06","department":"kitchen","staff_key":"사장님","hours":1,"tip_eligible":true,"tip_override":9.3604},{"branch":"downtown","business_date":"2026-05-07","department":"kitchen","staff_key":"사장님","hours":6,"tip_eligible":true,"tip_override":33.84},{"branch":"downtown","business_date":"2026-05-22","department":"kitchen","staff_key":"사장님","hours":6,"tip_eligible":true,"tip_override":79.275},{"branch":"downtown","business_date":"2026-05-27","department":"kitchen","staff_key":"사장님","hours":5,"tip_eligible":true,"tip_override":32.287},{"branch":"downtown","business_date":"2026-05-28","department":"kitchen","staff_key":"사장님","hours":5,"tip_eligible":true,"tip_override":15.135},{"branch":"downtown","business_date":"2026-06-02","department":"kitchen","staff_key":"사장님","hours":6.5,"tip_eligible":true,"tip_override":40.672},{"branch":"downtown","business_date":"2026-06-03","department":"kitchen","staff_key":"사장님","hours":8,"tip_eligible":true,"tip_override":34.6408},{"branch":"downtown","business_date":"2026-06-04","department":"kitchen","staff_key":"사장님","hours":8,"tip_eligible":true,"tip_override":29.7544},{"branch":"downtown","business_date":"2026-06-05","department":"kitchen","staff_key":"사장님","hours":7.5,"tip_eligible":true,"tip_override":119.8846},{"branch":"downtown","business_date":"2026-06-06","department":"kitchen","staff_key":"사장님","hours":8,"tip_eligible":true,"tip_override":126.8145},{"branch":"downtown","business_date":"2026-06-07","department":"kitchen","staff_key":"사장님","hours":4.5,"tip_eligible":true,"tip_override":37.9246},{"branch":"downtown","business_date":"2026-06-26","department":"kitchen","staff_key":"사장님","hours":8,"tip_eligible":true,"tip_override":135.7873},{"branch":"downtown","business_date":"2026-01-01","department":"kitchen","staff_key":"부경","hours":7.5,"tip_eligible":true,"tip_override":25.48},{"branch":"downtown","business_date":"2026-01-08","department":"kitchen","staff_key":"부경","hours":7.5,"tip_eligible":true,"tip_override":25.1742},{"branch":"downtown","business_date":"2026-01-27","department":"kitchen","staff_key":"부경","hours":7.5,"tip_eligible":true,"tip_override":54.9948},{"branch":"downtown","business_date":"2026-01-29","department":"kitchen","staff_key":"부경","hours":7.5,"tip_eligible":true,"tip_override":60.9934},{"branch":"downtown","business_date":"2026-01-30","department":"kitchen","staff_key":"부경","hours":7.5,"tip_eligible":true,"tip_override":88.9421},{"branch":"downtown","business_date":"2026-02-03","department":"kitchen","staff_key":"부경","hours":4,"tip_eligible":true,"tip_override":11.4608},{"branch":"downtown","business_date":"2026-02-05","department":"kitchen","staff_key":"부경","hours":7.5,"tip_eligible":true,"tip_override":71.5194},{"branch":"downtown","business_date":"2026-02-06","department":"kitchen","staff_key":"부경","hours":7.5,"tip_eligible":true,"tip_override":81.7923},{"branch":"downtown","business_date":"2026-02-07","department":"kitchen","staff_key":"부경","hours":7.5,"tip_eligible":true,"tip_override":59.0518},{"branch":"downtown","business_date":"2026-02-10","department":"kitchen","staff_key":"부경","hours":7.5,"tip_eligible":true,"tip_override":28.2902},{"branch":"downtown","business_date":"2026-02-12","department":"kitchen","staff_key":"부경","hours":7.5,"tip_eligible":true,"tip_override":43.6827},{"branch":"downtown","business_date":"2026-02-13","department":"kitchen","staff_key":"부경","hours":7.5,"tip_eligible":true,"tip_override":68.1846},{"branch":"downtown","business_date":"2026-02-17","department":"kitchen","staff_key":"부경","hours":7.5,"tip_eligible":true,"tip_override":44.5412},{"branch":"downtown","business_date":"2026-02-18","department":"kitchen","staff_key":"부경","hours":4,"tip_eligible":true,"tip_override":14.769},{"branch":"downtown","business_date":"2026-02-26","department":"kitchen","staff_key":"부경","hours":7.5,"tip_eligible":true,"tip_override":43.0338},{"branch":"downtown","business_date":"2026-03-05","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":35.7532},{"branch":"downtown","business_date":"2026-03-12","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":35.9252},{"branch":"downtown","business_date":"2026-03-18","department":"kitchen","staff_key":"부경","hours":4.5,"tip_eligible":true,"tip_override":11.5284},{"branch":"downtown","business_date":"2026-03-19","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":33.7884},{"branch":"downtown","business_date":"2026-03-26","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":27.6321},{"branch":"downtown","business_date":"2026-04-01","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":33.7889},{"branch":"downtown","business_date":"2026-04-02","department":"kitchen","staff_key":"부경","hours":9,"tip_eligible":true,"tip_override":123.8771},{"branch":"downtown","business_date":"2026-04-08","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":42.5692},{"branch":"downtown","business_date":"2026-04-09","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":54.6351},{"branch":"downtown","business_date":"2026-04-15","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":55.27},{"branch":"downtown","business_date":"2026-04-16","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":37.4438},{"branch":"downtown","business_date":"2026-04-22","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":38.2538},{"branch":"downtown","business_date":"2026-04-23","department":"kitchen","staff_key":"부경","hours":8.5,"tip_eligible":true,"tip_override":54.2424},{"branch":"downtown","business_date":"2026-04-29","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":18.7673},{"branch":"downtown","business_date":"2026-04-30","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":46.0304},{"branch":"downtown","business_date":"2026-05-13","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":31.107},{"branch":"downtown","business_date":"2026-05-14","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":47.9233},{"branch":"downtown","business_date":"2026-05-21","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":66.9039},{"branch":"downtown","business_date":"2026-06-03","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":34.6408},{"branch":"downtown","business_date":"2026-06-04","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":29.7544},{"branch":"downtown","business_date":"2026-06-11","department":"kitchen","staff_key":"부경","hours":9,"tip_eligible":true,"tip_override":113.7603},{"branch":"downtown","business_date":"2026-06-18","department":"kitchen","staff_key":"부경","hours":8.5,"tip_eligible":true,"tip_override":137.009},{"branch":"downtown","business_date":"2026-06-25","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":67.9803},{"branch":"downtown","business_date":"2026-07-02","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":49.4108},{"branch":"downtown","business_date":"2026-07-09","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":45.5038},{"branch":"downtown","business_date":"2026-07-16","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":60.6698},{"branch":"downtown","business_date":"2026-07-23","department":"kitchen","staff_key":"부경","hours":8,"tip_eligible":true,"tip_override":45.3192},{"branch":"downtown","business_date":"2026-07-06","department":"kitchen","staff_key":"허준서","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-07-07","department":"kitchen","staff_key":"허준서","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-07-10","department":"kitchen","staff_key":"허준서","hours":8.5,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-07-13","department":"kitchen","staff_key":"허준서","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-07-14","department":"kitchen","staff_key":"허준서","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-07-15","department":"kitchen","staff_key":"허준서","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-07-17","department":"kitchen","staff_key":"허준서","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-07-20","department":"kitchen","staff_key":"허준서","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-07-21","department":"kitchen","staff_key":"허준서","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-07-22","department":"kitchen","staff_key":"허준서","hours":8.5,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-07-24","department":"kitchen","staff_key":"허준서","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-07-27","department":"kitchen","staff_key":"허준서","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-07-28","department":"kitchen","staff_key":"허준서","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-07-29","department":"kitchen","staff_key":"허준서","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-05-31","department":"kitchen","staff_key":"태연","hours":8.5,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-04-24","department":"kitchen","staff_key":"예슬","hours":7.5,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-04-25","department":"kitchen","staff_key":"예슬","hours":7.5,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-04-27","department":"kitchen","staff_key":"예슬","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-04-28","department":"kitchen","staff_key":"예슬","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-05-01","department":"kitchen","staff_key":"예슬","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-05-02","department":"kitchen","staff_key":"예슬","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-05-04","department":"kitchen","staff_key":"예슬","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-05-05","department":"kitchen","staff_key":"예슬","hours":3,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-05-08","department":"kitchen","staff_key":"예슬","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-05-09","department":"kitchen","staff_key":"예슬","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-05-11","department":"kitchen","staff_key":"예슬","hours":8.5,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-05-12","department":"kitchen","staff_key":"예슬","hours":8.5,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-05-15","department":"kitchen","staff_key":"예슬","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-05-16","department":"kitchen","staff_key":"예슬","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-01-02","department":"kitchen","staff_key":"성우","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-01-03","department":"kitchen","staff_key":"성우","hours":7.5,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-01-07","department":"kitchen","staff_key":"성우","hours":7.5,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-01-31","department":"kitchen","staff_key":"은성","hours":7.5,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-02-14","department":"kitchen","staff_key":"은성","hours":7.5,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2025-12-31","department":"hall","staff_key":"영환","hours":11,"tip_eligible":true,"tip_override":154.6198},{"branch":"downtown","business_date":"2026-01-01","department":"hall","staff_key":"영환","hours":8,"tip_eligible":true,"tip_override":38.2201},{"branch":"downtown","business_date":"2026-01-02","department":"hall","staff_key":"영환","hours":6,"tip_eligible":true,"tip_override":64.398},{"branch":"downtown","business_date":"2026-01-03","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":84.8436},{"branch":"downtown","business_date":"2026-01-08","department":"hall","staff_key":"영환","hours":7.5,"tip_eligible":true,"tip_override":37.7613},{"branch":"downtown","business_date":"2026-01-09","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":169.2669},{"branch":"downtown","business_date":"2026-01-10","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":108.546},{"branch":"downtown","business_date":"2026-01-16","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":153.8709},{"branch":"downtown","business_date":"2026-01-17","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":122.3264},{"branch":"downtown","business_date":"2026-01-19","department":"hall","staff_key":"영환","hours":8.5,"tip_eligible":true,"tip_override":105.881},{"branch":"downtown","business_date":"2026-01-23","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":178.0375},{"branch":"downtown","business_date":"2026-01-24","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":118.2981},{"branch":"downtown","business_date":"2026-01-27","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":164.9844},{"branch":"downtown","business_date":"2026-01-29","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":109.7881},{"branch":"downtown","business_date":"2026-01-30","department":"hall","staff_key":"영환","hours":6,"tip_eligible":true,"tip_override":100.0599},{"branch":"downtown","business_date":"2026-01-31","department":"hall","staff_key":"영환","hours":10,"tip_eligible":true,"tip_override":83.9488},{"branch":"downtown","business_date":"2026-02-02","department":"hall","staff_key":"영환","hours":8,"tip_eligible":true,"tip_override":197.1733},{"branch":"downtown","business_date":"2026-02-13","department":"hall","staff_key":"영환","hours":6.5,"tip_eligible":true,"tip_override":86.6702},{"branch":"downtown","business_date":"2026-02-15","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":101.0095},{"branch":"downtown","business_date":"2026-02-16","department":"hall","staff_key":"영환","hours":2.5,"tip_eligible":true,"tip_override":24.7176},{"branch":"downtown","business_date":"2026-02-20","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":112.8336},{"branch":"downtown","business_date":"2026-02-21","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":125.9929},{"branch":"downtown","business_date":"2026-02-23","department":"hall","staff_key":"영환","hours":8.5,"tip_eligible":true,"tip_override":45.9409},{"branch":"downtown","business_date":"2026-02-27","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":163.2794},{"branch":"downtown","business_date":"2026-02-28","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":103.9723},{"branch":"downtown","business_date":"2026-03-02","department":"hall","staff_key":"영환","hours":8.5,"tip_eligible":true,"tip_override":88.2532},{"branch":"downtown","business_date":"2026-03-06","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":144.8184},{"branch":"downtown","business_date":"2026-03-07","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":123.5222},{"branch":"downtown","business_date":"2026-03-09","department":"hall","staff_key":"영환","hours":6.5,"tip_eligible":true,"tip_override":111.6665},{"branch":"downtown","business_date":"2026-03-13","department":"hall","staff_key":"영환","hours":4.5,"tip_eligible":true,"tip_override":42.4102},{"branch":"downtown","business_date":"2026-03-14","department":"hall","staff_key":"영환","hours":10,"tip_eligible":true,"tip_override":187.1305},{"branch":"downtown","business_date":"2026-03-16","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":101.8651},{"branch":"downtown","business_date":"2026-03-17","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":152.2848},{"branch":"downtown","business_date":"2026-03-20","department":"hall","staff_key":"영환","hours":10,"tip_eligible":true,"tip_override":184.518},{"branch":"downtown","business_date":"2026-03-21","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":136.132},{"branch":"downtown","business_date":"2026-03-23","department":"hall","staff_key":"영환","hours":10,"tip_eligible":true,"tip_override":223.9488},{"branch":"downtown","business_date":"2026-03-27","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":160.359},{"branch":"downtown","business_date":"2026-03-28","department":"hall","staff_key":"영환","hours":10.5,"tip_eligible":true,"tip_override":184.9675},{"branch":"downtown","business_date":"2026-03-30","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":135.608},{"branch":"downtown","business_date":"2026-03-31","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":104.3816},{"branch":"downtown","business_date":"2026-04-02","department":"hall","staff_key":"영환","hours":10,"tip_eligible":true,"tip_override":185.8156},{"branch":"downtown","business_date":"2026-04-03","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":136.5353},{"branch":"downtown","business_date":"2026-04-04","department":"hall","staff_key":"영환","hours":10.5,"tip_eligible":true,"tip_override":122.2164},{"branch":"downtown","business_date":"2026-04-09","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":132.8193},{"branch":"downtown","business_date":"2026-04-10","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":155.9854},{"branch":"downtown","business_date":"2026-04-11","department":"hall","staff_key":"영환","hours":5.5,"tip_eligible":true,"tip_override":76.3601},{"branch":"downtown","business_date":"2026-04-16","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":69.7229},{"branch":"downtown","business_date":"2026-04-17","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":179.1686},{"branch":"downtown","business_date":"2026-04-18","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":105.5541},{"branch":"downtown","business_date":"2026-04-19","department":"hall","staff_key":"영환","hours":10,"tip_eligible":true,"tip_override":163.785},{"branch":"downtown","business_date":"2026-04-23","department":"hall","staff_key":"영환","hours":10,"tip_eligible":true,"tip_override":162.73},{"branch":"downtown","business_date":"2026-04-24","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":149.3078},{"branch":"downtown","business_date":"2026-04-25","department":"hall","staff_key":"영환","hours":6.5,"tip_eligible":true,"tip_override":128.9179},{"branch":"downtown","business_date":"2026-04-26","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":126.0455},{"branch":"downtown","business_date":"2026-05-01","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":90.1125},{"branch":"downtown","business_date":"2026-05-02","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":83.4091},{"branch":"downtown","business_date":"2026-05-09","department":"hall","staff_key":"영환","hours":6,"tip_eligible":true,"tip_override":44.014},{"branch":"downtown","business_date":"2026-05-15","department":"hall","staff_key":"영환","hours":8.5,"tip_eligible":true,"tip_override":97.3034},{"branch":"downtown","business_date":"2026-05-16","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":95.12},{"branch":"downtown","business_date":"2026-05-19","department":"hall","staff_key":"영환","hours":8.5,"tip_eligible":true,"tip_override":35.8034},{"branch":"downtown","business_date":"2026-05-22","department":"hall","staff_key":"영환","hours":10,"tip_eligible":true,"tip_override":211.3949},{"branch":"downtown","business_date":"2026-05-23","department":"hall","staff_key":"영환","hours":8.5,"tip_eligible":true,"tip_override":50.2288},{"branch":"downtown","business_date":"2026-05-29","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":90.4838},{"branch":"downtown","business_date":"2026-05-30","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":138.5625},{"branch":"downtown","business_date":"2026-06-05","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":123.8808},{"branch":"downtown","business_date":"2026-06-06","department":"hall","staff_key":"영환","hours":10,"tip_eligible":true,"tip_override":146.9895},{"branch":"downtown","business_date":"2026-06-11","department":"hall","staff_key":"영환","hours":10.5,"tip_eligible":true,"tip_override":170.6404},{"branch":"downtown","business_date":"2026-06-12","department":"hall","staff_key":"영환","hours":10.5,"tip_eligible":true,"tip_override":99.8986},{"branch":"downtown","business_date":"2026-06-13","department":"hall","staff_key":"영환","hours":8.5,"tip_eligible":true,"tip_override":97.6323},{"branch":"downtown","business_date":"2026-06-21","department":"hall","staff_key":"영환","hours":8.5,"tip_eligible":true,"tip_override":28.7194},{"branch":"downtown","business_date":"2026-06-22","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":69.1807},{"branch":"downtown","business_date":"2026-06-24","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":116.8484},{"branch":"downtown","business_date":"2026-06-26","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":145.1227},{"branch":"downtown","business_date":"2026-06-27","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":131.1048},{"branch":"downtown","business_date":"2026-06-30","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":111.8353},{"branch":"downtown","business_date":"2026-07-03","department":"hall","staff_key":"영환","hours":5.5,"tip_eligible":true,"tip_override":63.3115},{"branch":"downtown","business_date":"2026-07-04","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":97.4297},{"branch":"downtown","business_date":"2026-07-07","department":"hall","staff_key":"영환","hours":8.5,"tip_eligible":true,"tip_override":74.7099},{"branch":"downtown","business_date":"2026-07-10","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":137.9684},{"branch":"downtown","business_date":"2026-07-11","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":82.5723},{"branch":"downtown","business_date":"2026-07-16","department":"hall","staff_key":"영환","hours":8.5,"tip_eligible":true,"tip_override":91.0047},{"branch":"downtown","business_date":"2026-07-17","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":140.6893},{"branch":"downtown","business_date":"2026-07-18","department":"hall","staff_key":"영환","hours":10,"tip_eligible":true,"tip_override":177.015},{"branch":"downtown","business_date":"2026-07-19","department":"hall","staff_key":"영환","hours":9,"tip_eligible":true,"tip_override":64.9242},{"branch":"downtown","business_date":"2026-07-20","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":86.1972},{"branch":"downtown","business_date":"2026-07-21","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":65.2531},{"branch":"downtown","business_date":"2026-07-22","department":"hall","staff_key":"영환","hours":9.5,"tip_eligible":true,"tip_override":127.7996},{"branch":"downtown","business_date":"2026-07-24","department":"hall","staff_key":"영환","hours":10,"tip_eligible":true,"tip_override":150.6884},{"branch":"downtown","business_date":"2026-07-25","department":"hall","staff_key":"영환","hours":10.5,"tip_eligible":true,"tip_override":139.1662},{"branch":"downtown","business_date":"2026-07-26","department":"hall","staff_key":"영환","hours":8.5,"tip_eligible":true,"tip_override":63.8888},{"branch":"downtown","business_date":"2025-12-31","department":"hall","staff_key":"서윤","hours":11,"tip_eligible":true,"tip_override":154.6198},{"branch":"downtown","business_date":"2026-01-02","department":"hall","staff_key":"서윤","hours":6,"tip_eligible":true,"tip_override":64.398},{"branch":"downtown","business_date":"2026-01-04","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":101.6156},{"branch":"downtown","business_date":"2026-01-10","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":108.546},{"branch":"downtown","business_date":"2026-01-11","department":"hall","staff_key":"서윤","hours":8,"tip_eligible":true,"tip_override":48.3188},{"branch":"downtown","business_date":"2026-01-13","department":"hall","staff_key":"서윤","hours":9,"tip_eligible":true,"tip_override":84.5783},{"branch":"downtown","business_date":"2026-01-16","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":153.8709},{"branch":"downtown","business_date":"2026-01-23","department":"hall","staff_key":"서윤","hours":9,"tip_eligible":true,"tip_override":178.0375},{"branch":"downtown","business_date":"2026-01-25","department":"hall","staff_key":"서윤","hours":10,"tip_eligible":true,"tip_override":146.3566},{"branch":"downtown","business_date":"2026-01-31","department":"hall","staff_key":"서윤","hours":10,"tip_eligible":true,"tip_override":83.9488},{"branch":"downtown","business_date":"2026-02-01","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":75.9647},{"branch":"downtown","business_date":"2026-02-06","department":"hall","staff_key":"서윤","hours":10,"tip_eligible":true,"tip_override":129.1458},{"branch":"downtown","business_date":"2026-02-07","department":"hall","staff_key":"서윤","hours":10.5,"tip_eligible":true,"tip_override":88.5778},{"branch":"downtown","business_date":"2026-02-13","department":"hall","staff_key":"서윤","hours":6.5,"tip_eligible":true,"tip_override":86.6702},{"branch":"downtown","business_date":"2026-02-15","department":"hall","staff_key":"서윤","hours":9,"tip_eligible":true,"tip_override":101.0095},{"branch":"downtown","business_date":"2026-02-20","department":"hall","staff_key":"서윤","hours":9,"tip_eligible":true,"tip_override":112.8336},{"branch":"downtown","business_date":"2026-02-22","department":"hall","staff_key":"서윤","hours":8.5,"tip_eligible":true,"tip_override":78.879},{"branch":"downtown","business_date":"2026-02-28","department":"hall","staff_key":"서윤","hours":9,"tip_eligible":true,"tip_override":103.9723},{"branch":"downtown","business_date":"2026-03-01","department":"hall","staff_key":"서윤","hours":8.5,"tip_eligible":true,"tip_override":53.8751},{"branch":"downtown","business_date":"2026-03-07","department":"hall","staff_key":"서윤","hours":9,"tip_eligible":true,"tip_override":123.5222},{"branch":"downtown","business_date":"2026-03-08","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":68.3459},{"branch":"downtown","business_date":"2026-03-11","department":"hall","staff_key":"서윤","hours":8.5,"tip_eligible":true,"tip_override":79.8541},{"branch":"downtown","business_date":"2026-03-13","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":89.5327},{"branch":"downtown","business_date":"2026-03-18","department":"hall","staff_key":"서윤","hours":9,"tip_eligible":true,"tip_override":44.9609},{"branch":"downtown","business_date":"2026-03-27","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":160.359},{"branch":"downtown","business_date":"2026-03-29","department":"hall","staff_key":"서윤","hours":10,"tip_eligible":true,"tip_override":156.5652},{"branch":"downtown","business_date":"2026-04-04","department":"hall","staff_key":"서윤","hours":7,"tip_eligible":true,"tip_override":81.4776},{"branch":"downtown","business_date":"2026-04-05","department":"hall","staff_key":"서윤","hours":8.5,"tip_eligible":true,"tip_override":99.7394},{"branch":"downtown","business_date":"2026-04-07","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":81.941},{"branch":"downtown","business_date":"2026-04-11","department":"hall","staff_key":"서윤","hours":11,"tip_eligible":true,"tip_override":152.7203},{"branch":"downtown","business_date":"2026-04-12","department":"hall","staff_key":"서윤","hours":5.5,"tip_eligible":true,"tip_override":65.906},{"branch":"downtown","business_date":"2026-04-18","department":"hall","staff_key":"서윤","hours":6,"tip_eligible":true,"tip_override":66.6658},{"branch":"downtown","business_date":"2026-04-24","department":"hall","staff_key":"서윤","hours":6,"tip_eligible":true,"tip_override":94.2996},{"branch":"downtown","business_date":"2026-04-30","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":69.0455},{"branch":"downtown","business_date":"2026-05-03","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":106.0321},{"branch":"downtown","business_date":"2026-05-05","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":44.1649},{"branch":"downtown","business_date":"2026-05-06","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":63.1829},{"branch":"downtown","business_date":"2026-05-11","department":"hall","staff_key":"서윤","hours":10,"tip_eligible":true,"tip_override":91.3321},{"branch":"downtown","business_date":"2026-05-12","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":59.4189},{"branch":"downtown","business_date":"2026-05-20","department":"hall","staff_key":"서윤","hours":9,"tip_eligible":true,"tip_override":32.2744},{"branch":"downtown","business_date":"2026-05-22","department":"hall","staff_key":"서윤","hours":10,"tip_eligible":true,"tip_override":211.3949},{"branch":"downtown","business_date":"2026-05-27","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":83.9488},{"branch":"downtown","business_date":"2026-05-29","department":"hall","staff_key":"서윤","hours":6,"tip_eligible":true,"tip_override":57.1477},{"branch":"downtown","business_date":"2026-06-02","department":"hall","staff_key":"서윤","hours":10,"tip_eligible":true,"tip_override":75.0934},{"branch":"downtown","business_date":"2026-06-07","department":"hall","staff_key":"서윤","hours":9,"tip_eligible":true,"tip_override":79.0096},{"branch":"downtown","business_date":"2026-06-14","department":"hall","staff_key":"서윤","hours":8.5,"tip_eligible":true,"tip_override":41.7023},{"branch":"downtown","business_date":"2026-06-17","department":"hall","staff_key":"서윤","hours":9,"tip_eligible":true,"tip_override":62.4677},{"branch":"downtown","business_date":"2026-06-18","department":"hall","staff_key":"서윤","hours":6.5,"tip_eligible":true,"tip_override":104.772},{"branch":"downtown","business_date":"2026-06-25","department":"hall","staff_key":"서윤","hours":9,"tip_eligible":true,"tip_override":101.9704},{"branch":"downtown","business_date":"2026-06-28","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":126.8887},{"branch":"downtown","business_date":"2026-07-02","department":"hall","staff_key":"서윤","hours":10,"tip_eligible":true,"tip_override":74.1162},{"branch":"downtown","business_date":"2026-07-04","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":97.4297},{"branch":"downtown","business_date":"2026-07-08","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":60.2119},{"branch":"downtown","business_date":"2026-07-11","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":82.5723},{"branch":"downtown","business_date":"2026-07-16","department":"hall","staff_key":"서윤","hours":8.5,"tip_eligible":true,"tip_override":91.0047},{"branch":"downtown","business_date":"2026-07-19","department":"hall","staff_key":"서윤","hours":7.5,"tip_eligible":true,"tip_override":54.1035},{"branch":"downtown","business_date":"2026-07-23","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":67.9789},{"branch":"downtown","business_date":"2026-07-28","department":"hall","staff_key":"서윤","hours":9.5,"tip_eligible":true,"tip_override":61.5801},{"branch":"downtown","business_date":"2026-01-03","department":"hall","staff_key":"우진","hours":9,"tip_eligible":true,"tip_override":84.8436},{"branch":"downtown","business_date":"2026-01-06","department":"hall","staff_key":"우진","hours":9,"tip_eligible":true,"tip_override":92.663},{"branch":"downtown","business_date":"2026-01-09","department":"hall","staff_key":"우진","hours":9.5,"tip_eligible":true,"tip_override":169.2669},{"branch":"downtown","business_date":"2026-01-18","department":"hall","staff_key":"우진","hours":9,"tip_eligible":true,"tip_override":77.2348},{"branch":"downtown","business_date":"2025-12-31","department":"hall","staff_key":"은성","hours":11,"tip_eligible":true,"tip_override":154.6198},{"branch":"downtown","business_date":"2026-01-02","department":"hall","staff_key":"은성","hours":9,"tip_eligible":true,"tip_override":96.597},{"branch":"downtown","business_date":"2026-01-05","department":"hall","staff_key":"은성","hours":10,"tip_eligible":true,"tip_override":124.102},{"branch":"downtown","business_date":"2026-01-07","department":"hall","staff_key":"은성","hours":9,"tip_eligible":true,"tip_override":39.4269},{"branch":"downtown","business_date":"2026-01-11","department":"hall","staff_key":"은성","hours":8,"tip_eligible":true,"tip_override":48.3188},{"branch":"downtown","business_date":"2026-01-12","department":"hall","staff_key":"은성","hours":9,"tip_eligible":true,"tip_override":95.8452},{"branch":"downtown","business_date":"2026-01-13","department":"hall","staff_key":"은성","hours":6.5,"tip_eligible":true,"tip_override":61.0843},{"branch":"downtown","business_date":"2026-01-14","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":84.7867},{"branch":"downtown","business_date":"2026-01-20","department":"hall","staff_key":"은성","hours":9,"tip_eligible":true,"tip_override":79.0589},{"branch":"downtown","business_date":"2026-01-22","department":"hall","staff_key":"은성","hours":8.5,"tip_eligible":true,"tip_override":65.8112},{"branch":"downtown","business_date":"2026-01-24","department":"hall","staff_key":"은성","hours":6,"tip_eligible":true,"tip_override":78.8654},{"branch":"downtown","business_date":"2026-01-26","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":88.4119},{"branch":"downtown","business_date":"2026-02-03","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":49.4248},{"branch":"downtown","business_date":"2026-02-05","department":"hall","staff_key":"은성","hours":6,"tip_eligible":true,"tip_override":85.8233},{"branch":"downtown","business_date":"2026-02-06","department":"hall","staff_key":"은성","hours":10,"tip_eligible":true,"tip_override":129.1458},{"branch":"downtown","business_date":"2026-02-07","department":"hall","staff_key":"은성","hours":10.5,"tip_eligible":true,"tip_override":88.5778},{"branch":"downtown","business_date":"2026-02-10","department":"hall","staff_key":"은성","hours":8,"tip_eligible":true,"tip_override":84.8705},{"branch":"downtown","business_date":"2026-02-13","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":126.6718},{"branch":"downtown","business_date":"2026-02-17","department":"hall","staff_key":"은성","hours":10,"tip_eligible":true,"tip_override":133.6236},{"branch":"downtown","business_date":"2026-02-18","department":"hall","staff_key":"은성","hours":6,"tip_eligible":true,"tip_override":38.2149},{"branch":"downtown","business_date":"2026-02-20","department":"hall","staff_key":"은성","hours":9,"tip_eligible":true,"tip_override":112.8336},{"branch":"downtown","business_date":"2026-02-24","department":"hall","staff_key":"은성","hours":8.5,"tip_eligible":true,"tip_override":60.9096},{"branch":"downtown","business_date":"2026-02-26","department":"hall","staff_key":"은성","hours":6.5,"tip_eligible":true,"tip_override":52.4474},{"branch":"downtown","business_date":"2026-02-27","department":"hall","staff_key":"은성","hours":6,"tip_eligible":true,"tip_override":108.8529},{"branch":"downtown","business_date":"2026-03-03","department":"hall","staff_key":"은성","hours":8.5,"tip_eligible":true,"tip_override":108.5609},{"branch":"downtown","business_date":"2026-03-04","department":"hall","staff_key":"은성","hours":5,"tip_eligible":true,"tip_override":44.1451},{"branch":"downtown","business_date":"2026-03-06","department":"hall","staff_key":"은성","hours":6.5,"tip_eligible":true,"tip_override":99.0863},{"branch":"downtown","business_date":"2026-03-10","department":"hall","staff_key":"은성","hours":10.5,"tip_eligible":true,"tip_override":148.1522},{"branch":"downtown","business_date":"2026-03-14","department":"hall","staff_key":"은성","hours":6.5,"tip_eligible":true,"tip_override":121.6348},{"branch":"downtown","business_date":"2026-03-15","department":"hall","staff_key":"은성","hours":5.5,"tip_eligible":true,"tip_override":57.4424},{"branch":"downtown","business_date":"2026-03-22","department":"hall","staff_key":"은성","hours":7,"tip_eligible":true,"tip_override":148.4322},{"branch":"downtown","business_date":"2026-03-24","department":"hall","staff_key":"은성","hours":10.5,"tip_eligible":true,"tip_override":174.7842},{"branch":"downtown","business_date":"2026-04-04","department":"hall","staff_key":"은성","hours":10.5,"tip_eligible":true,"tip_override":122.2164},{"branch":"downtown","business_date":"2026-04-11","department":"hall","staff_key":"은성","hours":7.5,"tip_eligible":true,"tip_override":104.1275},{"branch":"downtown","business_date":"2026-04-13","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":124.1152},{"branch":"downtown","business_date":"2026-04-14","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":142.2246},{"branch":"downtown","business_date":"2026-04-17","department":"hall","staff_key":"은성","hours":6,"tip_eligible":true,"tip_override":113.1591},{"branch":"downtown","business_date":"2026-04-20","department":"hall","staff_key":"은성","hours":10,"tip_eligible":true,"tip_override":73.2929},{"branch":"downtown","business_date":"2026-04-21","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":107.8272},{"branch":"downtown","business_date":"2026-04-25","department":"hall","staff_key":"은성","hours":10,"tip_eligible":true,"tip_override":179.0529},{"branch":"downtown","business_date":"2026-04-27","department":"hall","staff_key":"은성","hours":10,"tip_eligible":true,"tip_override":42.1489},{"branch":"downtown","business_date":"2026-04-28","department":"hall","staff_key":"은성","hours":10,"tip_eligible":true,"tip_override":82.4834},{"branch":"downtown","business_date":"2026-04-30","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":69.0455},{"branch":"downtown","business_date":"2026-05-07","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":78.9532},{"branch":"downtown","business_date":"2026-05-10","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":73.303},{"branch":"downtown","business_date":"2026-05-13","department":"hall","staff_key":"은성","hours":9,"tip_eligible":true,"tip_override":46.6606},{"branch":"downtown","business_date":"2026-05-17","department":"hall","staff_key":"은성","hours":10,"tip_eligible":true,"tip_override":147.2048},{"branch":"downtown","business_date":"2026-05-18","department":"hall","staff_key":"은성","hours":10,"tip_eligible":true,"tip_override":74.3571},{"branch":"downtown","business_date":"2026-05-21","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":100.3559},{"branch":"downtown","business_date":"2026-05-26","department":"hall","staff_key":"은성","hours":10,"tip_eligible":true,"tip_override":82.0102},{"branch":"downtown","business_date":"2026-05-28","department":"hall","staff_key":"은성","hours":9,"tip_eligible":true,"tip_override":39.3432},{"branch":"downtown","business_date":"2026-06-03","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":51.9611},{"branch":"downtown","business_date":"2026-06-04","department":"hall","staff_key":"은성","hours":10,"tip_eligible":true,"tip_override":44.6317},{"branch":"downtown","business_date":"2026-06-07","department":"hall","staff_key":"은성","hours":9,"tip_eligible":true,"tip_override":79.0096},{"branch":"downtown","business_date":"2026-06-08","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":56.1429},{"branch":"downtown","business_date":"2026-06-10","department":"hall","staff_key":"은성","hours":9,"tip_eligible":true,"tip_override":37.3393},{"branch":"downtown","business_date":"2026-06-13","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":109.1185},{"branch":"downtown","business_date":"2026-06-16","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":44.8556},{"branch":"downtown","business_date":"2026-06-17","department":"hall","staff_key":"은성","hours":9,"tip_eligible":true,"tip_override":62.4677},{"branch":"downtown","business_date":"2026-06-19","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":119.9181},{"branch":"downtown","business_date":"2026-06-21","department":"hall","staff_key":"은성","hours":8.5,"tip_eligible":true,"tip_override":28.7194},{"branch":"downtown","business_date":"2026-06-23","department":"hall","staff_key":"은성","hours":8.5,"tip_eligible":true,"tip_override":44.0576},{"branch":"downtown","business_date":"2026-06-24","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":116.8484},{"branch":"downtown","business_date":"2026-06-27","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":131.1048},{"branch":"downtown","business_date":"2026-06-29","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":68.1803},{"branch":"downtown","business_date":"2026-07-01","department":"hall","staff_key":"은성","hours":10.5,"tip_eligible":true,"tip_override":116.2991},{"branch":"downtown","business_date":"2026-07-05","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":112.369},{"branch":"downtown","business_date":"2026-07-07","department":"hall","staff_key":"은성","hours":8.5,"tip_eligible":true,"tip_override":74.7099},{"branch":"downtown","business_date":"2026-07-09","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":68.2556},{"branch":"downtown","business_date":"2026-07-12","department":"hall","staff_key":"은성","hours":10,"tip_eligible":true,"tip_override":122.4682},{"branch":"downtown","business_date":"2026-07-13","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":81.5133},{"branch":"downtown","business_date":"2026-07-14","department":"hall","staff_key":"은성","hours":9.5,"tip_eligible":true,"tip_override":115.66},{"branch":"downtown","business_date":"2026-07-15","department":"hall","staff_key":"은성","hours":10,"tip_eligible":true,"tip_override":57.3581},{"branch":"downtown","business_date":"2026-01-01","department":"hall","staff_key":"혜지","hours":8,"tip_eligible":true,"tip_override":38.2201},{"branch":"downtown","business_date":"2026-01-03","department":"hall","staff_key":"혜지","hours":6,"tip_eligible":true,"tip_override":56.5624},{"branch":"downtown","business_date":"2026-01-04","department":"hall","staff_key":"혜지","hours":6.5,"tip_eligible":true,"tip_override":69.5265},{"branch":"downtown","business_date":"2026-01-06","department":"hall","staff_key":"혜지","hours":6,"tip_eligible":true,"tip_override":61.7753},{"branch":"downtown","business_date":"2026-01-07","department":"hall","staff_key":"혜지","hours":6,"tip_eligible":true,"tip_override":26.2846},{"branch":"downtown","business_date":"2026-01-12","department":"hall","staff_key":"혜지","hours":6,"tip_eligible":true,"tip_override":63.8968},{"branch":"downtown","business_date":"2026-01-17","department":"hall","staff_key":"혜지","hours":8,"tip_eligible":true,"tip_override":103.0117},{"branch":"downtown","business_date":"2026-01-18","department":"hall","staff_key":"혜지","hours":6,"tip_eligible":true,"tip_override":51.4899},{"branch":"downtown","business_date":"2026-01-21","department":"hall","staff_key":"혜지","hours":9.5,"tip_eligible":true,"tip_override":132.1182},{"branch":"downtown","business_date":"2026-01-23","department":"hall","staff_key":"혜지","hours":6,"tip_eligible":true,"tip_override":118.6916},{"branch":"downtown","business_date":"2026-01-28","department":"hall","staff_key":"혜지","hours":4.5,"tip_eligible":true,"tip_override":34.1067},{"branch":"downtown","business_date":"2026-01-29","department":"hall","staff_key":"혜지","hours":6,"tip_eligible":true,"tip_override":73.1921},{"branch":"downtown","business_date":"2026-01-30","department":"hall","staff_key":"혜지","hours":9,"tip_eligible":true,"tip_override":150.0898},{"branch":"downtown","business_date":"2026-02-04","department":"hall","staff_key":"혜지","hours":1,"tip_eligible":true,"tip_override":8.8055},{"branch":"downtown","business_date":"2026-02-05","department":"hall","staff_key":"혜지","hours":9,"tip_eligible":true,"tip_override":128.7349},{"branch":"downtown","business_date":"2026-02-06","department":"hall","staff_key":"혜지","hours":8.5,"tip_eligible":true,"tip_override":109.7739},{"branch":"downtown","business_date":"2026-02-08","department":"hall","staff_key":"혜지","hours":8,"tip_eligible":true,"tip_override":57.1245},{"branch":"downtown","business_date":"2026-02-11","department":"hall","staff_key":"혜지","hours":5,"tip_eligible":true,"tip_override":41.6333},{"branch":"downtown","business_date":"2026-02-12","department":"hall","staff_key":"혜지","hours":9,"tip_eligible":true,"tip_override":78.6288},{"branch":"downtown","business_date":"2026-02-14","department":"hall","staff_key":"혜지","hours":9,"tip_eligible":true,"tip_override":146.5442},{"branch":"downtown","business_date":"2026-02-18","department":"hall","staff_key":"혜지","hours":4,"tip_eligible":true,"tip_override":25.4766},{"branch":"downtown","business_date":"2026-02-19","department":"hall","staff_key":"혜지","hours":9,"tip_eligible":true,"tip_override":82.6256},{"branch":"downtown","business_date":"2026-02-21","department":"hall","staff_key":"혜지","hours":6,"tip_eligible":true,"tip_override":83.9953},{"branch":"downtown","business_date":"2026-02-25","department":"hall","staff_key":"혜지","hours":5.5,"tip_eligible":true,"tip_override":58.6551},{"branch":"downtown","business_date":"2026-02-26","department":"hall","staff_key":"혜지","hours":9.5,"tip_eligible":true,"tip_override":76.6539},{"branch":"downtown","business_date":"2026-02-27","department":"hall","staff_key":"혜지","hours":9,"tip_eligible":true,"tip_override":163.2794},{"branch":"downtown","business_date":"2026-03-05","department":"hall","staff_key":"혜지","hours":9,"tip_eligible":true,"tip_override":66.575},{"branch":"downtown","business_date":"2026-03-07","department":"hall","staff_key":"혜지","hours":5.5,"tip_eligible":true,"tip_override":75.4858},{"branch":"downtown","business_date":"2026-03-08","department":"hall","staff_key":"혜지","hours":6,"tip_eligible":true,"tip_override":43.1658},{"branch":"downtown","business_date":"2026-03-11","department":"hall","staff_key":"혜지","hours":5,"tip_eligible":true,"tip_override":46.973},{"branch":"downtown","business_date":"2026-03-12","department":"hall","staff_key":"혜지","hours":9.5,"tip_eligible":true,"tip_override":66.0559},{"branch":"downtown","business_date":"2026-03-13","department":"hall","staff_key":"혜지","hours":6,"tip_eligible":true,"tip_override":56.547},{"branch":"downtown","business_date":"2026-03-18","department":"hall","staff_key":"혜지","hours":1,"tip_eligible":true,"tip_override":4.9957},{"branch":"downtown","business_date":"2026-03-19","department":"hall","staff_key":"혜지","hours":3.5,"tip_eligible":true,"tip_override":37.345},{"branch":"downtown","business_date":"2026-03-20","department":"hall","staff_key":"혜지","hours":10,"tip_eligible":true,"tip_override":184.518},{"branch":"downtown","business_date":"2026-03-25","department":"hall","staff_key":"혜지","hours":5.5,"tip_eligible":true,"tip_override":33.2612},{"branch":"downtown","business_date":"2026-03-26","department":"hall","staff_key":"혜지","hours":9.5,"tip_eligible":true,"tip_override":50.8074},{"branch":"downtown","business_date":"2026-03-29","department":"hall","staff_key":"혜지","hours":6.5,"tip_eligible":true,"tip_override":101.7674},{"branch":"downtown","business_date":"2026-04-01","department":"hall","staff_key":"혜지","hours":6,"tip_eligible":true,"tip_override":39.2387},{"branch":"downtown","business_date":"2026-04-03","department":"hall","staff_key":"혜지","hours":5,"tip_eligible":true,"tip_override":71.8607},{"branch":"downtown","business_date":"2026-04-05","department":"hall","staff_key":"혜지","hours":6,"tip_eligible":true,"tip_override":70.4043},{"branch":"downtown","business_date":"2026-04-06","department":"hall","staff_key":"혜지","hours":9.5,"tip_eligible":true,"tip_override":126.4615},{"branch":"downtown","business_date":"2026-04-10","department":"hall","staff_key":"혜지","hours":4,"tip_eligible":true,"tip_override":65.6781},{"branch":"downtown","business_date":"2026-01-08","department":"hall","staff_key":"예림","hours":7.5,"tip_eligible":true,"tip_override":37.7613},{"branch":"downtown","business_date":"2026-01-09","department":"hall","staff_key":"예림","hours":7,"tip_eligible":true,"tip_override":124.723},{"branch":"downtown","business_date":"2026-01-14","department":"hall","staff_key":"예림","hours":6.5,"tip_eligible":true,"tip_override":58.012},{"branch":"downtown","business_date":"2026-01-15","department":"hall","staff_key":"예림","hours":9,"tip_eligible":true,"tip_override":123.3036},{"branch":"downtown","business_date":"2026-01-16","department":"hall","staff_key":"예림","hours":6.5,"tip_eligible":true,"tip_override":105.2801},{"branch":"downtown","business_date":"2026-01-17","department":"hall","staff_key":"예림","hours":7.5,"tip_eligible":true,"tip_override":96.5735},{"branch":"downtown","business_date":"2026-01-21","department":"hall","staff_key":"예림","hours":6.5,"tip_eligible":true,"tip_override":90.3966},{"branch":"downtown","business_date":"2026-01-22","department":"hall","staff_key":"예림","hours":8.5,"tip_eligible":true,"tip_override":65.8112},{"branch":"downtown","business_date":"2026-01-24","department":"hall","staff_key":"예림","hours":9,"tip_eligible":true,"tip_override":118.2981},{"branch":"downtown","business_date":"2026-01-28","department":"hall","staff_key":"예림","hours":5.5,"tip_eligible":true,"tip_override":41.6859},{"branch":"downtown","business_date":"2026-01-30","department":"hall","staff_key":"예림","hours":9,"tip_eligible":true,"tip_override":150.0898},{"branch":"downtown","business_date":"2026-02-01","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":75.9647},{"branch":"downtown","business_date":"2026-02-04","department":"hall","staff_key":"예림","hours":9,"tip_eligible":true,"tip_override":79.2493},{"branch":"downtown","business_date":"2026-02-07","department":"hall","staff_key":"예림","hours":10.5,"tip_eligible":true,"tip_override":88.5778},{"branch":"downtown","business_date":"2026-02-08","department":"hall","staff_key":"예림","hours":1,"tip_eligible":true,"tip_override":7.1406},{"branch":"downtown","business_date":"2026-02-09","department":"hall","staff_key":"예림","hours":9,"tip_eligible":true,"tip_override":115.3435},{"branch":"downtown","business_date":"2026-02-11","department":"hall","staff_key":"예림","hours":5,"tip_eligible":true,"tip_override":41.6333},{"branch":"downtown","business_date":"2026-02-12","department":"hall","staff_key":"예림","hours":6,"tip_eligible":true,"tip_override":52.4192},{"branch":"downtown","business_date":"2026-02-14","department":"hall","staff_key":"예림","hours":9,"tip_eligible":true,"tip_override":146.5442},{"branch":"downtown","business_date":"2026-02-16","department":"hall","staff_key":"예림","hours":9,"tip_eligible":true,"tip_override":88.9835},{"branch":"downtown","business_date":"2026-02-19","department":"hall","staff_key":"예림","hours":9,"tip_eligible":true,"tip_override":82.6256},{"branch":"downtown","business_date":"2026-02-21","department":"hall","staff_key":"예림","hours":9,"tip_eligible":true,"tip_override":125.9929},{"branch":"downtown","business_date":"2026-02-22","department":"hall","staff_key":"예림","hours":5.5,"tip_eligible":true,"tip_override":51.0394},{"branch":"downtown","business_date":"2026-02-25","department":"hall","staff_key":"예림","hours":8.5,"tip_eligible":true,"tip_override":90.6489},{"branch":"downtown","business_date":"2026-02-28","department":"hall","staff_key":"예림","hours":6,"tip_eligible":true,"tip_override":69.3149},{"branch":"downtown","business_date":"2026-03-01","department":"hall","staff_key":"예림","hours":5.5,"tip_eligible":true,"tip_override":34.8604},{"branch":"downtown","business_date":"2026-03-04","department":"hall","staff_key":"예림","hours":8,"tip_eligible":true,"tip_override":70.6322},{"branch":"downtown","business_date":"2026-03-05","department":"hall","staff_key":"예림","hours":5.5,"tip_eligible":true,"tip_override":40.6847},{"branch":"downtown","business_date":"2026-03-06","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":144.8184},{"branch":"downtown","business_date":"2026-03-12","department":"hall","staff_key":"예림","hours":6,"tip_eligible":true,"tip_override":41.7195},{"branch":"downtown","business_date":"2026-03-14","department":"hall","staff_key":"예림","hours":10,"tip_eligible":true,"tip_override":187.1305},{"branch":"downtown","business_date":"2026-03-15","department":"hall","staff_key":"예림","hours":9,"tip_eligible":true,"tip_override":93.9967},{"branch":"downtown","business_date":"2026-03-19","department":"hall","staff_key":"예림","hours":6,"tip_eligible":true,"tip_override":64.0201},{"branch":"downtown","business_date":"2026-03-20","department":"hall","staff_key":"예림","hours":10,"tip_eligible":true,"tip_override":184.518},{"branch":"downtown","business_date":"2026-03-21","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":136.132},{"branch":"downtown","business_date":"2026-03-22","department":"hall","staff_key":"예림","hours":8.5,"tip_eligible":true,"tip_override":180.2391},{"branch":"downtown","business_date":"2026-03-25","department":"hall","staff_key":"예림","hours":9,"tip_eligible":true,"tip_override":54.4274},{"branch":"downtown","business_date":"2026-03-26","department":"hall","staff_key":"예림","hours":6,"tip_eligible":true,"tip_override":32.0889},{"branch":"downtown","business_date":"2026-03-27","department":"hall","staff_key":"예림","hours":6,"tip_eligible":true,"tip_override":101.2794},{"branch":"downtown","business_date":"2026-03-28","department":"hall","staff_key":"예림","hours":10.5,"tip_eligible":true,"tip_override":184.9675},{"branch":"downtown","business_date":"2026-04-01","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":62.128},{"branch":"downtown","business_date":"2026-04-02","department":"hall","staff_key":"예림","hours":10,"tip_eligible":true,"tip_override":185.8156},{"branch":"downtown","business_date":"2026-04-03","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":136.5353},{"branch":"downtown","business_date":"2026-04-08","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":78.2724},{"branch":"downtown","business_date":"2026-04-10","department":"hall","staff_key":"예림","hours":7.5,"tip_eligible":true,"tip_override":123.1464},{"branch":"downtown","business_date":"2026-04-12","department":"hall","staff_key":"예림","hours":6.5,"tip_eligible":true,"tip_override":77.8889},{"branch":"downtown","business_date":"2026-04-15","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":101.6256},{"branch":"downtown","business_date":"2026-04-17","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":179.1686},{"branch":"downtown","business_date":"2026-04-22","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":57.3808},{"branch":"downtown","business_date":"2026-04-24","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":149.3078},{"branch":"downtown","business_date":"2026-04-29","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":28.1509},{"branch":"downtown","business_date":"2026-05-01","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":90.1125},{"branch":"downtown","business_date":"2026-05-08","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":188.9762},{"branch":"downtown","business_date":"2026-05-14","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":71.885},{"branch":"downtown","business_date":"2026-05-15","department":"hall","staff_key":"예림","hours":8.5,"tip_eligible":true,"tip_override":97.3034},{"branch":"downtown","business_date":"2026-05-21","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":100.3559},{"branch":"downtown","business_date":"2026-05-22","department":"hall","staff_key":"예림","hours":10,"tip_eligible":true,"tip_override":211.3949},{"branch":"downtown","business_date":"2026-05-25","department":"hall","staff_key":"예림","hours":10,"tip_eligible":true,"tip_override":100.022},{"branch":"downtown","business_date":"2026-05-29","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":90.4838},{"branch":"downtown","business_date":"2026-06-01","department":"hall","staff_key":"예림","hours":9,"tip_eligible":true,"tip_override":36.8646},{"branch":"downtown","business_date":"2026-06-05","department":"hall","staff_key":"예림","hours":9,"tip_eligible":true,"tip_override":123.8808},{"branch":"downtown","business_date":"2026-06-08","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":56.1429},{"branch":"downtown","business_date":"2026-06-12","department":"hall","staff_key":"예림","hours":10.5,"tip_eligible":true,"tip_override":99.8986},{"branch":"downtown","business_date":"2026-06-15","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":97.0168},{"branch":"downtown","business_date":"2026-06-19","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":119.9181},{"branch":"downtown","business_date":"2026-06-20","department":"hall","staff_key":"예림","hours":9,"tip_eligible":true,"tip_override":103.4176},{"branch":"downtown","business_date":"2026-06-22","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":69.1807},{"branch":"downtown","business_date":"2026-06-26","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":145.1227},{"branch":"downtown","business_date":"2026-06-29","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":68.1803},{"branch":"downtown","business_date":"2026-07-03","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":109.3563},{"branch":"downtown","business_date":"2026-07-06","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":49.7307},{"branch":"downtown","business_date":"2026-07-10","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":137.9684},{"branch":"downtown","business_date":"2026-07-13","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":81.5133},{"branch":"downtown","business_date":"2026-07-17","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":140.6893},{"branch":"downtown","business_date":"2026-07-20","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":86.1972},{"branch":"downtown","business_date":"2026-07-24","department":"hall","staff_key":"예림","hours":10,"tip_eligible":true,"tip_override":150.6884},{"branch":"downtown","business_date":"2026-07-27","department":"hall","staff_key":"예림","hours":9.5,"tip_eligible":true,"tip_override":72.4711},{"branch":"downtown","business_date":"2026-04-06","department":"hall","staff_key":"수현","hours":6,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-04-08","department":"hall","staff_key":"수현","hours":6,"tip_eligible":true,"tip_override":49.4352},{"branch":"downtown","business_date":"2026-04-16","department":"hall","staff_key":"수현","hours":5.5,"tip_eligible":true,"tip_override":42.6085},{"branch":"downtown","business_date":"2026-04-19","department":"hall","staff_key":"수현","hours":3.5,"tip_eligible":true,"tip_override":57.3247},{"branch":"downtown","business_date":"2026-04-07","department":"hall","staff_key":"민영","hours":6,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-04-09","department":"hall","staff_key":"민영","hours":5.5,"tip_eligible":true,"tip_override":31.085},{"branch":"downtown","business_date":"2026-04-15","department":"hall","staff_key":"민영","hours":6,"tip_eligible":true,"tip_override":64.1846},{"branch":"downtown","business_date":"2026-04-18","department":"hall","staff_key":"민영","hours":9.5,"tip_eligible":true,"tip_override":105.5541},{"branch":"downtown","business_date":"2026-04-20","department":"hall","staff_key":"민영","hours":10,"tip_eligible":true,"tip_override":73.2929},{"branch":"downtown","business_date":"2026-04-22","department":"hall","staff_key":"민영","hours":9.5,"tip_eligible":true,"tip_override":57.3808},{"branch":"downtown","business_date":"2026-04-26","department":"hall","staff_key":"민영","hours":9.5,"tip_eligible":true,"tip_override":126.0455},{"branch":"downtown","business_date":"2026-04-29","department":"hall","staff_key":"민영","hours":9.5,"tip_eligible":true,"tip_override":28.1509},{"branch":"downtown","business_date":"2026-05-02","department":"hall","staff_key":"민영","hours":8,"tip_eligible":true,"tip_override":72.5295},{"branch":"downtown","business_date":"2026-05-04","department":"hall","staff_key":"민영","hours":9.5,"tip_eligible":true,"tip_override":37.0522},{"branch":"downtown","business_date":"2026-05-07","department":"hall","staff_key":"민영","hours":9.5,"tip_eligible":true,"tip_override":78.9532},{"branch":"downtown","business_date":"2026-05-13","department":"hall","staff_key":"민영","hours":9,"tip_eligible":true,"tip_override":46.6606},{"branch":"downtown","business_date":"2026-05-16","department":"hall","staff_key":"민영","hours":9.5,"tip_eligible":true,"tip_override":95.12},{"branch":"downtown","business_date":"2026-05-23","department":"hall","staff_key":"민영","hours":8.5,"tip_eligible":true,"tip_override":50.2288},{"branch":"downtown","business_date":"2026-05-24","department":"hall","staff_key":"민영","hours":9.5,"tip_eligible":true,"tip_override":47.0402},{"branch":"downtown","business_date":"2026-04-23","department":"hall","staff_key":"제윤","hours":10,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-04-25","department":"hall","staff_key":"제윤","hours":10,"tip_eligible":true,"tip_override":71.62},{"branch":"downtown","business_date":"2026-04-27","department":"hall","staff_key":"제윤","hours":10,"tip_eligible":true,"tip_override":42.1489},{"branch":"downtown","business_date":"2026-05-01","department":"hall","staff_key":"제윤","hours":9.5,"tip_eligible":true,"tip_override":90.1125},{"branch":"downtown","business_date":"2026-05-04","department":"hall","staff_key":"제윤","hours":9.5,"tip_eligible":true,"tip_override":37.0522},{"branch":"downtown","business_date":"2026-05-09","department":"hall","staff_key":"제윤","hours":9.5,"tip_eligible":true,"tip_override":69.6889},{"branch":"downtown","business_date":"2026-05-10","department":"hall","staff_key":"제윤","hours":9.5,"tip_eligible":true,"tip_override":73.303},{"branch":"downtown","business_date":"2026-05-12","department":"hall","staff_key":"제윤","hours":9.5,"tip_eligible":true,"tip_override":59.4189},{"branch":"downtown","business_date":"2026-05-15","department":"hall","staff_key":"제윤","hours":8,"tip_eligible":true,"tip_override":91.5797},{"branch":"downtown","business_date":"2026-05-17","department":"hall","staff_key":"제윤","hours":10,"tip_eligible":true,"tip_override":147.2048},{"branch":"downtown","business_date":"2026-05-23","department":"hall","staff_key":"제윤","hours":8.5,"tip_eligible":true,"tip_override":50.2288},{"branch":"downtown","business_date":"2026-05-24","department":"hall","staff_key":"제윤","hours":9.5,"tip_eligible":true,"tip_override":47.0402},{"branch":"downtown","business_date":"2026-05-25","department":"hall","staff_key":"제윤","hours":10,"tip_eligible":true,"tip_override":100.022},{"branch":"downtown","business_date":"2026-05-30","department":"hall","staff_key":"제윤","hours":9.5,"tip_eligible":true,"tip_override":138.5625},{"branch":"downtown","business_date":"2026-05-31","department":"hall","staff_key":"제윤","hours":10,"tip_eligible":true,"tip_override":107.3557},{"branch":"downtown","business_date":"2026-06-01","department":"hall","staff_key":"제윤","hours":9,"tip_eligible":true,"tip_override":36.8646},{"branch":"downtown","business_date":"2026-06-02","department":"hall","staff_key":"제윤","hours":10,"tip_eligible":true,"tip_override":75.0934},{"branch":"downtown","business_date":"2026-06-05","department":"hall","staff_key":"제윤","hours":9,"tip_eligible":true,"tip_override":123.8808},{"branch":"downtown","business_date":"2026-06-09","department":"hall","staff_key":"제윤","hours":9.5,"tip_eligible":true,"tip_override":74.729},{"branch":"downtown","business_date":"2026-06-10","department":"hall","staff_key":"제윤","hours":9,"tip_eligible":true,"tip_override":37.3393},{"branch":"downtown","business_date":"2026-06-12","department":"hall","staff_key":"제윤","hours":10.5,"tip_eligible":true,"tip_override":99.8986},{"branch":"downtown","business_date":"2026-06-20","department":"hall","staff_key":"제윤","hours":10.5,"tip_eligible":true,"tip_override":120.6539},{"branch":"downtown","business_date":"2026-06-28","department":"hall","staff_key":"제윤","hours":9.5,"tip_eligible":true,"tip_override":126.8887},{"branch":"downtown","business_date":"2026-07-02","department":"hall","staff_key":"제윤","hours":10,"tip_eligible":true,"tip_override":74.1162},{"branch":"downtown","business_date":"2026-07-05","department":"hall","staff_key":"제윤","hours":9.5,"tip_eligible":true,"tip_override":112.369},{"branch":"downtown","business_date":"2026-07-06","department":"hall","staff_key":"제윤","hours":9.5,"tip_eligible":true,"tip_override":49.7307},{"branch":"downtown","business_date":"2026-07-12","department":"hall","staff_key":"제윤","hours":9.5,"tip_eligible":true,"tip_override":116.3448},{"branch":"downtown","business_date":"2026-07-23","department":"hall","staff_key":"제윤","hours":9.5,"tip_eligible":true,"tip_override":67.9789},{"branch":"downtown","business_date":"2026-07-26","department":"hall","staff_key":"제윤","hours":8.5,"tip_eligible":true,"tip_override":63.8888},{"branch":"downtown","business_date":"2026-04-28","department":"hall","staff_key":"주은","hours":10,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-05-03","department":"hall","staff_key":"주은","hours":9.5,"tip_eligible":true,"tip_override":106.0321},{"branch":"downtown","business_date":"2026-05-05","department":"hall","staff_key":"주은","hours":9.5,"tip_eligible":true,"tip_override":44.1649},{"branch":"downtown","business_date":"2026-05-09","department":"hall","staff_key":"주은","hours":9.5,"tip_eligible":true,"tip_override":69.6889},{"branch":"downtown","business_date":"2026-05-14","department":"hall","staff_key":"주은","hours":9.5,"tip_eligible":true,"tip_override":71.885},{"branch":"downtown","business_date":"2026-05-16","department":"hall","staff_key":"주은","hours":9.5,"tip_eligible":true,"tip_override":95.12},{"branch":"downtown","business_date":"2026-05-18","department":"hall","staff_key":"주은","hours":10,"tip_eligible":true,"tip_override":74.3571},{"branch":"downtown","business_date":"2026-05-19","department":"hall","staff_key":"주은","hours":8.5,"tip_eligible":true,"tip_override":35.8034},{"branch":"downtown","business_date":"2026-05-20","department":"hall","staff_key":"주은","hours":4.5,"tip_eligible":true,"tip_override":16.1372},{"branch":"downtown","business_date":"2026-05-27","department":"hall","staff_key":"주은","hours":9.5,"tip_eligible":true,"tip_override":83.9488},{"branch":"downtown","business_date":"2026-05-28","department":"hall","staff_key":"주은","hours":9,"tip_eligible":true,"tip_override":39.3432},{"branch":"downtown","business_date":"2026-05-31","department":"hall","staff_key":"주은","hours":10,"tip_eligible":true,"tip_override":107.3557},{"branch":"downtown","business_date":"2026-06-04","department":"hall","staff_key":"주은","hours":10,"tip_eligible":true,"tip_override":44.6317},{"branch":"downtown","business_date":"2026-06-06","department":"hall","staff_key":"주은","hours":10,"tip_eligible":true,"tip_override":146.9895},{"branch":"downtown","business_date":"2026-06-09","department":"hall","staff_key":"주은","hours":9.5,"tip_eligible":true,"tip_override":74.729},{"branch":"downtown","business_date":"2026-06-11","department":"hall","staff_key":"주은","hours":10.5,"tip_eligible":true,"tip_override":170.6404},{"branch":"downtown","business_date":"2026-06-15","department":"hall","staff_key":"주은","hours":5.5,"tip_eligible":true,"tip_override":56.1676},{"branch":"downtown","business_date":"2026-06-16","department":"hall","staff_key":"주은","hours":9.5,"tip_eligible":true,"tip_override":44.8556},{"branch":"downtown","business_date":"2026-06-19","department":"hall","staff_key":"주은","hours":9.5,"tip_eligible":true,"tip_override":119.9181},{"branch":"downtown","business_date":"2026-06-25","department":"hall","staff_key":"주은","hours":9,"tip_eligible":true,"tip_override":101.9704},{"branch":"downtown","business_date":"2026-06-26","department":"hall","staff_key":"주은","hours":8.5,"tip_eligible":true,"tip_override":129.8466},{"branch":"downtown","business_date":"2026-06-30","department":"hall","staff_key":"주은","hours":9.5,"tip_eligible":true,"tip_override":111.8353},{"branch":"downtown","business_date":"2026-07-03","department":"hall","staff_key":"주은","hours":6,"tip_eligible":true,"tip_override":69.0671},{"branch":"downtown","business_date":"2026-07-10","department":"hall","staff_key":"주은","hours":9.5,"tip_eligible":true,"tip_override":137.9684},{"branch":"downtown","business_date":"2026-05-26","department":"hall","staff_key":"소정","hours":6.5,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-05-30","department":"hall","staff_key":"소정","hours":9.5,"tip_eligible":true,"tip_override":55.425},{"branch":"downtown","business_date":"2026-06-03","department":"hall","staff_key":"소정","hours":9.5,"tip_eligible":true,"tip_override":51.9611},{"branch":"downtown","business_date":"2026-06-06","department":"hall","staff_key":"소정","hours":7.5,"tip_eligible":true,"tip_override":110.2421},{"branch":"downtown","business_date":"2026-06-13","department":"hall","staff_key":"소정","hours":9.5,"tip_eligible":true,"tip_override":109.1185},{"branch":"downtown","business_date":"2026-06-14","department":"hall","staff_key":"소정","hours":8.5,"tip_eligible":true,"tip_override":41.7023},{"branch":"downtown","business_date":"2026-06-18","department":"hall","staff_key":"소정","hours":9.5,"tip_eligible":true,"tip_override":153.128},{"branch":"downtown","business_date":"2026-06-20","department":"hall","staff_key":"소정","hours":8.5,"tip_eligible":true,"tip_override":97.6722},{"branch":"downtown","business_date":"2026-06-23","department":"hall","staff_key":"소정","hours":4.5,"tip_eligible":true,"tip_override":23.3246},{"branch":"downtown","business_date":"2026-06-24","department":"hall","staff_key":"소정","hours":9.5,"tip_eligible":true,"tip_override":116.8484},{"branch":"downtown","business_date":"2026-06-27","department":"hall","staff_key":"소정","hours":9.5,"tip_eligible":true,"tip_override":131.1048},{"branch":"downtown","business_date":"2026-07-01","department":"hall","staff_key":"소정","hours":10.5,"tip_eligible":true,"tip_override":116.2991},{"branch":"downtown","business_date":"2026-07-04","department":"hall","staff_key":"소정","hours":9.5,"tip_eligible":true,"tip_override":97.4297},{"branch":"downtown","business_date":"2026-07-08","department":"hall","staff_key":"소정","hours":9.5,"tip_eligible":true,"tip_override":60.2119},{"branch":"downtown","business_date":"2026-07-09","department":"hall","staff_key":"소정","hours":9.5,"tip_eligible":true,"tip_override":68.2556},{"branch":"downtown","business_date":"2026-07-11","department":"hall","staff_key":"소정","hours":9.5,"tip_eligible":true,"tip_override":82.5723},{"branch":"downtown","business_date":"2026-07-15","department":"hall","staff_key":"소정","hours":10,"tip_eligible":true,"tip_override":57.3581},{"branch":"downtown","business_date":"2026-07-17","department":"hall","staff_key":"소정","hours":2.5,"tip_eligible":true,"tip_override":37.0235},{"branch":"downtown","business_date":"2026-07-18","department":"hall","staff_key":"소정","hours":9.5,"tip_eligible":true,"tip_override":168.1643},{"branch":"downtown","business_date":"2026-07-21","department":"hall","staff_key":"소정","hours":9.5,"tip_eligible":true,"tip_override":65.2531},{"branch":"downtown","business_date":"2026-07-22","department":"hall","staff_key":"소정","hours":9.5,"tip_eligible":true,"tip_override":127.7996},{"branch":"downtown","business_date":"2026-07-24","department":"hall","staff_key":"소정","hours":8,"tip_eligible":true,"tip_override":120.5507},{"branch":"downtown","business_date":"2026-07-25","department":"hall","staff_key":"소정","hours":10.5,"tip_eligible":true,"tip_override":139.1662},{"branch":"downtown","business_date":"2026-07-28","department":"hall","staff_key":"소정","hours":8,"tip_eligible":true,"tip_override":51.857},{"branch":"downtown","business_date":"2026-07-29","department":"hall","staff_key":"소정","hours":6.5,"tip_eligible":true,"tip_override":95.7648},{"branch":"downtown","business_date":"2026-07-14","department":"hall","staff_key":"지민","hours":8,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-07-27","department":"hall","staff_key":"이준서","hours":9.5,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-04-21","department":"hall","staff_key":"민재","hours":9.5,"tip_eligible":false,"tip_override":0},{"branch":"downtown","business_date":"2026-05-02","department":"hall","staff_key":"민재","hours":8,"tip_eligible":true,"tip_override":29.01},{"branch":"downtown","business_date":"2026-05-06","department":"hall","staff_key":"민재","hours":9.5,"tip_eligible":true,"tip_override":63.1829},{"branch":"downtown","business_date":"2026-05-08","department":"hall","staff_key":"민재","hours":9.5,"tip_eligible":true,"tip_override":188.9762},{"branch":"downtown","business_date":"2026-05-11","department":"hall","staff_key":"민재","hours":10,"tip_eligible":true,"tip_override":91.3321}]$entries$::jsonb
) as x(
  branch text,
  business_date date,
  department text,
  staff_key text,
  hours numeric,
  tip_eligible boolean,
  tip_override numeric
)
join settlement.daily_entries d
  on d.branch = x.branch
 and d.business_date = x.business_date
join settlement.staff_members sm
  on sm.branch = x.branch
 and sm.department = x.department
 and sm.staff_key = x.staff_key
on conflict (daily_entry_id, staff_id)
do update set
  hours = excluded.hours,
  tip_eligible = excluded.tip_eligible,
  tip_adjustment = excluded.tip_adjustment,
  tip_override = excluded.tip_override;

commit;
