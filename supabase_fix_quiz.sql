-- ============================================================
-- SIKIRO — Quiz/Cuestionario para Checkpoints
-- Tablas, RLS y RPCs para preguntas y respuestas
-- Pegá esto en Supabase > SQL Editor > New query > Run
-- ============================================================

-- 1. Tabla de preguntas del cuestionario
create table if not exists public.quiz_questions (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  question text not null,
  qtype text not null check (qtype in ('multiple', 'boolean')),
  options jsonb not null default '[]'::jsonb,
  correct_answer text not null,
  time_limit int not null default 60,
  order_num int not null default 0,
  created_at timestamptz not null default now()
);

-- 2. Tabla de respuestas de los alumnos
create table if not exists public.quiz_answers (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.quiz_questions(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  student_id uuid not null,
  answer text not null,
  is_correct boolean not null default false,
  ts timestamptz not null default now()
);

-- 3. RLS
alter table public.quiz_questions enable row level security;
alter table public.quiz_answers enable row level security;

-- Docente: puede gestionar preguntas de sus clases
create policy "quiz_questions_teacher_all" on public.quiz_questions
  for all using (
    exists (select 1 from public.classes c where c.id = class_id and c.teacher_id = auth.uid())
  );

-- Alumno: puede leer preguntas de clases en las que participa
create policy "quiz_questions_student_read" on public.quiz_questions
  for select using (
    exists (select 1 from public.class_participants cp where cp.class_id = quiz_questions.class_id and cp.user_id = auth.uid())
  );

-- Docente: puede leer respuestas de sus clases
create policy "quiz_answers_teacher_read" on public.quiz_answers
  for select using (
    exists (select 1 from public.classes c where c.id = class_id and c.teacher_id = auth.uid())
  );

-- Alumno: puede insertar sus propias respuestas
create policy "quiz_answers_student_insert" on public.quiz_answers
  for insert with check (student_id = auth.uid());

-- Alumno: puede leer sus propias respuestas
create policy "quiz_answers_student_read" on public.quiz_answers
  for select using (student_id = auth.uid());

-- 4. RPC: Guardar preguntas del cuestionario
create or replace function public.save_quiz_questions(p_class_id uuid, p_questions jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.classes where id = p_class_id and teacher_id = auth.uid()) then
    raise exception 'No tienes permiso para esta clase';
  end if;
  delete from public.quiz_questions where class_id = p_class_id;
  insert into public.quiz_questions (class_id, question, qtype, options, correct_answer, time_limit, order_num)
  select p_class_id, q->>'question', q->>'type', q->'options', q->>'correct', (q->>'timeLimit')::int, (q->>'order')::int
  from jsonb_array_elements(p_questions) as q;
end;
$$;

-- 5. RPC: Obtener preguntas del cuestionario
create or replace function public.get_quiz_questions(p_class_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return coalesce(
    (select jsonb_agg(jsonb_build_object(
      'id', q.id,
      'question', q.question,
      'type', q.qtype,
      'options', q.options,
      'correct', q.correct_answer,
      'timeLimit', q.time_limit
    ) order by q.order_num)
    from public.quiz_questions q where q.class_id = p_class_id),
    '[]'::jsonb
  );
end;
$$;

-- 6. RPC: Guardar respuesta del alumno
create or replace function public.save_quiz_answer(p_question_id uuid, p_answer text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_class_id uuid;
  v_correct text;
  v_is_correct boolean;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  select class_id, correct_answer into v_class_id, v_correct
  from public.quiz_questions where id = p_question_id;
  if v_class_id is null then raise exception 'Pregunta no encontrada'; end if;
  if not exists (select 1 from public.class_participants where class_id = v_class_id and user_id = auth.uid()) then
    raise exception 'No participas de esta clase';
  end if;
  v_is_correct := (upper(trim(p_answer)) = upper(trim(v_correct)));
  insert into public.quiz_answers (question_id, class_id, student_id, answer, is_correct)
  values (p_question_id, v_class_id, auth.uid(), p_answer, v_is_correct);
end;
$$;

-- 7. RPC: Obtener resultados del quiz para el reporte
create or replace function public.get_quiz_results(p_class_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return coalesce(
    (select jsonb_agg(jsonb_build_object(
      'question', q.question,
      'total_answers', (select count(*) from public.quiz_answers a where a.question_id = q.id),
      'correct_answers', (select count(*) from public.quiz_answers a where a.question_id = q.id and a.is_correct),
      'false_comprehension', (select count(*) from public.quiz_answers a where a.question_id = q.id and a.is_correct = false)
    ) order by q.order_num)
    from public.quiz_questions q where q.class_id = p_class_id),
    '[]'::jsonb
  );
end;
$$;

-- 8. Permisos
grant execute on function public.save_quiz_questions(uuid, jsonb) to authenticated;
grant execute on function public.get_quiz_questions(uuid) to authenticated;
grant execute on function public.save_quiz_answer(uuid, text) to authenticated;
grant execute on function public.get_quiz_results(uuid) to authenticated;