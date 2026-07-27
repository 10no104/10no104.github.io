-- EHWA dining operational guards and checkout semantics.
-- Run after:
--   1. dining-party-guest-architecture.sql
--   2. dining-party-qr-pool.sql
--
-- Adds an expected headcount to each Party, prevents one browser Guest from
-- silently switching to another active Party, and treats Party close as the
-- final payment/checkout event while preserving all order history.

begin;

alter table public.dining_parties
  add column if not exists expected_guest_count integer not null default 1;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'dining_parties_expected_guest_count_check'
      and conrelid = 'public.dining_parties'::regclass
  ) then
    alter table public.dining_parties
      add constraint dining_parties_expected_guest_count_check
      check (expected_guest_count between 1 and 100);
  end if;
end;
$$;

-- Avoid an immediate false warning for Parties that were already active when
-- this migration was installed.
update public.dining_parties as party
set expected_guest_count = greatest(
  party.expected_guest_count,
  (
    select count(*)::integer
    from public.dining_guests as guest
    where guest.party_id = party.id
      and guest.status = 'ACTIVE'
      and guest.expires_at > now()
  ),
  1
)
where party.status = 'ACTIVE';

create or replace function public.configure_dining_party_qrs(
  p_branch text,
  p_table_codes text[],
  p_qr_numbers integer[],
  p_party_id bigint,
  p_expected_guest_count integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  setup_result jsonb;
  resolved_party_id bigint;
begin
  if p_expected_guest_count is null or p_expected_guest_count not between 1 and 100 then
    raise exception 'Expected guest count must be between 1 and 100';
  end if;

  setup_result := public.configure_dining_party_qrs(
    p_branch,
    p_table_codes,
    p_qr_numbers,
    p_party_id
  );
  resolved_party_id := (setup_result->>'party_id')::bigint;

  update public.dining_parties
  set expected_guest_count = p_expected_guest_count,
      updated_at = now()
  where id = resolved_party_id
    and branch = lower(trim(p_branch))
    and status = 'ACTIVE';

  if not found then
    raise exception 'Active Party not found after QR assignment';
  end if;

  return setup_result || jsonb_build_object(
    'expected_guest_count',
    p_expected_guest_count
  );
end;
$$;

create or replace function public.resolve_dining_guest(
  p_branch text,
  p_qr_number integer,
  p_guest_id uuid default null,
  p_device_info jsonb default '{}'::jsonb,
  p_current_page text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_branch text := lower(trim(p_branch));
  active_table public.dining_tables;
  active_party public.dining_parties;
  stored_guest public.dining_guests;
  resolved_guest public.dining_guests;
  stored_party_status text;
  stored_table_code text;
  compatibility_session_id bigint;
  safe_device_info jsonb := coalesce(p_device_info, '{}'::jsonb);
  safe_page text := left(coalesce(p_current_page, ''), 300);
begin
  if normalized_branch is null or normalized_branch !~ '^[a-z0-9_-]{1,40}$' then
    raise exception 'Invalid branch';
  end if;
  if p_qr_number is null or p_qr_number not between 1 and 10 then
    raise exception 'Invalid QR number';
  end if;
  if jsonb_typeof(safe_device_info) <> 'object'
    or octet_length(safe_device_info::text) > 12000
  then
    safe_device_info := '{}'::jsonb;
  end if;

  update public.dining_guests
  set status = 'EXPIRED'
  where status = 'ACTIVE'
    and expires_at <= now();

  select table_record.*
  into active_table
  from public.dining_party_qrs as party_qr
  join public.dining_tables as table_record
    on table_record.id = party_qr.table_id
   and table_record.current_party_id = party_qr.party_id
  join public.dining_parties as party
    on party.id = party_qr.party_id
   and party.status = 'ACTIVE'
  where party_qr.branch = normalized_branch
    and party_qr.qr_number = p_qr_number
    and party_qr.released_at is null
  limit 1;

  if not found then
    raise exception 'This QR is not assigned to an active Party';
  end if;

  select party.*
  into active_party
  from public.dining_parties as party
  where party.id = active_table.current_party_id
    and party.status = 'ACTIVE';

  if p_guest_id is not null then
    select guest.*
    into stored_guest
    from public.dining_guests as guest
    where guest.id = p_guest_id
      and guest.branch = normalized_branch
    for update;

    if stored_guest.id is not null then
      select party.status
      into stored_party_status
      from public.dining_parties as party
      where party.id = stored_guest.party_id;

      select table_record.table_code
      into stored_table_code
      from public.dining_tables as table_record
      where table_record.id = stored_guest.current_table_id;
    end if;

    if stored_guest.id is not null
      and stored_guest.status = 'ACTIVE'
      and stored_guest.expires_at > now()
      and stored_party_status = 'ACTIVE'
      and stored_guest.party_id <> active_party.id
    then
      raise exception using
        message = 'GUEST_PARTY_CONFLICT',
        detail = jsonb_build_object(
          'guest_id', stored_guest.id,
          'display_code', stored_guest.display_code,
          'current_party_id', stored_guest.party_id,
          'current_table_code', coalesce(stored_table_code, ''),
          'target_party_id', active_party.id,
          'target_table_code', active_table.table_code
        )::text,
        hint = 'Finish payment for the current Guest before ordering from another Party';
    end if;

    if stored_guest.id is not null
      and stored_guest.status = 'PAID'
      and stored_party_status = 'ACTIVE'
      and stored_guest.party_id = active_party.id
    then
      raise exception using
        message = 'GUEST_ALREADY_PAID',
        detail = jsonb_build_object(
          'guest_id', stored_guest.id,
          'display_code', stored_guest.display_code,
          'current_party_id', stored_guest.party_id,
          'current_table_code', coalesce(stored_table_code, active_table.table_code),
          'target_party_id', active_party.id,
          'target_table_code', active_table.table_code
        )::text,
        hint = 'This Guest bill is already paid; wait for Party checkout or ask staff before creating another bill';
    end if;

    if stored_guest.id is not null
      and stored_guest.party_id = active_party.id
      and stored_guest.status = 'ACTIVE'
      and stored_guest.expires_at > now()
      and stored_party_status = 'ACTIVE'
    then
      resolved_guest := stored_guest;
    end if;
  end if;

  if resolved_guest.id is null then
    insert into public.dining_guests (
      branch,
      display_code,
      party_id,
      current_table_id,
      device_info,
      current_page
    )
    values (
      normalized_branch,
      public.create_dining_guest_display_code(normalized_branch),
      active_party.id,
      active_table.id,
      safe_device_info,
      safe_page
    )
    returning * into resolved_guest;

    insert into public.dining_guest_events (guest_id, event_type, detail)
    values (
      resolved_guest.id,
      'CREATED',
      jsonb_build_object(
        'party_id', active_party.id,
        'table_id', active_table.id,
        'table_code', active_table.table_code
      )
    );
  else
    if resolved_guest.current_page is distinct from safe_page then
      insert into public.dining_guest_events (guest_id, event_type, detail)
      values (
        resolved_guest.id,
        'PAGE_CHANGED',
        jsonb_build_object(
          'from', resolved_guest.current_page,
          'to', safe_page,
          'table_code', active_table.table_code
        )
      );
    end if;

    update public.dining_guests
    set last_seen_at = now(),
        current_table_id = active_table.id,
        current_page = safe_page,
        device_info = case
          when safe_device_info = '{}'::jsonb then device_info
          else safe_device_info
        end
    where id = resolved_guest.id
    returning * into resolved_guest;
  end if;

  select session.id
  into compatibility_session_id
  from public.dining_qr_sessions as session
  where session.branch = normalized_branch
    and session.qr_number = p_qr_number
    and session.status = 'active'
  order by session.started_at desc
  limit 1;

  return jsonb_build_object(
    'guest_id', resolved_guest.id,
    'display_code', resolved_guest.display_code,
    'guest_status', resolved_guest.status,
    'created_at', resolved_guest.created_at,
    'expires_at', resolved_guest.expires_at,
    'party_id', active_party.id,
    'party_status', active_party.status,
    'table_id', active_table.id,
    'table_code', active_table.table_code,
    'qr_number', p_qr_number,
    'qr_session_id', compatibility_session_id
  );
end;
$$;

create or replace function public.close_dining_party(
  p_branch text,
  p_party_id bigint,
  p_reason text default 'table-checkout'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_branch text := lower(trim(p_branch));
  active_party public.dining_parties;
  paid_guest_count integer := 0;
  completed_request_count integer := 0;
begin
  select party.*
  into active_party
  from public.dining_parties as party
  where party.id = p_party_id
    and party.branch = normalized_branch
    and party.status = 'ACTIVE'
  for update;

  if not found then
    raise exception 'Active Party not found';
  end if;

  update public.dining_qr_sessions as session
  set status = 'closed',
      ended_at = coalesce(session.ended_at, now()),
      ended_reason = left(coalesce(nullif(trim(p_reason), ''), 'party-paid'), 80)
  where session.branch = normalized_branch
    and session.status = 'active'
    and exists (
      select 1
      from public.dining_party_qrs as party_qr
      where party_qr.party_id = active_party.id
        and party_qr.branch = normalized_branch
        and party_qr.released_at is null
        and party_qr.qr_number = session.qr_number
    );

  update public.dining_requests
  set status = 'completed'
  where party_id = active_party.id
    and status not in ('completed', 'canceled');
  get diagnostics completed_request_count = row_count;

  with paid_guests as (
    update public.dining_guests
    set status = 'PAID',
        paid_at = coalesce(paid_at, now()),
        last_seen_at = now()
    where party_id = active_party.id
      and status = 'ACTIVE'
    returning id, display_code
  ),
  logged_events as (
    insert into public.dining_guest_events (guest_id, event_type, detail)
    select
      paid_guest.id,
      'PAID',
      jsonb_build_object(
        'display_code', paid_guest.display_code,
        'reason', 'party-checkout'
      )
    from paid_guests as paid_guest
    returning guest_id
  )
  select count(*)::integer
  into paid_guest_count
  from logged_events;

  update public.dining_party_tables
  set left_at = now()
  where party_id = active_party.id
    and left_at is null;

  update public.dining_tables
  set current_party_id = null
  where current_party_id = active_party.id;

  update public.dining_parties
  set status = 'CLOSED',
      closed_at = now(),
      closed_reason = left(coalesce(nullif(trim(p_reason), ''), 'party-paid'), 80),
      updated_at = now()
  where id = active_party.id;

  return jsonb_build_object(
    'party_id', active_party.id,
    'status', 'CLOSED',
    'payment_status', 'PAID',
    'paid_guest_count', paid_guest_count,
    'completed_request_count', completed_request_count
  );
end;
$$;

revoke all on function public.configure_dining_party_qrs(text, text[], integer[], bigint, integer) from public;
revoke all on function public.resolve_dining_guest(text, integer, uuid, jsonb, text) from public;
revoke all on function public.close_dining_party(text, bigint, text) from public;

grant execute on function public.configure_dining_party_qrs(text, text[], integer[], bigint, integer)
  to anon, authenticated;
grant execute on function public.resolve_dining_guest(text, integer, uuid, jsonb, text)
  to anon, authenticated;
grant execute on function public.close_dining_party(text, bigint, text)
  to anon, authenticated;

comment on column public.dining_parties.expected_guest_count is
  'Staff-entered Party headcount. Queen warns when active browser Guests exceed this number.';

commit;
