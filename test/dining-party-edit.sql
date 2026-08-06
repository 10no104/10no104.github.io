-- Enable Queen to edit an active Party without closing its dining session.
-- Run after tools/sql/dining-party-operational-guards.sql.

begin;

create or replace function public.update_dining_party_setup(
  p_branch text,
  p_party_id bigint,
  p_table_codes text[],
  p_expected_guest_count integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_branch text := lower(trim(p_branch));
  normalized_codes text[] := array[]::text[];
  selected_code text;
  selected_table public.dining_tables;
  active_party public.dining_parties;
  selected_table_ids bigint[] := array[]::bigint[];
  fallback_table_id bigint;
  fallback_table_code text;
begin
  if normalized_branch is null or normalized_branch !~ '^[a-z0-9_-]{1,40}$' then
    raise exception 'Invalid branch';
  end if;
  if p_party_id is null then
    raise exception 'Party id is required';
  end if;
  if p_expected_guest_count is null or p_expected_guest_count not between 1 and 100 then
    raise exception 'Expected guest count must be between 1 and 100';
  end if;

  for selected_code in
    select candidate.code
    from (
      select distinct on (lower(trim(input.code)))
        trim(input.code) as code,
        input.position
      from unnest(coalesce(p_table_codes, array[]::text[]))
        with ordinality as input(code, position)
      where nullif(trim(input.code), '') is not null
      order by lower(trim(input.code)), input.position
    ) as candidate
    order by candidate.position
  loop
    if char_length(selected_code) > 40 then
      raise exception 'Invalid table code';
    end if;
    normalized_codes := array_append(normalized_codes, selected_code);
  end loop;

  if coalesce(array_length(normalized_codes, 1), 0) not between 1 and 30 then
    raise exception 'Select between 1 and 30 tables';
  end if;

  perform pg_advisory_xact_lock(hashtext('party-qr:' || normalized_branch));

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

  foreach selected_code in array normalized_codes loop
    selected_table := null;
    select table_record.*
    into selected_table
    from public.dining_tables as table_record
    where table_record.branch = normalized_branch
      and lower(table_record.table_code) = lower(selected_code)
    for update;

    if selected_table.id is null then
      insert into public.dining_tables (branch, table_code)
      values (normalized_branch, selected_code)
      returning * into selected_table;
    elsif selected_table.current_party_id is not null
      and selected_table.current_party_id <> active_party.id
    then
      raise exception 'Table % already belongs to another active Party', selected_table.table_code;
    end if;

    selected_table_ids := array_append(selected_table_ids, selected_table.id);
  end loop;

  fallback_table_id := selected_table_ids[1];
  select table_record.table_code
  into fallback_table_code
  from public.dining_tables as table_record
  where table_record.id = fallback_table_id;

  update public.dining_party_tables as party_table
  set left_at = now()
  where party_table.party_id = active_party.id
    and party_table.left_at is null
    and not (party_table.table_id = any(selected_table_ids));

  insert into public.dining_party_tables (party_id, table_id)
  select active_party.id, selected_id
  from unnest(selected_table_ids) as selected(selected_id)
  where not exists (
    select 1
    from public.dining_party_tables as party_table
    where party_table.party_id = active_party.id
      and party_table.table_id = selected.selected_id
      and party_table.left_at is null
  );

  update public.dining_party_qrs as party_qr
  set table_id = fallback_table_id
  where party_qr.party_id = active_party.id
    and party_qr.released_at is null
    and not (party_qr.table_id = any(selected_table_ids));

  update public.dining_guests as guest
  set current_table_id = fallback_table_id,
      last_seen_at = now()
  where guest.party_id = active_party.id
    and guest.status = 'ACTIVE'
    and not (guest.current_table_id = any(selected_table_ids));

  update public.dining_tables as table_record
  set current_party_id = null
  where table_record.current_party_id = active_party.id
    and not (table_record.id = any(selected_table_ids));

  update public.dining_tables as table_record
  set current_party_id = active_party.id
  where table_record.id = any(selected_table_ids);

  update public.dining_qr_sessions as session
  set table_code = fallback_table_code
  where session.branch = normalized_branch
    and session.status = 'active'
    and exists (
      select 1
      from public.dining_party_qrs as party_qr
      where party_qr.party_id = active_party.id
        and party_qr.released_at is null
        and party_qr.qr_number = session.qr_number
    );

  update public.dining_parties
  set expected_guest_count = p_expected_guest_count,
      updated_at = now()
  where id = active_party.id;

  return jsonb_build_object(
    'party_id', active_party.id,
    'status', active_party.status,
    'table_codes', normalized_codes,
    'expected_guest_count', p_expected_guest_count
  );
end;
$$;

revoke all on function public.update_dining_party_setup(text, bigint, text[], integer) from public;
grant execute on function public.update_dining_party_setup(text, bigint, text[], integer)
  to anon, authenticated;

commit;
