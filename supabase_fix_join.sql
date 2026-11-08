-- Fix: "column reference code is ambiguous" en join_sikiro_class
-- Pegá esto en Supabase > SQL Editor > New query > Run

create or replace function public.join_sikiro_class(p_code text)
returns table(class_id uuid, course text, topic text, code text, status text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_class_id uuid;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;

  select c.id into v_class_id
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
    select c.id, c.course, c.topic, c.code, c.status
    from public.classes c
    where c.id = v_class_id;
end;
$$;

grant execute on function public.join_sikiro_class(text) to authenticated;
