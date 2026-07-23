-- Run this after noble-rpc-fix.sql.
-- Noble can read one selected published week at a time without direct access
-- to the scheduling tables. Unpublished or missing weeks return no rows.

create or replace function public.noble_get_schedule_week_v1(
  input_ref text,
  p_week_start date
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
    where w.week_start = p_week_start
      and w.status = 'published'
    order by s.branch, s.shift_date, s.sort_order, s.staff_name;
end;
$$;

revoke all on function public.noble_get_schedule_week_v1(text, date) from public;
grant execute on function public.noble_get_schedule_week_v1(text, date) to anon, authenticated;
