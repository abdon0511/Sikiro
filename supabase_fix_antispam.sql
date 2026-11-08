-- Anti-spam de preguntas POR ALUMNO (sin romper el anonimato para el docente)
-- El docente nunca ve sender_id; solo se usa para limitar a 5/min por alumno.
-- Pegá esto en Supabase > SQL Editor > New query > Run

alter table public.questions add column if not exists sender_id uuid references public.profiles(id) on delete set null;

-- CHECK de longitud (si aún no lo corriste)
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'questions_content_len') then
    alter table public.questions drop constraint questions_content_len;
  end if;
end $$;
alter table public.questions
  add constraint questions_content_len check (char_length(content) between 1 and 200);

create or replace function public.send_sikiro_question(p_class_id uuid, p_content text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_text text := trim(p_content);
  v_lower text := lower(trim(p_content));
  v_word text;
  v_banned text[] := array['mierda','puta','puto','carajo','pendejo','boludo','cabrón','cabron','chingada','chingado','verga','marica','idiota','estúpido','estupido','imbécil','imbecil'];
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  if char_length(v_text) < 1 or char_length(v_text) > 200 then
    raise exception 'La pregunta debe tener entre 1 y 200 caracteres';
  end if;
  if v_text ~* 'https?://|www\.' then
    raise exception 'No se permiten enlaces en las preguntas';
  end if;
  foreach v_word in array v_banned loop
    if position(v_word in v_lower) > 0 then
      raise exception 'Tu pregunta contiene palabras no permitidas';
    end if;
  end loop;
  if not exists (select 1 from public.class_participants where class_id = p_class_id and user_id = auth.uid()) then
    raise exception 'No participas de esta clase';
  end if;
  -- Límite por alumno: 5 preguntas por minuto
  if (select count(*) from public.questions where sender_id = auth.uid() and created_at > now() - interval '1 minute') >= 5 then
    raise exception 'Espera un momento antes de enviar otra pregunta';
  end if;
  -- Límite por clase (respaldo): 20 por minuto
  if (select count(*) from public.questions where class_id = p_class_id and created_at > now() - interval '1 minute') >= 20 then
    raise exception 'La clase está enviando muchas preguntas, espera un momento';
  end if;
  insert into public.questions(class_id, sender_id, content) values (p_class_id, auth.uid(), v_text);
end;
$$;

grant execute on function public.send_sikiro_question(uuid, text) to authenticated;
