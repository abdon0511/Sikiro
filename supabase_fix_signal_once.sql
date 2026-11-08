-- 1 voto por alumno cada 20 minutos (comprensión / ritmo por separado)
-- Pegá esto en Supabase > SQL Editor > New query > Run

create or replace function public.send_sikiro_signal(p_class_id uuid, p_kind text, p_value text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  if not exists (select 1 from public.class_participants where class_id = p_class_id and user_id = auth.uid()) then
    raise exception 'No participas de esta clase';
  end if;
  -- Un voto por tipo cada 20 minutos (ventana móvil desde tu último voto)
  if exists (
    select 1 from public.signals
    where class_id = p_class_id and user_id = auth.uid() and kind = p_kind
      and created_at > now() - interval '20 minutes'
  ) then
    raise exception 'Ya votaste. Próximo voto en unos minutos (cada 20 min)';
  end if;
  insert into public.signals(class_id, user_id, kind, value)
    values (p_class_id, auth.uid(), p_kind, p_value);
end;
$$;

grant execute on function public.send_sikiro_signal(uuid, text, text) to authenticated;
