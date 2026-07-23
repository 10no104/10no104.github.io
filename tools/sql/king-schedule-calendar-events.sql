-- King schedule calendar events (admin-managed).
-- Run this in Supabase SQL Editor after the existing Noble scheduling schema.

create extension if not exists pgcrypto;

create table if not exists public.king_schedule_calendar_events (
  id uuid primary key default gen_random_uuid(),
  event_date date not null,
  title text not null check (char_length(trim(title)) between 1 and 80),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists king_schedule_calendar_events_date_idx
  on public.king_schedule_calendar_events (event_date);

create or replace function public.king_schedule_calendar_events_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists king_schedule_calendar_events_touch_updated_at on public.king_schedule_calendar_events;
create trigger king_schedule_calendar_events_touch_updated_at
before update on public.king_schedule_calendar_events
for each row execute function public.king_schedule_calendar_events_touch_updated_at();

alter table public.king_schedule_calendar_events enable row level security;

drop policy if exists king_schedule_calendar_events_admin_all on public.king_schedule_calendar_events;
create policy king_schedule_calendar_events_admin_all
on public.king_schedule_calendar_events
for all
to authenticated
using (true)
with check (true);
