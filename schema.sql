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

-- membro da equipe vinculado ao login atual
create or replace function public.acordos_meu_membro() returns text
language sql stable security definer set search_path = public as $$
  select v.data->>'membroId' from public.acordos_docs v where v.col = 'vinculos' and v.id = auth.uid()::text limit 1;
$$;
grant execute on function public.acordos_meu_membro() to authenticated;

-- administrador, coordenador ou diretoria veem as tarefas de todos
create or replace function public.acordos_ve_tudo() returns boolean
language sql stable security definer set search_path = public as $$
  select public.acordos_is_admin() or exists(
    select 1 from public.acordos_docs e where e.col = 'equipe' and e.id = public.acordos_meu_membro()
      and coalesce(e.data->>'papel','integrante') in ('coordenador','diretoria'));
$$;
grant execute on function public.acordos_ve_tudo() to authenticated;

drop policy if exists acordos_ler on public.acordos_docs;
create policy acordos_ler on public.acordos_docs for select to authenticated
  using (case
    when col = 'conferencia' then public.acordos_is_admin()
    when col = 'tarefas' then public.acordos_ve_tudo() or data->>'responsavel' = public.acordos_meu_membro()
    else true end);

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
-- Registro de atividades (auditoria), gravado pelo banco
create table if not exists public.acordos_log (
  id bigserial primary key,
  ts timestamptz not null default now(),
  uid uuid,
  email text,
  acao text not null,
  col text,
  doc_id text,
  rotulo text,
  campos text[],
  detalhe jsonb
);
create index if not exists acordos_log_ts on public.acordos_log (ts desc);
alter table public.acordos_log enable row level security;
drop policy if exists acordos_log_ler on public.acordos_log;
create policy acordos_log_ler on public.acordos_log for select to authenticated using (public.acordos_is_admin());
-- sem politicas de insert/update/delete: ninguem altera o registro pelo app

create or replace function public.acordos_log_trg() returns trigger
language plpgsql security definer set search_path = public as $$
declare r jsonb; o jsonb; ch text[]; rot text; c text; i text;
begin
  if tg_op = 'DELETE' then r := old.data; c := old.col; i := old.id; else r := new.data; c := new.col; i := new.id; end if;
  if tg_op = 'UPDATE' then
    o := old.data;
    select array_agg(k) into ch from (
      select coalesce(n.key, x.key) k from jsonb_each(r) n full join jsonb_each(o) x on n.key = x.key
      where n.value is distinct from x.value) z;
    if ch is null then return null; end if;
  end if;
  rot := coalesce(r->>'nome', r->>'titulo', r->>'numero', r->>'cliente', r->>'descricao', r->>'resumo', '');
  insert into public.acordos_log (uid, email, acao, col, doc_id, rotulo, campos, detalhe)
  values (auth.uid(), auth.jwt()->>'email', lower(tg_op), c, i, left(rot, 200), ch,
          jsonb_strip_nulls(jsonb_build_object('status', r->'status', 'etapa', r->'etapa', 'resultado', r->'resultado', 'canal', r->'canal')));
  return null;
end $$;

drop trigger if exists acordos_log_aiud on public.acordos_docs;
create trigger acordos_log_aiud after insert or update or delete on public.acordos_docs
for each row execute function public.acordos_log_trg();

create or replace function public.acordos_registrar(acao text, rotulo text default null) returns void
language sql security definer set search_path = public as $$
  insert into public.acordos_log (uid, email, acao, rotulo)
  select auth.uid(), auth.jwt()->>'email', acao, left(rotulo, 200)
  where auth.uid() is not null and acao in ('acesso', 'saida');
$$;
revoke all on function public.acordos_registrar(text, text) from public, anon;
grant execute on function public.acordos_registrar(text, text) to authenticated;

select 'ok' as resultado;
