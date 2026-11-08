-- Lista de clases del docente (incluye finished_at para duración del reporte)
-- Pegá esto en Supabase > SQL Editor > New query > Run

create or replace function public.list_sikiro_classes()
returns table(class_id uuid, code text, course text, topic text, status text, created_at timestamptz, finished_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  return query
    select c.id, c.code, c.course, c.topic, c.status, c.created_at, c.finished_at
    from public.classes c
    where c.teacher_id = auth.uid()
    order by c.created_at desc
    limit 10;
end;
$$;

grant execute on function public.list_sikiro_classes() to authenticated;
