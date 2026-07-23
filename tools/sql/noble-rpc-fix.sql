-- RPC fix for the classified schema setup.
-- Run this in Supabase SQL Editor after the tables are under:
-- staff.noble_access_requests and schedule.staff_availability / schedule.schedule_*.

create or replace function public.noble_submit_access_request_v2(
  p_name text,
  p_branch_scope text,
  p_smart_server_number text
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

  insert into staff.noble_access_requests (name, branch_scope, smart_server_number)
  values (trim(p_name), normalized_branch, trim(p_smart_server_number))
  returning id into new_id;

  return new_id;
end;
$$;

create or replace function public.noble_submit_availability_v2(
  input_ref text,
  p_unavailable_dates jsonb default '[]'::jsonb,
  p_preferred_dates jsonb default '[]'::jsonb,
  p_date_details jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, schedule
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

  delete from schedule.staff_availability
  where staff_key = employee.staff_key;

  for item_date in
    select value::date from jsonb_array_elements_text(coalesce(p_unavailable_dates, '[]'::jsonb))
  loop
    insert into schedule.staff_availability (
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

  for item_date in
    select value::date from jsonb_array_elements_text(coalesce(p_preferred_dates, '[]'::jsonb))
  loop
    insert into schedule.staff_availability (
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
      delete from schedule.staff_availability
      where staff_key = employee.staff_key
        and availability_date = item_date;
      continue;
    end if;

    insert into schedule.staff_availability (
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
set search_path = public, schedule
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
  from schedule.schedule_weeks w
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
    from schedule.schedule_shifts s
    join schedule.schedule_weeks w on w.id = s.week_id
    where w.week_start = latest_week
      and w.status = 'published'
    order by s.branch, s.shift_date, s.sort_order, s.staff_name;
end;
$$;

revoke all on function public.noble_submit_access_request_v2(text, text, text) from public;
grant execute on function public.noble_submit_access_request_v2(text, text, text) to anon, authenticated;

revoke all on function public.noble_submit_availability_v2(text, jsonb, jsonb, jsonb) from public;
grant execute on function public.noble_submit_availability_v2(text, jsonb, jsonb, jsonb) to anon, authenticated;

revoke all on function public.noble_get_latest_schedule(text) from public;
grant execute on function public.noble_get_latest_schedule(text) to anon, authenticated;
