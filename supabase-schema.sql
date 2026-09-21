create table if not exists public.grimorio_data (
  collection text not null,
  id text not null,
  data jsonb not null default '{}'::jsonb,
  primary key (collection, id)
);

create table if not exists public.grimorio_images (
  id text primary key,
  data text not null,
  created_at timestamptz not null default now()
);

alter table public.grimorio_data enable row level security;
alter table public.grimorio_images enable row level security;

drop policy if exists "grimorio_data_anon_all" on public.grimorio_data;
create policy "grimorio_data_anon_all"
on public.grimorio_data for all
to anon
using (true)
with check (true);

drop policy if exists "grimorio_images_anon_all" on public.grimorio_images;
create policy "grimorio_images_anon_all"
on public.grimorio_images for all
to anon
using (true)
with check (true);

do $$
begin
  alter publication supabase_realtime add table public.grimorio_data;
exception
  when duplicate_object then null;
end $$;
