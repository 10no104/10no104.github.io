-- Remove the abandoned settlement feature and superseded public RPCs.
-- Audited on 2026-08-06 against the live ehwa project and current frontend.
--
-- Important: the public noble_* and king_ref_* schedule objects are views over
-- the same schedule.* base tables. They consume no duplicate row storage and
-- remain in place because they enforce different client access boundaries.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Superseded endpoints that are not referenced by the current frontend.
drop function if exists public.king_get_access_requests();
drop function if exists public.king_save_employee_with_settlement_v1(jsonb);
drop function if exists public.noble_get_latest_schedule(text);
drop function if exists public.noble_get_my_schedule(text, date, date);
drop function if exists public.noble_get_wage_history_v1(text);
drop function if exists public.noble_submit_access_request(text, text, text);
drop function if exists public.noble_submit_access_request_v2(text, text, text);
drop function if exists public.noble_submit_access_request_v2(text, text, text, text);
drop function if exists public.noble_submit_availability(text, date[], date[], jsonb);

-- Keep the King employee endpoint, but detach it from settlement and expose it
-- only to signed-in Supabase administrators. The frontend does not use the
-- former settlement_* result fields.
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
  updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
  select
    employee.id,
    employee.ref_code,
    employee.staff_key,
    employee.job_role,
    employee.branch_scope,
    employee.active,
    employee.sin_number,
    employee.phone_number,
    employee.inactive_at,
    employee.created_at,
    employee.updated_at
  from staff.employee_refs as employee
  order by employee.active desc, employee.branch_scope, employee.staff_key;
$$;

revoke all on function public.king_get_employee_refs()
  from public, anon, authenticated;
grant execute on function public.king_get_employee_refs()
  to authenticated;

comment on function public.king_get_employee_refs() is
  'Returns employee management data to signed-in King administrators only.';

-- Remove dynamic compatibility logic and close anonymous access to employee
-- onboarding requests. This endpoint is used only by the full King login.
create or replace function public.king_get_access_requests_v2()
returns table (
  id uuid,
  name text,
  branch_scope text,
  job_role text,
  phone_number text,
  smart_server_number text,
  status text,
  note text,
  created_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
  select
    request.id,
    request.name,
    request.branch_scope,
    case
      when lower(trim(coalesce(request.job_role, ''))) = 'kitchen' then 'kitchen'
      else 'server'
    end,
    request.phone_number,
    request.smart_server_number,
    request.status,
    request.note,
    request.created_at
  from staff.noble_access_requests as request
  where request.status in ('pending', 'approved')
  order by request.created_at desc;
$$;

revoke all on function public.king_get_access_requests_v2()
  from public, anon, authenticated;
grant execute on function public.king_get_access_requests_v2()
  to authenticated;

comment on function public.king_get_access_requests_v2() is
  'Returns Noble onboarding requests to signed-in King administrators only.';

-- Abandoned settlement API surface.
drop function if exists public.settlement_get_day_v1(text, date);
drop function if exists public.settlement_get_summary_v1(text, date, date);
drop function if exists public.settlement_save_day_v1(jsonb);
drop function if exists public.settlement_save_staff_v1(jsonb);

drop view if exists public.settlement_staff_calculations;
drop view if exists public.settlement_daily_calculations;
drop view if exists public.settlement_daily_staff_entries;
drop view if exists public.settlement_daily_entries;
drop view if exists public.settlement_staff_members;

drop view if exists settlement.period_staff_summaries;
drop view if exists settlement.period_summaries;
drop view if exists settlement.staff_calculations;
drop view if exists settlement.daily_calculations;

drop table if exists settlement.daily_staff_entries;
drop table if exists settlement.daily_entries;
drop table if exists settlement.staff_members;

drop function if exists settlement.period_start(date);
drop function if exists settlement.touch_updated_at();
drop schema if exists settlement;

-- Remove exact duplicate indexes. The retained unique indexes have the same
-- column order and satisfy both uniqueness and lookup use cases.
drop index if exists public.dining_table_layouts_branch_idx;
drop index if exists schedule.noble_staff_availability_staff_idx;

-- This eight-row table is always loaded as a complete set by King/Noble; the
-- branch-only index has had no scans since project statistics began.
drop index if exists schedule.staff_preferences_branch_idx;

-- These policies were byte-for-byte equivalent for the authenticated role.
drop policy if exists noble_access_requests_admin_all
  on staff.noble_access_requests;

-- Trigger bodies only touch NEW, so an empty fixed search path is sufficient
-- and avoids inheriting a caller-controlled role search path.
alter function public.king_schedule_calendar_events_touch_updated_at()
  set search_path = '';
alter function public.noble_touch_updated_at()
  set search_path = '';
alter function schedule.touch_shift_substitute_request_updated_at()
  set search_path = '';
alter function schedule.touch_staff_preferences_updated_at()
  set search_path = '';
alter function staff.touch_employee_refs_updated_at()
  set search_path = '';

select pg_notify('pgrst', 'reload schema');

commit;
