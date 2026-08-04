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
