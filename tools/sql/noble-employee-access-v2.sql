-- Noble employee lookup with kitchen role and former-employee wage access.
-- Run once in the Supabase SQL Editor.

create or replace function public.noble_lookup_employee_v2(input_ref text)
returns jsonb
language sql
stable
security definer
set search_path = public, staff, pg_temp
as $$
  select jsonb_build_object(
    'staff_key', e.staff_key,
    'branch_scope', coalesce(nullif(lower(trim(e.branch_scope)), ''), 'both'),
    'job_role', case
      when lower(trim(coalesce(e.job_role, ''))) = 'kitchen' then 'kitchen'
      else 'server'
    end,
    'active', coalesce(e.active, true),
    'inactive_at', e.inactive_at
  )
  from public.employee_refs e
  where lower(trim(e.ref_code)) = lower(trim(input_ref))
  limit 1;
$$;

revoke all on function public.noble_lookup_employee_v2(text) from public;
grant execute on function public.noble_lookup_employee_v2(text) to anon, authenticated;

comment on function public.noble_lookup_employee_v2(text) is
  'Looks up active or former employees for Noble. Former employees are limited to wage history by the client.';

-- Store the requested role without depending on whether the staff tables
-- currently live in public or behind the public compatibility views.
do $$
declare
  public_request_kind "char";
begin
  select c.relkind
    into public_request_kind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'noble_access_requests';

  if to_regclass('staff.noble_access_requests') is not null then
    alter table staff.noble_access_requests
      add column if not exists job_role text;
    update staff.noble_access_requests
      set job_role = case when lower(trim(coalesce(job_role, ''))) = 'kitchen' then 'kitchen' else 'server' end;
    alter table staff.noble_access_requests
      alter column job_role set default 'server',
      alter column job_role set not null;
  end if;

  if to_regclass('public.noble_access_requests') is not null
     and public_request_kind in ('r', 'p') then
    alter table public.noble_access_requests
      add column if not exists job_role text;
    update public.noble_access_requests
      set job_role = case when lower(trim(coalesce(job_role, ''))) = 'kitchen' then 'kitchen' else 'server' end;
    alter table public.noble_access_requests
      alter column job_role set default 'server',
      alter column job_role set not null;
  end if;
end;
$$;

create or replace function public.noble_submit_access_request_v3(
  p_name text,
  p_branch_scope text,
  p_job_role text,
  p_smart_server_number text,
  p_phone_number text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, staff, pg_temp
as $$
declare
  new_id uuid;
  normalized_branch text := lower(trim(p_branch_scope));
  normalized_role text := lower(trim(p_job_role));
  target_table regclass;
begin
  if nullif(trim(p_name), '') is null then
    raise exception 'name is required';
  end if;

  if normalized_branch not in ('uptown', 'downtown', 'both') then
    raise exception 'invalid branch_scope';
  end if;

  if normalized_role not in ('server', 'kitchen') then
    raise exception 'invalid job_role';
  end if;

  if nullif(trim(p_smart_server_number), '') is null then
    raise exception 'smart_server_number is required';
  end if;

  if nullif(trim(coalesce(p_phone_number, '')), '') is null then
    raise exception 'phone_number is required';
  end if;

  target_table := coalesce(
    to_regclass('staff.noble_access_requests'),
    to_regclass('public.noble_access_requests')
  );
  if target_table is null then
    raise exception 'noble_access_requests table is missing';
  end if;

  execute format(
    'insert into %s (name, branch_scope, job_role, smart_server_number, phone_number)
     values ($1, $2, $3, $4, $5) returning id',
    target_table
  )
  into new_id
  using trim(p_name), normalized_branch, normalized_role,
    trim(p_smart_server_number), trim(p_phone_number);

  return new_id;
end;
$$;

revoke all on function public.noble_submit_access_request_v3(text, text, text, text, text) from public;
grant execute on function public.noble_submit_access_request_v3(text, text, text, text, text) to anon, authenticated;

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
language plpgsql
security definer
set search_path = public, staff, pg_temp
as $$
declare
  target_table regclass;
begin
  target_table := coalesce(
    to_regclass('staff.noble_access_requests'),
    to_regclass('public.noble_access_requests')
  );
  if target_table is null then
    return;
  end if;

  return query execute format(
    'select id, name, branch_scope,
       case when lower(trim(coalesce(job_role, ''''))) = ''kitchen'' then ''kitchen'' else ''server'' end,
       phone_number, smart_server_number, status, note, created_at
     from %s
     where status in (''pending'', ''approved'')
     order by created_at desc',
    target_table
  );
end;
$$;

revoke all on function public.king_get_access_requests_v2() from public;
grant execute on function public.king_get_access_requests_v2() to authenticated;
