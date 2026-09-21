-- =====================================================================
-- GRIMÓRIO — Banco de dados (Supabase / PostgreSQL)
-- Como usar: Supabase > SQL Editor > New query > cole tudo > Run.
-- Rode em um projeto novo (o script cria tabelas e usuários do zero).
-- =====================================================================


-- =====================================================================
-- PASSO 1 — Perfis e papel de mestre
-- =====================================================================
create extension if not exists pgcrypto with schema extensions;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text not null,
  role text not null check (role in ('master', 'player'))
);

create or replace function public.is_master()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'master'
  );
$$;


-- =====================================================================
-- PASSO 2 — Tabelas do jogo
-- Biblioteca > Campanha > Fichas / Monstros / Mapas (com waypoints)
-- =====================================================================
create table public.libraries (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text default '',
  color text default '#7a2630',
  hp_label text default 'Vida',
  mana_label text default 'Mana',
  default_attrs text[] default '{}',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.campaigns (
  id uuid primary key default gen_random_uuid(),
  library_id uuid not null references public.libraries(id) on delete cascade,
  name text not null,
  synopsis text default '',
  cover text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.characters (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  owner_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  name text not null,
  subtitle text default '',
  portrait text,
  hp_cur int default 10,  hp_max int default 10,
  mana_cur int default 5, mana_max int default 5,
  attrs jsonb default '[]',
  items jsonb default '[]',
  sections jsonb default '[]',
  gallery text[] default '{}',
  notes text default '',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.monsters (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  name text not null,
  subtitle text default '',
  portrait text,
  hp_cur int default 10,  hp_max int default 10,
  mana_cur int default 5, mana_max int default 5,
  attrs jsonb default '[]',
  items jsonb default '[]',
  sections jsonb default '[]',
  gallery text[] default '{}',
  notes text default '',
  visible boolean default false,      -- aparece no bestiário dos jogadores
  reveal_name boolean default false,  -- jogadores veem o nome
  in_field boolean default false,     -- "ativo em campo" no Modo Jogo
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- O que os jogadores podem ver dos monstros (preenchida pelo gatilho do passo 3)
create table public.monsters_public (
  id uuid primary key references public.monsters(id) on delete cascade,
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  name text,
  portrait text,
  hp_cur int, hp_max int,
  mana_cur int, mana_max int,
  visible boolean default false,
  in_field boolean default false
);

create table public.maps (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  name text not null default 'Mapa',
  image text not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.waypoints (
  id uuid primary key default gen_random_uuid(),
  map_id uuid not null references public.maps(id) on delete cascade,
  title text not null default 'Local',
  description text default '',
  color text default '#d8b060',
  x numeric(5,2) not null check (x between 0 and 100),
  y numeric(5,2) not null check (y between 0 and 100),
  images text[] default '{}',
  created_at timestamptz default now()
);

create index on public.campaigns (library_id);
create index on public.characters (campaign_id);
create index on public.monsters (campaign_id);
create index on public.monsters_public (campaign_id);
create index on public.maps (campaign_id);
create index on public.waypoints (map_id);

-- Atualiza updated_at automaticamente a cada edição
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

create trigger t_libraries  before update on public.libraries  for each row execute function public.touch_updated_at();
create trigger t_campaigns  before update on public.campaigns  for each row execute function public.touch_updated_at();
create trigger t_characters before update on public.characters for each row execute function public.touch_updated_at();
create trigger t_monsters   before update on public.monsters   for each row execute function public.touch_updated_at();
create trigger t_maps       before update on public.maps       for each row execute function public.touch_updated_at();


-- =====================================================================
-- PASSO 3 — Esconder os monstros de verdade
-- Visível no bestiário OU ativo em campo: copia só nome (se revelado),
-- imagem, vida e mana para monsters_public. Nenhum dos dois: remove a cópia.
-- Bestiário dos jogadores: where visible. Modo Jogo: where in_field.
-- =====================================================================
create or replace function public.sync_monster_public()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.visible or new.in_field then
    insert into public.monsters_public
      (id, campaign_id, name, portrait, hp_cur, hp_max, mana_cur, mana_max, visible, in_field)
    values
      (new.id, new.campaign_id,
       case when new.reveal_name then new.name end,
       new.portrait, new.hp_cur, new.hp_max, new.mana_cur, new.mana_max,
       new.visible, new.in_field)
    on conflict (id) do update set
      campaign_id = excluded.campaign_id,
      name        = excluded.name,
      portrait    = excluded.portrait,
      hp_cur      = excluded.hp_cur,
      hp_max      = excluded.hp_max,
      mana_cur    = excluded.mana_cur,
      mana_max    = excluded.mana_max,
      visible     = excluded.visible,
      in_field    = excluded.in_field;
  else
    delete from public.monsters_public where id = new.id;
  end if;
  return new;
end $$;

create trigger monsters_sync
after insert or update on public.monsters
for each row execute function public.sync_monster_public();


-- =====================================================================
-- PASSO 4 — Permissões (RLS)
-- =====================================================================
alter table public.profiles        enable row level security;
alter table public.libraries       enable row level security;
alter table public.campaigns       enable row level security;
alter table public.characters      enable row level security;
alter table public.monsters        enable row level security;
alter table public.monsters_public enable row level security;
alter table public.maps            enable row level security;
alter table public.waypoints       enable row level security;

-- Perfis
create policy "logados leem perfis" on public.profiles
  for select to authenticated using (true);

-- Bibliotecas, campanhas, mapas e pontos: todos leem, só o mestre escreve
create policy "logados leem" on public.libraries for select to authenticated using (true);
create policy "mestre escreve" on public.libraries for all to authenticated
  using (public.is_master()) with check (public.is_master());

create policy "logados leem" on public.campaigns for select to authenticated using (true);
create policy "mestre escreve" on public.campaigns for all to authenticated
  using (public.is_master()) with check (public.is_master());

create policy "logados leem" on public.maps for select to authenticated using (true);
create policy "mestre escreve" on public.maps for all to authenticated
  using (public.is_master()) with check (public.is_master());

create policy "logados leem" on public.waypoints for select to authenticated using (true);
create policy "mestre escreve" on public.waypoints for all to authenticated
  using (public.is_master()) with check (public.is_master());

-- Fichas: todos leem, dono ou mestre alteram
create policy "logados leem fichas" on public.characters
  for select to authenticated using (true);
create policy "criar ficha" on public.characters
  for insert to authenticated
  with check (owner_id = auth.uid() or public.is_master());
create policy "editar ficha" on public.characters
  for update to authenticated
  using (owner_id = auth.uid() or public.is_master())
  with check (owner_id = auth.uid() or public.is_master());
create policy "excluir ficha" on public.characters
  for delete to authenticated
  using (owner_id = auth.uid() or public.is_master());

-- Monstros completos: só o mestre
create policy "só o mestre" on public.monsters for all to authenticated
  using (public.is_master()) with check (public.is_master());

-- Versão pública dos monstros: todos leem, ninguém escreve direto
create policy "logados leem monstros visíveis" on public.monsters_public
  for select to authenticated using (true);


-- =====================================================================
-- PASSO 5 — Armazenamento das imagens (bucket "imagens")
-- =====================================================================
insert into storage.buckets (id, name, public)
values ('imagens', 'imagens', true)
on conflict (id) do nothing;

create policy "logados enviam imagens" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'imagens');

create policy "dono ou mestre apaga imagens" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'imagens'
    and (owner_id = auth.uid()::text or public.is_master())
  );


-- =====================================================================
-- PASSO 6 — Tempo real
-- =====================================================================
alter publication supabase_realtime add table
  public.libraries, public.campaigns, public.characters,
  public.monsters, public.monsters_public, public.maps, public.waypoints;


-- =====================================================================
-- PASSO 7 — Usuários da mesa
-- Login no app: "Jogador 1" vira jogador1@grimorio.app por trás.
-- Criados via SQL porque o painel exige senha com 6+ caracteres.
-- =====================================================================
do $$
declare
  u record;
  new_id uuid;
begin
  for u in
    select * from (values
      ('jogador1', 'Jogador 1', '12341',     'player'),
      ('jogador2', 'Jogador 2', '12342',     'player'),
      ('jogador3', 'Jogador 3', '12343',     'player'),
      ('jogador4', 'Jogador 4', '12344',     'player'),
      ('mestre',   'Mestre',    'mestre123', 'master')
    ) as t(username, display_name, pass, role)
  loop
    new_id := gen_random_uuid();

    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at,
      confirmation_token, email_change, email_change_token_new, recovery_token
    ) values (
      '00000000-0000-0000-0000-000000000000', new_id, 'authenticated', 'authenticated',
      u.username || '@grimorio.app',
      extensions.crypt(u.pass, extensions.gen_salt('bf')),
      now(), '{"provider":"email","providers":["email"]}',
      jsonb_build_object('username', u.username),
      now(), now(), '', '', '', ''
    );

    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), new_id, new_id::text,
      jsonb_build_object('sub', new_id::text, 'email', u.username || '@grimorio.app', 'email_verified', true),
      'email', now(), now(), now()
    );

    insert into public.profiles (id, username, display_name, role)
    values (new_id, u.username, u.display_name, u.role);
  end loop;
end $$;


-- =====================================================================
-- CONFERÊNCIA — deve listar os 5 usuários
-- =====================================================================
select p.display_name, p.role, u.email
from public.profiles p
join auth.users u on u.id = p.id
order by p.username;
