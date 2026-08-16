-- ============================================================
-- Cofre de dados do SM Hub — Lucas
-- Cole este arquivo inteiro no SQL Editor do Supabase e clique em Run.
-- Pode rodar mais de uma vez sem problema (ele pula o que já existe).
-- ============================================================

create table if not exists clients (
  key text primary key,
  name text not null,
  valor text,
  pillars text[] default '{}',
  cadencia text,
  objetivo text,
  icp text,
  portal_token text unique,
  updated_at timestamptz default now()
);

create table if not exists videos (
  id text primary key,
  client_key text references clients(key) on delete set null,
  title text,
  pillar text,
  date date,
  status text default 'pendente',
  gancho text,
  dev text,
  cta text,
  ref text,
  roteiro text,
  updated_at timestamptz default now()
);

create table if not exists finance_entries (
  id bigint generated always as identity primary key,
  month text not null,          -- '2026-08'
  type text not null,           -- 'receita' ou 'custo'
  name text,
  value numeric,
  updated_at timestamptz default now()
);

create table if not exists metrics (
  client_key text references clients(key) on delete cascade,
  month text not null,          -- '2026-08'
  data jsonb default '{}',
  primary key (client_key, month)
);

create table if not exists prospects (
  id text primary key,
  data jsonb default '{}',
  updated_at timestamptz default now()
);

create table if not exists mm_projects (
  id text primary key,
  name text not null,
  created_at timestamptz default now()
);

create table if not exists mm_maps (
  id text primary key,
  project_id text references mm_projects(id) on delete cascade,
  name text not null,
  nodes jsonb default '[]',
  edges jsonb default '[]',
  updated_at timestamptz default now()
);

create table if not exists app_state (
  key text primary key,         -- 'metas', 'processos', 'metas_mes', etc.
  data jsonb default '{}',
  updated_at timestamptz default now()
);

-- ============================================================
-- Trava de segurança: liga o cadeado em toda tabela.
-- Sem isso, qualquer pessoa que ache seu link consegue ler tudo.
-- ============================================================
alter table clients        enable row level security;
alter table videos         enable row level security;
alter table finance_entries enable row level security;
alter table metrics        enable row level security;
alter table prospects      enable row level security;
alter table mm_projects    enable row level security;
alter table mm_maps        enable row level security;
alter table app_state      enable row level security;

-- Você (dono, logado) pode ler e escrever tudo.
do $$
declare t text;
begin
  foreach t in array array['clients','videos','finance_entries','metrics','prospects','mm_projects','mm_maps','app_state']
  loop
    execute format(
      'drop policy if exists "dono acessa tudo" on %I;
       create policy "dono acessa tudo" on %I
       for all using (auth.role() = ''authenticated'')
       with check (auth.role() = ''authenticated'');',
      t, t);
  end loop;
end $$;

-- ============================================================
-- Portal do cliente: acesso público, mas só ENXERGA o próprio cliente,
-- e só se souber o código secreto (portal_token). Ninguém digita SQL —
-- isso é usado por uma função seca abaixo.
-- ============================================================
create or replace function portal_do_cliente(token text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'client', to_jsonb(c) - 'portal_token',
    'videos', coalesce((select jsonb_agg(to_jsonb(v) - 'client_key')
                         from videos v where v.client_key = c.key), '[]'::jsonb),
    'metrics', coalesce((select jsonb_object_agg(m.month, m.data)
                          from metrics m where m.client_key = c.key), '{}'::jsonb)
  )
  from clients c
  where c.portal_token = token;
$$;

grant execute on function portal_do_cliente(text) to anon;

-- ============================================================
-- Troca o financeiro inteiro de uma vez só, sem risco de duas
-- gravações quase juntas se atropelarem e duplicar linha.
-- ============================================================
create or replace function substituir_financeiro(entradas jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from finance_entries;
  insert into finance_entries (month, type, name, value)
  select (e->>'month'), (e->>'type'), (e->>'name'), (e->>'value')::numeric
  from jsonb_array_elements(entradas) e;
end;
$$;

grant execute on function substituir_financeiro(jsonb) to authenticated;
