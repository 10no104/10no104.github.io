-- Optional schema organization migration.
-- Goal:
-- - admin.*    : admin users / admin-only data
-- - menu.*     : menu management
-- - staff.*    : employee refs / access requests
-- - schedule.* : availability and schedule production
--
-- This migration moves existing public tables into schemas and recreates
-- public compatibility views so current frontend calls like .from("menu_items")
-- can keep working while code is migrated gradually.

create schema if not exists admin;
create schema if not exists menu;
create schema if not exists staff;
create schema if not exists schedule;

grant usage on schema admin to authenticated;
grant usage on schema menu to anon, authenticated;
grant usage on schema staff to anon, authenticated;
grant usage on schema schedule to anon, authenticated;

do $$
begin
  if to_regclass('public.admin_users') is not null and to_regclass('admin.admin_users') is null then
    alter table public.admin_users set schema admin;
  end if;

  if to_regclass('public.menu_items') is not null and to_regclass('menu.menu_items') is null then
    alter table public.menu_items set schema menu;
  end if;

  if to_regclass('public.employee_refs') is not null and to_regclass('staff.employee_refs') is null then
    alter table public.employee_refs set schema staff;
  end if;

  if to_regclass('public.noble_access_requests') is not null and to_regclass('staff.noble_access_requests') is null then
    alter table public.noble_access_requests set schema staff;
  end if;

  if to_regclass('public.noble_staff_availability') is not null and to_regclass('schedule.staff_availability') is null then
    alter table public.noble_staff_availability rename to staff_availability;
    alter table public.staff_availability set schema schedule;
  end if;

  if to_regclass('public.noble_schedule_weeks') is not null and to_regclass('schedule.schedule_weeks') is null then
    alter table public.noble_schedule_weeks rename to schedule_weeks;
    alter table public.schedule_weeks set schema schedule;
  end if;

  if to_regclass('public.noble_schedule_shifts') is not null and to_regclass('schedule.schedule_shifts') is null then
    alter table public.noble_schedule_shifts rename to schedule_shifts;
    alter table public.schedule_shifts set schema schedule;
  end if;
end;
$$;

grant select, insert, update, delete on all tables in schema admin to authenticated;
grant select on all tables in schema menu to anon;
grant select, insert, update, delete on all tables in schema menu to authenticated;
grant select, insert, update, delete on all tables in schema staff to authenticated;
grant select, insert, update, delete on all tables in schema schedule to authenticated;

-- Staff/schedule anon writes should go through public RPCs, not direct table access.
revoke all on all tables in schema staff from anon;
revoke all on all tables in schema schedule from anon;

alter default privileges in schema admin grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema menu grant select on tables to anon;
alter default privileges in schema menu grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema staff grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema schedule grant select, insert, update, delete on tables to authenticated;

drop view if exists public.admin_users;
create view public.admin_users
with (security_invoker = true)
as select * from admin.admin_users;

drop view if exists public.menu_items;
create view public.menu_items
with (security_invoker = true)
as select * from menu.menu_items;

drop view if exists public.employee_refs;
create view public.employee_refs
with (security_invoker = true)
as select * from staff.employee_refs;

drop view if exists public.noble_access_requests;
create view public.noble_access_requests
with (security_invoker = true)
as select * from staff.noble_access_requests;

drop view if exists public.noble_staff_availability;
create view public.noble_staff_availability
with (security_invoker = true)
as select * from schedule.staff_availability;

drop view if exists public.noble_schedule_weeks;
create view public.noble_schedule_weeks
with (security_invoker = true)
as select * from schedule.schedule_weeks;

drop view if exists public.noble_schedule_shifts;
create view public.noble_schedule_shifts
with (security_invoker = true)
as select * from schedule.schedule_shifts;

grant select, insert, update, delete on public.admin_users to authenticated;
grant select on public.menu_items to anon;
grant select, insert, update, delete on public.menu_items to authenticated;
grant select, insert, update, delete on public.employee_refs to authenticated;
grant select, insert, update, delete on public.noble_access_requests to authenticated;
grant select, insert, update, delete on public.noble_staff_availability to authenticated;
grant select, insert, update, delete on public.noble_schedule_weeks to authenticated;
grant select, insert, update, delete on public.noble_schedule_shifts to authenticated;

revoke all on public.employee_refs from anon;
revoke all on public.noble_access_requests from anon;
revoke all on public.noble_staff_availability from anon;
revoke all on public.noble_schedule_weeks from anon;
revoke all on public.noble_schedule_shifts from anon;

-- Optional: schema-native helper views for easier browsing in Supabase UI.
comment on schema admin is 'Admin accounts and admin-only helpers.';
comment on schema menu is 'Menu data and menu management.';
comment on schema staff is 'Employee references and staff-facing access requests.';
comment on schema schedule is 'Staff availability, schedule weeks, and shifts.';

comment on view public.admin_users is 'Compatibility view for admin.admin_users.';
comment on view public.menu_items is 'Compatibility view for menu.menu_items.';
comment on view public.employee_refs is 'Compatibility view for staff.employee_refs.';
comment on view public.noble_access_requests is 'Compatibility view for staff.noble_access_requests.';
comment on view public.noble_staff_availability is 'Compatibility view for schedule.staff_availability.';
comment on view public.noble_schedule_weeks is 'Compatibility view for schedule.schedule_weeks.';
comment on view public.noble_schedule_shifts is 'Compatibility view for schedule.schedule_shifts.';
