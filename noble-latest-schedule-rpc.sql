-- Run this after the scheduling tables/views exist.
-- It lets Noble read the latest published weekly schedule without exposing
-- schedule tables directly to anon users.

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
