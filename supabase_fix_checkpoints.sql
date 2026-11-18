-- started_at para calcular checkpoints por clase + RPC devuelve el checkpoint asignado
-- Pegá esto en Supabase > SQL Editor > New query > Run

alter table public.classes add column if not exists started_at timestamptz;

-- set_sikiro_class_status marca started_at al activar
create or replace function public.set_sikiro_class_status(p_class_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.classes where id = p_class_id and teacher_id = auth.uid()) then
    raise exception 'No tienes permiso para esta clase';
  end if;
  if p_status = 'active' then
    update public.classes set status = p_status, started_at = coalesce(started_at, now()) where id = p_class_id;
  else
    update public.classes set status = p_status where id = p_class_id;
  end if;
end;
$$;

-- join devuelve started_at para que el alumno sepa el checkpoint base
create or replace function public.join_sikiro_class(p_code text)
returns table(class_id uuid, course text, topic text, code text, status text, started_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_class_id uuid;
  v_started timestamptz;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;

  select c.id, c.started_at into v_class_id, v_started
  from public.classes c
  where c.code = upper(trim(p_code)) and c.status <> 'finished'
  limit 1;

  if v_class_id is null then
    raise exception 'Clase no encontrada o ya finalizada';
  end if;

  insert into public.class_participants(class_id, user_id)
  values (v_class_id, auth.uid())
  on conflict (class_id, user_id) do nothing;

  return query
    select c.id, c.course, c.topic, c.code, c.status, c.started_at
    from public.classes c
    where c.id = v_class_id;
end;
$$;

-- send_sikiro_signal calcula el checkpoint en servidor y lo devuelve
create or replace function public.send_sikiro_signal(p_class_id uuid, p_kind text, p_value text, p_checkpoint int default 1)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_started timestamptz;
  v_cp int;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  if not exists (select 1 from public.class_participants where class_id = p_class_id and user_id = auth.uid()) then
    raise exception 'No participas de esta clase';
  end if;
  if exists (
    select 1 from public.signals
    where class_id = p_class_id and user_id = auth.uid() and kind = p_kind
      and created_at > now() - interval '20 minutes'
  ) then
    raise exception 'Ya votaste. Próximo voto en unos minutos (cada 20 min)';
  end if;
  select started_at into v_started from public.classes where id = p_class_id;
  if v_started is null then v_cp := 1;
  else v_cp := greatest(1, floor(extract(epoch from (now() - v_started)) / 1200)::int + 1);
  end if;
  insert into public.signals(class_id, user_id, kind, value, checkpoint)
    values (p_class_id, auth.uid(), p_kind, p_value, v_cp);
  return v_cp;
end;
$$;

grant execute on function public.send_sikiro_signal(uuid, text, text, int) to authenticated;
grant execute on function public.join_sikiro_class(text) to authenticated;
