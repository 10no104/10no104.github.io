-- Lightweight Realtime invalidation for the always-on Queen dining dashboard.
-- Source tables remain private; clients only receive a branch revision number.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.dining_realtime_signals (
  branch text primary key,
  revision bigint not null default 0 check (revision >= 0),
  updated_at timestamptz not null default now(),
  check (branch = lower(trim(branch)) and length(branch) between 1 and 40)
);

alter table public.dining_realtime_signals enable row level security;

revoke all on table public.dining_realtime_signals from anon, authenticated;
grant select on table public.dining_realtime_signals to anon, authenticated;

drop policy if exists dining_realtime_signals_select on public.dining_realtime_signals;
create policy dining_realtime_signals_select
on public.dining_realtime_signals
for select
to anon, authenticated
using (true);

create or replace function private.bump_dining_realtime_signal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data jsonb;
  branch_value text;
  relation_id bigint;
  signal_revision bigint;
begin
  row_data := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;

  -- Presence heartbeats update last_seen_at frequently. Only guest changes that
  -- affect the Queen dashboard should invalidate its snapshot.
  if tg_table_name = 'dining_guests' and tg_op = 'UPDATE' then
    if (to_jsonb(old) ->> 'party_id') is not distinct from (to_jsonb(new) ->> 'party_id')
      and (to_jsonb(old) ->> 'current_table_id') is not distinct from (to_jsonb(new) ->> 'current_table_id')
      and (to_jsonb(old) ->> 'status') is not distinct from (to_jsonb(new) ->> 'status')
      and (to_jsonb(old) ->> 'paid_at') is not distinct from (to_jsonb(new) ->> 'paid_at') then
      return new;
    end if;
  end if;

  branch_value := nullif(lower(trim(row_data ->> 'branch')), '');

  if branch_value is null and tg_argv[0] = 'party' then
    relation_id := nullif(row_data ->> 'party_id', '')::bigint;
    select lower(trim(party.branch))
      into branch_value
      from public.dining_parties as party
     where party.id = relation_id;
  elsif branch_value is null and tg_argv[0] = 'request' then
    relation_id := nullif(row_data ->> 'request_id', '')::bigint;
    select lower(trim(request.branch))
      into branch_value
      from public.dining_requests as request
     where request.id = relation_id;
  elsif branch_value is null and tg_argv[0] = 'guest' then
    select lower(trim(guest.branch))
      into branch_value
      from public.dining_guests as guest
     where guest.id = nullif(row_data ->> 'guest_id', '')::uuid;
  end if;

  if branch_value is not null then
    insert into public.dining_realtime_signals as signal (branch, revision, updated_at)
    values (branch_value, 1, now())
    on conflict (branch) do update
      set revision = signal.revision + 1,
          updated_at = excluded.updated_at
    returning revision into signal_revision;

    perform realtime.send(
      jsonb_build_object(
        'branch', branch_value,
        'revision', signal_revision
      ),
      'dining_changed',
      'dining:' || branch_value,
      false
    );
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.bump_dining_realtime_signal() from public, anon, authenticated;

drop trigger if exists dining_requests_realtime_signal on public.dining_requests;
create trigger dining_requests_realtime_signal
after insert or update or delete on public.dining_requests
for each row execute function private.bump_dining_realtime_signal('direct');

drop trigger if exists dining_qr_sessions_realtime_signal on public.dining_qr_sessions;
create trigger dining_qr_sessions_realtime_signal
after insert or update or delete on public.dining_qr_sessions
for each row execute function private.bump_dining_realtime_signal('direct');

drop trigger if exists dining_table_layouts_realtime_signal on public.dining_table_layouts;
create trigger dining_table_layouts_realtime_signal
after insert or update or delete on public.dining_table_layouts
for each row execute function private.bump_dining_realtime_signal('direct');

drop trigger if exists dining_parties_realtime_signal on public.dining_parties;
create trigger dining_parties_realtime_signal
after insert or update or delete on public.dining_parties
for each row execute function private.bump_dining_realtime_signal('direct');

drop trigger if exists dining_tables_realtime_signal on public.dining_tables;
create trigger dining_tables_realtime_signal
after insert or update or delete on public.dining_tables
for each row execute function private.bump_dining_realtime_signal('direct');

drop trigger if exists dining_party_qrs_realtime_signal on public.dining_party_qrs;
create trigger dining_party_qrs_realtime_signal
after insert or update or delete on public.dining_party_qrs
for each row execute function private.bump_dining_realtime_signal('direct');

drop trigger if exists dining_party_tables_realtime_signal on public.dining_party_tables;
create trigger dining_party_tables_realtime_signal
after insert or update or delete on public.dining_party_tables
for each row execute function private.bump_dining_realtime_signal('party');

drop trigger if exists dining_guests_realtime_signal on public.dining_guests;
create trigger dining_guests_realtime_signal
after insert or update of party_id, current_table_id, status, paid_at or delete
on public.dining_guests
for each row execute function private.bump_dining_realtime_signal('direct');

drop trigger if exists dining_order_items_realtime_signal on public.dining_order_items;
create trigger dining_order_items_realtime_signal
after insert or update or delete on public.dining_order_items
for each row execute function private.bump_dining_realtime_signal('request');

drop trigger if exists dining_order_events_realtime_signal on public.dining_order_events;
create trigger dining_order_events_realtime_signal
after insert or update or delete on public.dining_order_events
for each row execute function private.bump_dining_realtime_signal('request');

drop trigger if exists dining_guest_events_realtime_signal on public.dining_guest_events;
create trigger dining_guest_events_realtime_signal
after insert or update or delete on public.dining_guest_events
for each row execute function private.bump_dining_realtime_signal('guest');

insert into public.dining_realtime_signals (branch)
values ('downtown'), ('uptown')
on conflict (branch) do nothing;

do $$
begin
  if exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'dining_realtime_signals'
  ) then
    alter publication supabase_realtime drop table public.dining_realtime_signals;
  end if;
end;
$$;

comment on table public.dining_realtime_signals is
  'Branch-level revision used by Queen Realtime Broadcast and its low-egress polling fallback.';
