-- Preserve an explicit per-date "default/available" choice so it can override
-- a recurring fixed unavailable/preferred weekday in King.

create or replace function public.noble_submit_availability_v2(
  input_ref text,
  p_unavailable_dates jsonb default '[]'::jsonb,
  p_preferred_dates jsonb default '[]'::jsonb,
  p_date_details jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
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
    select value::date
    from jsonb_array_elements_text(coalesce(p_unavailable_dates, '[]'::jsonb))
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
    select value::date
    from jsonb_array_elements_text(coalesce(p_preferred_dates, '[]'::jsonb))
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
    select key, value
    from jsonb_each(coalesce(p_date_details, '{}'::jsonb))
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

    -- A default row is intentionally kept: it means this particular date was
    -- explicitly changed to available and therefore overrides fixed weekdays.
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

revoke all on function public.noble_submit_availability_v2(text, jsonb, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.noble_submit_availability_v2(text, jsonb, jsonb, jsonb)
  to anon, authenticated;

notify pgrst, 'reload schema';
