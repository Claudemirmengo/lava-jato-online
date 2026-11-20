-- =====================================================================
-- LAVA JATO ONLINE: estrutura do banco de dados (Supabase / PostgreSQL)
-- Cole TUDO no "SQL Editor" do Supabase e clique em Run (uma vez só).
-- =====================================================================

-- Tabelas ------------------------------------------------------------
create table public.admins (
  id uuid primary key references auth.users(id) on delete cascade
);

create table public.servicos (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  preco numeric(10,2) not null default 0,
  simples boolean not null default false,   -- serviço da promoção "10ª lavagem grátis"
  completa boolean not null default false   -- serviço do brinde de aniversário
);

create table public.clientes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete set null,
  nome text not null,
  tel text not null,
  email text,
  nasc date,
  aniv_ano int,                             -- ano em que o brinde de aniversário foi usado
  criado_em timestamptz not null default now()
);
create unique index clientes_tel_uk on public.clientes (right(regexp_replace(tel, '\D', '', 'g'), 9));

create table public.veiculos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id) on delete cascade,
  placa text not null default '',
  modelo text not null default '',
  ciclo int not null default 0 check (ciclo between 0 and 9)   -- lavagens pagas no cartão
);
create unique index veiculos_placa_uk on public.veiculos (placa) where placa <> '';

create table public.caixas (
  id uuid primary key default gen_random_uuid(),
  aberto_em timestamptz not null default now(),
  troco numeric(10,2) not null default 0,
  fechado_em timestamptz,
  contado numeric(10,2)
);

create table public.fila (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid references public.clientes(id) on delete set null,
  veiculo_id uuid references public.veiculos(id) on delete set null,
  nome text not null,
  placa text not null default '',
  servico_id uuid references public.servicos(id) on delete set null,
  servico text not null,
  preco numeric(10,2) not null,
  obs text not null default '',
  status text not null default 'Na fila' check (status in ('Na fila', 'Lavando', 'Pronto')),
  recebido_em timestamptz not null default now()
);

create table public.lancamentos (
  id uuid primary key default gen_random_uuid(),
  caixa_id uuid not null references public.caixas(id),
  tipo text not null check (tipo in ('lav', 'desp', 'reforco')),
  cliente_id uuid references public.clientes(id) on delete set null,
  veiculo_id uuid references public.veiculos(id) on delete set null,
  nome text not null default '',
  placa text not null default '',
  servico text not null default '',
  valor numeric(10,2) not null default 0,
  forma text not null default 'Dinheiro',
  gratis boolean not null default false,
  aniv boolean not null default false,
  recebido_em timestamptz,
  criado_em timestamptz not null default now()
);

-- Segurança (cada cliente só enxerga os próprios dados) ----------------
alter table public.admins      enable row level security;
alter table public.servicos    enable row level security;
alter table public.clientes    enable row level security;
alter table public.veiculos    enable row level security;
alter table public.caixas      enable row level security;
alter table public.fila        enable row level security;
alter table public.lancamentos enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where id = auth.uid())
$$;

create policy "admin ve a si mesmo" on public.admins for select to authenticated using (id = auth.uid());

do $$
declare t text;
begin
  foreach t in array array['servicos','clientes','veiculos','caixas','fila','lancamentos'] loop
    execute format('create policy "admin total" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

create policy "todos veem os servicos" on public.servicos for select to anon, authenticated using (true);
create policy "cliente ve o proprio cadastro" on public.clientes for select to authenticated using (user_id = auth.uid());
create policy "cliente ve os proprios veiculos" on public.veiculos for select to authenticated
  using (exists (select 1 from public.clientes c where c.id = cliente_id and c.user_id = auth.uid()));
create policy "cliente ve a propria fila" on public.fila for select to authenticated
  using (exists (select 1 from public.clientes c where c.id = cliente_id and c.user_id = auth.uid()));
create policy "cliente ve os proprios lancamentos" on public.lancamentos for select to authenticated
  using (exists (select 1 from public.clientes c where c.id = cliente_id and c.user_id = auth.uid()));

-- Funções (regras de negócio ficam no servidor) ------------------------

-- Cliente: cria o cadastro (ou vincula a um cadastro feito no balcão, conferindo telefone e nascimento)
create or replace function public.cadastrar_conta(p_nome text, p_tel text, p_nasc date, p_placa text, p_modelo text)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  t text := right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 9);
  pl text := upper(regexp_replace(coalesce(p_placa, ''), '[\s-]', '', 'g'));
  c public.clientes%rowtype;
  mail text;
begin
  if uid is null then raise exception 'Faça login primeiro.'; end if;
  if exists (select 1 from public.clientes where user_id = uid) then return; end if;
  if coalesce(p_nome, '') = '' or length(t) < 8 or p_nasc is null then
    raise exception 'Informe nome, telefone e data de nascimento.';
  end if;
  select email into mail from auth.users where id = uid;
  select * into c from public.clientes where right(regexp_replace(tel, '\D', '', 'g'), 9) = t limit 1;
  if found then
    if c.user_id is not null then raise exception 'Esse telefone já tem uma conta.'; end if;
    if c.nasc is distinct from p_nasc then raise exception 'A data de nascimento não confere com o cadastro do balcão.'; end if;
    update public.clientes set user_id = uid, email = mail where id = c.id;
  else
    insert into public.clientes (user_id, nome, tel, nasc, email) values (uid, p_nome, p_tel, p_nasc, mail) returning * into c;
  end if;
  if pl <> '' and not exists (select 1 from public.veiculos where placa = pl) then
    insert into public.veiculos (cliente_id, placa, modelo) values (c.id, pl, coalesce(p_modelo, ''));
  end if;
end $$;

-- Cliente: vincula mais um veículo ao próprio cadastro
create or replace function public.vincular_veiculo(p_placa text, p_modelo text)
returns void language plpgsql security definer set search_path = public as $$
declare
  c public.clientes%rowtype;
  pl text := upper(regexp_replace(coalesce(p_placa, ''), '[\s-]', '', 'g'));
begin
  select * into c from public.clientes where user_id = auth.uid();
  if not found then raise exception 'Cadastro não encontrado.'; end if;
  if pl = '' then raise exception 'Informe a placa.'; end if;
  if exists (select 1 from public.veiculos where placa = pl) then
    raise exception 'Essa placa já está vinculada a um cadastro. Fale com a equipe.';
  end if;
  insert into public.veiculos (cliente_id, placa, modelo) values (c.id, pl, coalesce(p_modelo, ''));
end $$;

-- Administrativo: entrega o veículo, calcula o valor (promoções) e lança no caixa
create or replace function public.entregar_veiculo(p_fila uuid, p_forma text)
returns numeric language plpgsql security definer set search_path = public as $$
declare
  f public.fila%rowtype;
  c public.clientes%rowtype;
  v public.veiculos%rowtype;
  s public.servicos%rowtype;
  cx public.caixas%rowtype;
  valor numeric;
  gratis boolean := false;
  aniv boolean := false;
  agora timestamp := (now() at time zone 'America/Fortaleza');
  hoje date := (now() at time zone 'America/Fortaleza')::date;
  ano int := extract(year from (now() at time zone 'America/Fortaleza'))::int;
  y int;
  ini date;
begin
  if not public.is_admin() then raise exception 'Sem permissão.'; end if;
  select * into f from public.fila where id = p_fila for update;
  if not found then raise exception 'Esse veículo não está mais na fila.'; end if;
  select * into cx from public.caixas where fechado_em is null order by aberto_em desc limit 1;
  if not found then raise exception 'Abra o caixa para entregar.'; end if;
  valor := f.preco;
  select * into s from public.servicos where id = f.servico_id;

  if f.cliente_id is not null then
    select * into c from public.clientes where id = f.cliente_id;
    select * into v from public.veiculos where id = f.veiculo_id;

    -- Brinde de aniversário: lavagem completa grátis por 7 dias a partir do aniversário (1 vez por ano)
    if coalesce(s.completa, false) and c.nasc is not null then
      for y in ano - 1 .. ano loop
        ini := (make_date(y, 1, 1) + make_interval(months => extract(month from c.nasc)::int - 1, days => extract(day from c.nasc)::int - 1))::date;
        if hoje between ini and ini + 6 and c.aniv_ano is distinct from y then
          valor := 0; gratis := true; aniv := true;
          update public.clientes set aniv_ano = y where id = c.id;
          exit;
        end if;
      end loop;
    end if;

    -- Cartão fidelidade: 10ª lavagem simples grátis (segunda a sexta, das 8h às 17h)
    if not aniv and v.id is not null then
      if coalesce(s.simples, false) and v.ciclo >= 9
         and extract(isodow from agora) between 1 and 5
         and extract(hour from agora) >= 8 and extract(hour from agora) < 17 then
        valor := 0; gratis := true;
        update public.veiculos set ciclo = 0 where id = v.id;
      else
        update public.veiculos set ciclo = least(9, ciclo + 1) where id = v.id;
      end if;
    end if;
  end if;

  insert into public.lancamentos (caixa_id, tipo, cliente_id, veiculo_id, nome, placa, servico, valor, forma, gratis, aniv, recebido_em)
  values (cx.id, 'lav', f.cliente_id, f.veiculo_id, f.nome, f.placa, f.servico, valor, p_forma, gratis, aniv, f.recebido_em);
  delete from public.fila where id = p_fila;
  return valor;
end $$;

-- Administrativo: cancela um lançamento e devolve o ponto do cartão
create or replace function public.cancelar_lancamento(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare l public.lancamentos%rowtype;
begin
  if not public.is_admin() then raise exception 'Sem permissão.'; end if;
  select * into l from public.lancamentos where id = p_id;
  if not found then return; end if;
  if l.tipo = 'lav' then
    if l.aniv then
      update public.clientes set aniv_ano = null where id = l.cliente_id;
    elsif l.veiculo_id is not null then
      update public.veiculos set ciclo = case when l.gratis then 9 else greatest(0, ciclo - 1) end where id = l.veiculo_id;
    end if;
  end if;
  delete from public.lancamentos where id = p_id;
end $$;

-- Serviços de exemplo (troque os valores depois, no app) -----------------
insert into public.servicos (nome, preco, simples, completa) values
  ('Lavagem simples', 30, true, false),
  ('Lavagem completa', 50, false, true),
  ('Lavagem com cera', 70, false, false),
  ('Higienização interna', 120, false, false);
