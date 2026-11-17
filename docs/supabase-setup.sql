-- Настройка базы Supabase для синхронизации приложения «Вдвоём».
-- Выполнить один раз: Supabase → SQL Editor → New query → вставить весь файл → Run.

-- Пара (вы вдвоём) и её участники.
create table if not exists public.couples (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);

-- role: 'owner' (владелец) или 'partner' (партнёр). От роли зависит,
-- какие вкладки и функции видит человек в приложении.
create table if not exists public.couple_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  couple_id uuid not null references public.couples(id) on delete cascade,
  role text not null check (role in ('owner', 'partner')),
  display_name text,
  unique (couple_id, role)
);

-- Пара текущего пользователя.
create or replace function public.my_couple_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select couple_id from public.couple_members where user_id = auth.uid()
$$;

-- Все синхронизируемые данные приложения лежат в одной таблице.
-- kind: тип записи (например "nutrition.meal"), payload: сами данные в JSON.
create table if not exists public.records (
  id uuid primary key,
  couple_id uuid not null default public.my_couple_id() references public.couples(id) on delete cascade,
  kind text not null,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  author_id uuid default auth.uid(),
  server_updated_at timestamptz not null default now()
);

create index if not exists records_couple_server_updated_idx
  on public.records (couple_id, server_updated_at);

-- Побеждает последнее изменение; сервер ставит своё время записи.
create or replace function public.records_before_write()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' then
    if new.updated_at < old.updated_at then
      return null; -- пришла более старая версия, оставляем текущую
    end if;
    new.couple_id := old.couple_id;
  end if;
  new.server_updated_at := clock_timestamp();
  return new;
end
$$;

drop trigger if exists records_before_write on public.records;
create trigger records_before_write
  before insert or update on public.records
  for each row execute function public.records_before_write();

-- Доступ: каждый видит только данные своей пары.
alter table public.couples enable row level security;
alter table public.couple_members enable row level security;
alter table public.records enable row level security;

drop policy if exists "couple: read own" on public.couples;
create policy "couple: read own" on public.couples
  for select to authenticated using (id = public.my_couple_id());

drop policy if exists "members: read own couple" on public.couple_members;
create policy "members: read own couple" on public.couple_members
  for select to authenticated using (couple_id = public.my_couple_id());

drop policy if exists "members: rename self" on public.couple_members;
create policy "members: rename self" on public.couple_members
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "records: read own couple" on public.records;
create policy "records: read own couple" on public.records
  for select to authenticated using (couple_id = public.my_couple_id());

drop policy if exists "records: insert own couple" on public.records;
create policy "records: insert own couple" on public.records
  for insert to authenticated with check (couple_id = public.my_couple_id());

drop policy if exists "records: update own couple" on public.records;
create policy "records: update own couple" on public.records
  for update to authenticated
  using (couple_id = public.my_couple_id())
  with check (couple_id = public.my_couple_id());

grant select on public.couples, public.couple_members to authenticated;
grant update (display_name) on public.couple_members to authenticated;
grant select, insert, update on public.records to authenticated;
grant execute on function public.my_couple_id() to authenticated;

-- ---------------------------------------------------------------------------
-- ШАГ 2 (выполнить отдельно, после создания двух пользователей в
-- Authentication → Users). Замените почты и имена на свои и запустите:
--
-- with c as (insert into public.couples default values returning id)
-- insert into public.couple_members (user_id, couple_id, role, display_name)
-- select u.id, c.id,
--        case when u.email = 'я@example.com' then 'owner' else 'partner' end,
--        case when u.email = 'я@example.com' then 'Моё имя' else 'Её имя' end
-- from auth.users u, c
-- where u.email in ('я@example.com', 'она@example.com');
