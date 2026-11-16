-- Setor de Acordos D'Freire: banco do site
create table if not exists public.acordos_docs (
  col text not null,
  id text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  primary key (col, id)
);
alter table public.acordos_docs replica identity full;

create table if not exists public.acordos_admins (email text primary key);
alter table public.acordos_admins enable row level security;

create or replace function public.acordos_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.acordos_admins a where lower(a.email) = lower(auth.jwt()->>'email'));
$$;
grant execute on function public.acordos_is_admin() to authenticated;

alter table public.acordos_docs enable row level security;

drop policy if exists acordos_ler on public.acordos_docs;
create policy acordos_ler on public.acordos_docs for select to authenticated
  using (col <> 'conferencia' or public.acordos_is_admin());

drop policy if exists acordos_inserir on public.acordos_docs;
create policy acordos_inserir on public.acordos_docs for insert to authenticated
  with check (
    case
      when col in ('equipe','config','nichos','conferencia') then public.acordos_is_admin()
      when col = 'vinculos' then public.acordos_is_admin() or (
        id = auth.uid()::text and (data->>'membroId') in (
          select e.id from public.acordos_docs e where e.col = 'equipe' and coalesce(e.data->>'papel','integrante') = 'integrante'))
      else true end);

drop policy if exists acordos_alterar on public.acordos_docs;
create policy acordos_alterar on public.acordos_docs for update to authenticated
  using (
    case
      when col in ('equipe','config','nichos','conferencia') then public.acordos_is_admin()
      when col = 'vinculos' then public.acordos_is_admin() or id = auth.uid()::text
      else true end)
  with check (
    case
      when col in ('equipe','config','nichos','conferencia') then public.acordos_is_admin()
      when col = 'vinculos' then public.acordos_is_admin() or (
        id = auth.uid()::text and (data->>'membroId') in (
          select e.id from public.acordos_docs e where e.col = 'equipe' and coalesce(e.data->>'papel','integrante') = 'integrante'))
      else true end);

drop policy if exists acordos_apagar on public.acordos_docs;
create policy acordos_apagar on public.acordos_docs for delete to authenticated
  using (
    case
      when col in ('equipe','config','nichos','conferencia','vinculos') then public.acordos_is_admin()
      else true end);

do $$ begin
  alter publication supabase_realtime add table public.acordos_docs;
exception when duplicate_object then null; end $$;
