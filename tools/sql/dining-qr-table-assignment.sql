begin;

alter table public.dining_qr_sessions
  add column if not exists table_code text;

-- The previous version allowed an active QR without a table. Under the new
-- workflow an unassigned QR is inactive, so close only those legacy sessions.
update public.dining_qr_sessions
set status = 'closed',
    ended_at = coalesce(ended_at, now()),
    ended_reason = coalesce(nullif(ended_reason, ''), 'table-assignment-migration')
where status = 'active'
  and nullif(trim(table_code), '') is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'dining_qr_sessions_active_table_check'
      and conrelid = 'public.dining_qr_sessions'::regclass
  ) then
    alter table public.dining_qr_sessions
      add constraint dining_qr_sessions_active_table_check
      check (status = 'closed' or nullif(trim(table_code), '') is not null);
  end if;
end;
$$;

create unique index if not exists dining_qr_sessions_one_active_table
on public.dining_qr_sessions (branch, lower(table_code))
where status = 'active';

create index if not exists dining_qr_sessions_table_history
on public.dining_qr_sessions (branch, lower(table_code), started_at desc);

create or replace function public.validate_dining_request_qr_session()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  active_session public.dining_qr_sessions;
begin
  if new.qr_session_id is null or new.qr_number is null then
    raise exception 'An active QR session is required';
  end if;

  select session.*
  into active_session
  from public.dining_qr_sessions as session
  where session.id = new.qr_session_id
    and session.branch = new.branch
    and session.qr_number = new.qr_number
    and session.status = 'active'
    and nullif(trim(session.table_code), '') is not null;

  if not found then
    raise exception 'The QR is not assigned to an active table';
  end if;

  new.table_code = active_session.table_code;
  return new;
end;
$$;

create or replace function public.assign_dining_qr_session(
  p_branch text,
  p_qr_number integer,
  p_table_code text
)
returns public.dining_qr_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  active_session public.dining_qr_sessions;
  normalized_branch text := lower(trim(p_branch));
  normalized_table_code text := trim(p_table_code);
begin
  if normalized_branch is null or normalized_branch !~ '^[a-z0-9_-]{1,40}$' then
    raise exception 'Invalid branch';
  end if;
  if p_qr_number is null or p_qr_number not between 1 and 10 then
    raise exception 'QR number must be between 1 and 10';
  end if;
  if normalized_table_code is null or normalized_table_code = '' or length(normalized_table_code) > 40 then
    raise exception 'Table code must be between 1 and 40 characters';
  end if;

  -- Serialize assignments for a branch so simultaneous taps cannot assign the
  -- same table or QR twice before either transaction becomes visible.
  perform pg_advisory_xact_lock(hashtext(normalized_branch));

  select session.*
  into active_session
  from public.dining_qr_sessions as session
  where session.branch = normalized_branch
    and session.qr_number = p_qr_number
    and session.status = 'active'
  limit 1;

  if found then
    if lower(active_session.table_code) = lower(normalized_table_code) then
      return active_session;
    end if;
    raise exception 'QR % is already assigned to table %', p_qr_number, active_session.table_code;
  end if;

  if exists (
    select 1
    from public.dining_qr_sessions as session
    where session.branch = normalized_branch
      and lower(session.table_code) = lower(normalized_table_code)
      and session.status = 'active'
  ) then
    raise exception 'Table % already has an active QR', normalized_table_code;
  end if;

  insert into public.dining_qr_sessions (branch, qr_number, table_code)
  values (normalized_branch, p_qr_number, normalized_table_code)
  returning * into active_session;

  return active_session;
end;
$$;

-- Direct activation is intentionally removed. A QR now becomes active only
-- through assign_dining_qr_session with a table code.
drop function if exists public.activate_dining_qr_session(text, integer);

revoke all on function public.assign_dining_qr_session(text, integer, text)
from public;
revoke all on function public.reset_dining_qr_session(text, integer)
from public;
grant execute on function public.assign_dining_qr_session(text, integer, text)
to anon, authenticated;

drop policy if exists dining_requests_public_insert on public.dining_requests;
create policy dining_requests_public_insert
on public.dining_requests
for insert
to anon, authenticated
with check (
  status = 'new'
  and source in ('table-qr', 'table-service-call')
  and qr_number between 1 and 10
  and qr_session_id is not null
  and exists (
    select 1
    from public.dining_qr_sessions as session
    where session.id = dining_requests.qr_session_id
      and session.branch = dining_requests.branch
      and session.qr_number = dining_requests.qr_number
      and session.status = 'active'
      and nullif(trim(session.table_code), '') is not null
      and dining_requests.table_code = session.table_code
  )
);

comment on column public.dining_qr_sessions.table_code is
  'Table assigned for this visit. Null means the QR is not active/assigned.';

commit;
