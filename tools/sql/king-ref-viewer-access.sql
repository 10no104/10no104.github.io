-- King reference-code access.
-- Access levels:
--   anon: reservations only (Google Sheet in the frontend)
--   REF : reservations + staff calendar + full schedule management
--   Auth: existing Supabase administrator access

create schema if not exists admin;

create table if not exists admin.king_ref_access (
  id uuid primary key default extensions.gen_random_uuid(),
  ref_code text not null unique,
  label text not null default 'King REF',
  can_view_calendar boolean not null default true,
  can_manage_schedule boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint king_ref_access_ref_code_length
    check (char_length(btrim(ref_code)) between 4 and 64)
);

create table if not exists admin.king_ref_sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  access_id uuid not null references admin.king_ref_access(id) on delete cascade,
  token_hash bytea not null unique,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists king_ref_sessions_expires_at_idx
  on admin.king_ref_sessions (expires_at);
create index if not exists king_ref_sessions_access_id_idx
  on admin.king_ref_sessions (access_id);

comment on table admin.king_ref_access is
  'Plain reference codes allowed to view the King calendar and manage schedules.';
comment on table admin.king_ref_sessions is
  'Short-lived opaque sessions issued after a King reference code is verified.';

alter table admin.king_ref_access enable row level security;
alter table admin.king_ref_sessions enable row level security;
revoke all on table admin.king_ref_access from public, anon, authenticated;
revoke all on table admin.king_ref_sessions from public, anon, authenticated;

drop policy if exists king_ref_access_deny_direct on admin.king_ref_access;
create policy king_ref_access_deny_direct
on admin.king_ref_access
for all
to public
using (false)
with check (false);

drop policy if exists king_ref_sessions_deny_direct on admin.king_ref_sessions;
create policy king_ref_sessions_deny_direct
on admin.king_ref_sessions
for all
to public
using (false)
with check (false);

create or replace function admin.king_ref_request_has_permission(required_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from admin.king_ref_sessions as session
    join admin.king_ref_access as access on access.id = session.access_id
    where session.expires_at > now()
      and access.active
      and session.token_hash = extensions.digest(
        coalesce(
          coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb
            ->> 'x-king-ref-session',
          ''
        ),
        'sha256'
      )
      and case required_permission
        when 'calendar' then access.can_view_calendar
        when 'schedule' then access.can_manage_schedule
        else false
      end
  );
$$;

revoke all on function admin.king_ref_request_has_permission(text)
  from public, anon, authenticated;
grant execute on function admin.king_ref_request_has_permission(text) to anon;

create or replace function public.king_start_ref_session(input_ref text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  matched_access admin.king_ref_access%rowtype;
  plain_token text;
  session_expiry timestamptz := now() + interval '12 hours';
begin
  select access.*
  into matched_access
  from admin.king_ref_access as access
  where access.active
    and access.ref_code = btrim(coalesce(input_ref, ''))
  limit 1;

  if matched_access.id is null then
    raise exception 'invalid reference code' using errcode = '42501';
  end if;

  delete from admin.king_ref_sessions where expires_at <= now();
  plain_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into admin.king_ref_sessions (access_id, token_hash, expires_at)
  values (
    matched_access.id,
    extensions.digest(plain_token, 'sha256'),
    session_expiry
  );

  return jsonb_build_object(
    'token', plain_token,
    'expires_at', session_expiry,
    'label', matched_access.label,
    'can_view_calendar', matched_access.can_view_calendar,
    'can_manage_schedule', matched_access.can_manage_schedule
  );
end;
$$;

create or replace function public.king_end_ref_session()
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  delete from admin.king_ref_sessions as session
  where session.token_hash = extensions.digest(
    coalesce(
      coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb
        ->> 'x-king-ref-session',
      ''
    ),
    'sha256'
  );
$$;

revoke all on function public.king_start_ref_session(text)
  from public, anon, authenticated;
revoke all on function public.king_end_ref_session()
  from public, anon, authenticated;
grant execute on function public.king_start_ref_session(text) to anon;
grant execute on function public.king_end_ref_session() to anon;

-- Safe API views: employee phone/SIN/reference-code fields are never exposed.
drop view if exists public.king_ref_staff_directory;
create view public.king_ref_staff_directory
with (security_invoker = true)
as
select
  employee.staff_key,
  employee.staff_key as name,
  employee.job_role,
  employee.branch_scope,
  employee.active
from staff.employee_refs as employee
where employee.active is true
  and lower(coalesce(employee.job_role, 'server')) <> 'kitchen';

drop view if exists public.king_ref_staff_availability;
create view public.king_ref_staff_availability
with (security_invoker = true)
as
select
  availability.staff_key,
  availability.staff_name,
  availability.branch_scope,
  availability.availability_date,
  availability.status,
  availability.available_start,
  availability.available_end,
  availability.note
from schedule.staff_availability as availability;

drop view if exists public.king_ref_staff_preferences;
create view public.king_ref_staff_preferences
with (security_invoker = true)
as
select
  preference.staff_key,
  preference.staff_name,
  preference.staff_name as name,
  preference.branch_scope,
  preference.fixed_unavailable_weekdays,
  preference.fixed_preferred_weekdays,
  preference.work_style,
  preference.preferred_branch,
  preference.max_weekly_shifts
from schedule.staff_preferences as preference;

drop view if exists public.king_ref_schedule_weeks;
create view public.king_ref_schedule_weeks
with (security_invoker = true)
as
select week.id, week.week_start, week.status, week.note
from schedule.schedule_weeks as week;

drop view if exists public.king_ref_schedule_shifts;
create view public.king_ref_schedule_shifts
with (security_invoker = true)
as
select
  shift.id,
  shift.week_id,
  shift.shift_date,
  shift.branch,
  shift.staff_key,
  shift.staff_name,
  shift.job_role,
  shift.shift_label,
  shift.start_time,
  shift.end_time,
  shift.sort_order,
  shift.note
from schedule.schedule_shifts as shift;

drop view if exists public.king_ref_schedule_calendar_events;
create view public.king_ref_schedule_calendar_events
with (security_invoker = true)
as
select event.id, event.event_date, event.title
from public.king_schedule_calendar_events as event;

grant usage on schema staff, schedule to anon;

revoke all on table staff.employee_refs from anon;
revoke all on table schedule.staff_availability from anon;
revoke all on table schedule.staff_preferences from anon;
revoke all on table schedule.schedule_weeks from anon;
revoke all on table schedule.schedule_shifts from anon;
revoke all on table public.king_schedule_calendar_events from anon;

grant select (staff_key, job_role, branch_scope, active)
  on staff.employee_refs to anon;
grant select (
  staff_key, staff_name, branch_scope, availability_date, status,
  available_start, available_end, note
) on schedule.staff_availability to anon;
grant select (
  staff_key, staff_name, branch_scope, fixed_unavailable_weekdays,
  fixed_preferred_weekdays, work_style, preferred_branch, max_weekly_shifts
) on schedule.staff_preferences to anon;
grant select (id, week_start, status, note)
  on schedule.schedule_weeks to anon;
grant insert (week_start, status, note)
  on schedule.schedule_weeks to anon;
grant update (status, note)
  on schedule.schedule_weeks to anon;
grant select (
  id, week_id, shift_date, branch, staff_key, staff_name, job_role,
  shift_label, start_time, end_time, sort_order, note
) on schedule.schedule_shifts to anon;
grant insert (
  week_id, shift_date, branch, staff_key, staff_name, job_role,
  shift_label, start_time, end_time, sort_order, note
) on schedule.schedule_shifts to anon;
grant update (
  shift_date, branch, staff_key, staff_name, job_role,
  shift_label, start_time, end_time, sort_order, note
) on schedule.schedule_shifts to anon;
grant delete on schedule.schedule_shifts to anon;
grant select (id, event_date, title)
  on public.king_schedule_calendar_events to anon;
grant insert (event_date, title)
  on public.king_schedule_calendar_events to anon;
grant delete on public.king_schedule_calendar_events to anon;

revoke all on public.king_ref_staff_directory from anon;
revoke all on public.king_ref_staff_availability from anon;
revoke all on public.king_ref_staff_preferences from anon;
revoke all on public.king_ref_schedule_weeks from anon;
revoke all on public.king_ref_schedule_shifts from anon;
revoke all on public.king_ref_schedule_calendar_events from anon;

grant select on public.king_ref_staff_directory to anon;
grant select on public.king_ref_staff_availability to anon;
grant select on public.king_ref_staff_preferences to anon;
grant select, insert, update on public.king_ref_schedule_weeks to anon;
grant select, insert, update, delete on public.king_ref_schedule_shifts to anon;
grant select, insert, delete on public.king_ref_schedule_calendar_events to anon;

drop policy if exists king_ref_staff_directory_select on staff.employee_refs;
create policy king_ref_staff_directory_select
on staff.employee_refs
for select
to anon
using (
  (select admin.king_ref_request_has_permission('calendar'))
  or (select admin.king_ref_request_has_permission('schedule'))
);

drop policy if exists king_ref_staff_availability_select on schedule.staff_availability;
create policy king_ref_staff_availability_select
on schedule.staff_availability
for select
to anon
using (
  (select admin.king_ref_request_has_permission('calendar'))
  or (select admin.king_ref_request_has_permission('schedule'))
);

drop policy if exists king_ref_staff_preferences_select on schedule.staff_preferences;
create policy king_ref_staff_preferences_select
on schedule.staff_preferences
for select
to anon
using (
  (select admin.king_ref_request_has_permission('calendar'))
  or (select admin.king_ref_request_has_permission('schedule'))
);

drop policy if exists king_ref_schedule_manage on schedule.schedule_weeks;
create policy king_ref_schedule_manage
on schedule.schedule_weeks
for all
to anon
using ((select admin.king_ref_request_has_permission('schedule')))
with check ((select admin.king_ref_request_has_permission('schedule')));

drop policy if exists king_ref_schedule_manage on schedule.schedule_shifts;
create policy king_ref_schedule_manage
on schedule.schedule_shifts
for all
to anon
using ((select admin.king_ref_request_has_permission('schedule')))
with check ((select admin.king_ref_request_has_permission('schedule')));

drop policy if exists king_ref_schedule_calendar_events_manage
  on public.king_schedule_calendar_events;
create policy king_ref_schedule_calendar_events_manage
on public.king_schedule_calendar_events
for all
to anon
using ((select admin.king_ref_request_has_permission('schedule')))
with check ((select admin.king_ref_request_has_permission('schedule')));

insert into admin.king_ref_access (
  ref_code,
  label,
  can_view_calendar,
  can_manage_schedule,
  active
)
values (
  '110211021102',
  'King REF',
  true,
  true,
  true
)
on conflict (ref_code) do update
set label = excluded.label,
    can_view_calendar = excluded.can_view_calendar,
    can_manage_schedule = excluded.can_manage_schedule,
    active = excluded.active,
    updated_at = now();

notify pgrst, 'reload schema';
