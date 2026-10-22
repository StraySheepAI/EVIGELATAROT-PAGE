-- EVIGILA AULA · esquema inicial para activaciones por tríadas.
-- Ejecutar en el SQL Editor del proyecto EVIGILATAROT_AULA.

create extension if not exists pgcrypto;

create table if not exists public.access_keys (
  id uuid primary key default gen_random_uuid(),
  label text not null unique,
  code_hash text not null unique,
  max_activations integer not null default 3 check (max_activations > 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.access_activations (
  id uuid primary key default gen_random_uuid(),
  access_key_id uuid not null references public.access_keys(id) on delete restrict,
  email text not null,
  auth_user_id uuid references auth.users(id) on delete set null,
  status text not null default 'active' check (status in ('pending','active','revoked')),
  created_at timestamptz not null default now(),
  unique (access_key_id, email)
);

create index if not exists access_activations_email_idx on public.access_activations (lower(email));

create table if not exists public.saved_readings (
  id uuid primary key default gen_random_uuid(),
  access_key_id uuid not null references public.access_keys(id) on delete restrict,
  email text not null,
  spread_id text not null,
  cards text not null,
  orientations text not null default '',
  response text not null default '',
  question text not null default '',
  action text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists saved_readings_email_idx
  on public.saved_readings (lower(email), created_at desc);

create table if not exists public.system_health (
  id integer primary key check (id = 1),
  label text not null default 'EVIGILA health check',
  touched_at timestamptz not null default now()
);

insert into public.system_health (id) values (1) on conflict (id) do nothing;

alter table public.access_keys enable row level security;
alter table public.access_activations enable row level security;
alter table public.saved_readings enable row level security;
alter table public.system_health enable row level security;

drop policy if exists "health check is readable" on public.system_health;
create policy "health check is readable" on public.system_health
  for select to anon, authenticated using (true);

create or replace function public.normalize_evigila_code(raw_code text)
returns text
language sql
immutable
as $$
  select upper(regexp_replace(coalesce(raw_code, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

create or replace function public.activate_evigila_code(p_code text, p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_code text := public.normalize_evigila_code(p_code);
  normalized_email text := lower(trim(coalesce(p_email, '')));
  key_row public.access_keys%rowtype;
  used_count integer;
begin
  if normalized_code = '' or normalized_email = '' or position('@' in normalized_email) = 0 then
    return jsonb_build_object('ok', false, 'error', 'missing_code_or_email');
  end if;

  select * into key_row
  from public.access_keys
  where active = true
    and code_hash = encode(extensions.digest(normalized_code, 'sha256'::text), 'hex')
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;

  select count(*) into used_count
  from public.access_activations
  where access_key_id = key_row.id and status <> 'revoked';

  if exists (select 1 from public.access_activations where access_key_id = key_row.id and lower(email) = normalized_email and status <> 'revoked') then
    return jsonb_build_object('ok', true, 'already_active', true, 'key_label', key_row.label);
  end if;

  if used_count >= key_row.max_activations then
    return jsonb_build_object('ok', false, 'error', 'trio_complete');
  end if;

  insert into public.access_activations (access_key_id, email, status)
  values (key_row.id, normalized_email, 'pending');

  return jsonb_build_object('ok', true, 'already_active', false, 'key_label', key_row.label, 'remaining', key_row.max_activations - used_count - 1);
end;
$$;

revoke all on function public.activate_evigila_code(text, text) from public;
grant execute on function public.activate_evigila_code(text, text) to anon, authenticated;

create or replace function public.save_evigila_reading(
  p_code text,
  p_email text,
  p_reading jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_code text := public.normalize_evigila_code(p_code);
  normalized_email text := lower(trim(coalesce(p_email, '')));
  key_id uuid;
  reading_id uuid;
begin
  select k.id into key_id
  from public.access_keys k
  join public.access_activations a on a.access_key_id = k.id
  where k.active = true
    and k.code_hash = encode(extensions.digest(normalized_code, 'sha256'::text), 'hex')
    and lower(a.email) = normalized_email
    and a.status <> 'revoked';

  if key_id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_access');
  end if;

  insert into public.saved_readings (
    access_key_id, email, spread_id, cards, orientations, response, question, action
  )
  values (
    key_id,
    normalized_email,
    coalesce(p_reading->>'tirada_id', 'tres-umbrales'),
    coalesce(p_reading->>'cartas', ''),
    coalesce(p_reading->>'orientaciones', ''),
    coalesce(p_reading->>'respuesta_mostrada', ''),
    coalesce(p_reading->>'pregunta', ''),
    coalesce(p_reading->>'accion', '')
  )
  returning id into reading_id;

  return jsonb_build_object('ok', true, 'id', reading_id);
end;
$$;

create or replace function public.list_evigila_readings(
  p_code text,
  p_email text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_code text := public.normalize_evigila_code(p_code);
  normalized_email text := lower(trim(coalesce(p_email, '')));
  key_id uuid;
  readings jsonb;
begin
  select k.id into key_id
  from public.access_keys k
  join public.access_activations a on a.access_key_id = k.id
  where k.active = true
    and k.code_hash = encode(extensions.digest(normalized_code, 'sha256'::text), 'hex')
    and lower(a.email) = normalized_email
    and a.status <> 'revoked';

  if key_id is null then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.created_at desc), '[]'::jsonb)
  into readings
  from (
    select id, spread_id, cards, orientations, response, question, action, created_at
    from public.saved_readings
    where access_key_id = key_id and lower(email) = normalized_email
    order by created_at desc
    limit 50
  ) as row_data;

  return readings;
end;
$$;

revoke all on function public.save_evigila_reading(text, text, jsonb) from public;
grant execute on function public.save_evigila_reading(text, text, jsonb) to anon, authenticated;
revoke all on function public.list_evigila_readings(text, text) from public;
grant execute on function public.list_evigila_readings(text, text) to anon, authenticated;

-- Las claves se cargan después, desde el SQL Editor privado, usando:
-- insert into public.access_keys (label, code_hash, max_activations)
-- values ('NOMBRE-DE-CLAVE', encode(extensions.digest(public.normalize_evigila_code('CLAVE-REAL'), 'sha256'::text), 'hex'), 3);
-- Nunca pongas las claves reales en la página ni en un archivo público.
