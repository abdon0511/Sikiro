-- ============================================================
-- Sikiro - Setup completo para proyecto Supabase NUEVO
-- Pegá TODO este archivo en: Supabase > SQL Editor > New query > Run
-- ============================================================

-- 1. Extensión para UUIDs
create extension if not exists pgcrypto;

-- 2. TABLAS
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('teacher','student')),
  display_name text,
  created_at timestamptz default now()
);

create table if not exists public.classes (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  course text not null,
  topic text not null,
  code text not null unique,
  status text not null default 'waiting' check (status in ('waiting','active','paused','finished')),
  created_at timestamptz default now(),
  finished_at timestamptz
);

create table if not exists public.class_participants (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz default now(),
  unique (class_id, user_id)
);

create table if not exists public.signals (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete set null,
  kind text not null check (kind in ('comprension','ritmo')),
  value text not null check (value in ('seguro','parcial','perdido','lento','adecuado','rapido')),
  created_at timestamptz default now()
);

create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  content text not null,
  created_at timestamptz default now()
);

-- 3. ROW LEVEL SECURITY
alter table public.profiles enable row level security;
alter table public.classes enable row level security;
alter table public.class_participants enable row level security;
alter table public.signals enable row level security;
alter table public.questions enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select to authenticated using (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- El resto de tablas SOLO se accede vía RPC (SECURITY DEFINER),
-- por eso no creamos policies de acceso directo: denegado por defecto.
-- Si necesitás leer classes directo para debug, agregá una policy temporal.

-- 4. FUNCIONES RPC (SECURITY DEFINER = corren con permisos del dueño)
-- Helper interno para generar código de 4 caracteres único
create or replace function public.generate_class_code()
returns text language plpgsql as $$
declare
  chars text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  result text;
  i int;
begin
  loop
    result := '';
    for i in 1..4 loop
      result := result || substr(chars, 1 + floor(random() * length(chars))::int, 1);
    end loop;
    exit when not exists (select 1 from public.classes where code = result);
  end loop;
  return result;
end;
$$;

create or replace function public.create_sikiro_class(p_course text, p_topic text)
returns table(class_id uuid, code text)
language plpgsql security definer set search_path = public as $$
declare
  v_code text;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'teacher') then
    raise exception 'Solo docentes pueden crear clases';
  end if;
  v_code := public.generate_class_code();
  return query insert into public.classes(teacher_id, course, topic, code, status)
    values (auth.uid(), p_course, p_topic, v_code, 'waiting')
    returning id, public.classes.code;
end;
$$;

create or replace function public.join_sikiro_class(p_code text)
returns table(class_id uuid, course text, topic text, code text, status text)
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  return query
    select c.id, c.course, c.topic, c.code, c.status
    from public.classes c
    where c.code = upper(trim(p_code)) and c.status <> 'finished'
    limit 1;
  if not found then raise exception 'Clase no encontrada o ya finalizada'; end if;

  insert into public.class_participants(class_id, user_id)
    select id, auth.uid() from public.classes where code = upper(trim(p_code))
    on conflict (class_id, user_id) do nothing;
end;
$$;

create or replace function public.set_sikiro_class_status(p_class_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.classes where id = p_class_id and teacher_id = auth.uid()) then
    raise exception 'No tienes permiso para esta clase';
  end if;
  update public.classes set status = p_status where id = p_class_id;
end;
$$;

create or replace function public.finish_sikiro_class(p_class_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.classes where id = p_class_id and teacher_id = auth.uid()) then
    raise exception 'No tienes permiso para esta clase';
  end if;
  update public.classes set status = 'finished', finished_at = now() where id = p_class_id;
end;
$$;

create or replace function public.send_sikiro_signal(p_class_id uuid, p_kind text, p_value text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  if not exists (select 1 from public.class_participants where class_id = p_class_id and user_id = auth.uid()) then
    raise exception 'No participas de esta clase';
  end if;
  insert into public.signals(class_id, user_id, kind, value)
    values (p_class_id, auth.uid(), p_kind, p_value);
end;
$$;

create or replace function public.send_sikiro_question(p_class_id uuid, p_content text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  if not exists (select 1 from public.class_participants where class_id = p_class_id and user_id = auth.uid()) then
    raise exception 'No participas de esta clase';
  end if;
  -- Pregunta 100% anónima: NO guardamos user_id
  insert into public.questions(class_id, content) values (p_class_id, p_content);
end;
$$;

create or replace function public.get_sikiro_stats(p_class_id uuid)
returns table(
  seguro bigint, parcial bigint, perdido bigint,
  lento bigint, adecuado bigint, rapido bigint,
  total_students bigint, questions jsonb
)
language plpgsql security definer set search_path = public as $$
begin
  return query
    select
      count(*) filter (where s.value = 'seguro')::bigint,
      count(*) filter (where s.value = 'parcial')::bigint,
      count(*) filter (where s.value = 'perdido')::bigint,
      count(*) filter (where s.value = 'lento')::bigint,
      count(*) filter (where s.value = 'adecuado')::bigint,
      count(*) filter (where s.value = 'rapido')::bigint,
      (select count(*)::bigint from public.class_participants where class_id = p_class_id),
      coalesce(
        (select jsonb_agg(q.content order by q.created_at desc) from public.questions q where q.class_id = p_class_id),
        '[]'::jsonb
      )
    from public.signals s where s.class_id = p_class_id;
end;
$$;

-- 5. Permisos de ejecución para usuarios autenticados
grant execute on function public.create_sikiro_class(text, text) to authenticated;
grant execute on function public.join_sikiro_class(text) to authenticated;
grant execute on function public.set_sikiro_class_status(uuid, text) to authenticated;
grant execute on function public.finish_sikiro_class(uuid) to authenticated;
grant execute on function public.send_sikiro_signal(uuid, text, text) to authenticated;
grant execute on function public.send_sikiro_question(uuid, text) to authenticated;
grant execute on function public.get_sikiro_stats(uuid) to authenticated;
