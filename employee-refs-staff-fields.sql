-- Employee refs extension for King staff management.
-- Run this after supabase-schema-classification.sql / noble-rpc-fix.sql.

create extension if not exists pgcrypto;
create schema if not exists staff;

do $$
begin
  if to_regclass('staff.noble_access_requests') is not null then
    alter table staff.noble_access_requests
      add column if not exists phone_number text;
  end if;

  if to_regclass('public.noble_access_requests') is not null
     and to_regclass('staff.noble_access_requests') is null then
    alter table public.noble_access_requests
      add column if not exists phone_number text;
  end if;

  if to_regclass('staff.employee_refs') is not null then
    alter table staff.employee_refs
      add column if not exists sin_number text,
      add column if not exists phone_number text,
      add column if not exists active boolean not null default true,
      add column if not exists inactive_at timestamptz,
      add column if not exists updated_at timestamptz not null default now();
  end if;

  if to_regclass('public.employee_refs') is not null
     and to_regclass('staff.employee_refs') is null then
    alter table public.employee_refs
      add column if not exists sin_number text,
      add column if not exists phone_number text,
      add column if not exists active boolean not null default true,
      add column if not exists inactive_at timestamptz,
      add column if not exists updated_at timestamptz not null default now();
  end if;
end;
$$;

create or replace function staff.touch_employee_refs_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
begin
  if to_regclass('staff.employee_refs') is not null then
    drop trigger if exists employee_refs_touch_updated_at on staff.employee_refs;
    create trigger employee_refs_touch_updated_at
    before update on staff.employee_refs
    for each row execute function staff.touch_employee_refs_updated_at();
  end if;
end;
$$;

drop view if exists public.employee_refs;
create view public.employee_refs
with (security_invoker = true)
as select * from staff.employee_refs;

drop view if exists public.noble_access_requests;
create view public.noble_access_requests
with (security_invoker = true)
as select * from staff.noble_access_requests;

grant select, insert, update, delete on public.employee_refs to authenticated;
grant select, insert, update, delete on public.noble_access_requests to authenticated;
grant usage on schema staff to authenticated;
grant select, insert, update, delete on staff.employee_refs to authenticated;
grant select, insert, update, delete on staff.noble_access_requests to authenticated;
revoke all on public.employee_refs from anon;
revoke all on public.noble_access_requests from anon;

create or replace function public.noble_submit_access_request_v2(
  p_name text,
  p_branch_scope text,
  p_smart_server_number text,
  p_phone_number text default null
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

  if nullif(trim(coalesce(p_phone_number, '')), '') is null then
    raise exception 'phone_number is required';
  end if;

  insert into staff.noble_access_requests (
    name,
    branch_scope,
    smart_server_number,
    phone_number
  )
  values (
    trim(p_name),
    normalized_branch,
    trim(p_smart_server_number),
    trim(p_phone_number)
  )
  returning id into new_id;

  return new_id;
end;
$$;

revoke all on function public.noble_submit_access_request_v2(text, text, text, text) from public;
grant execute on function public.noble_submit_access_request_v2(text, text, text, text) to anon, authenticated;
