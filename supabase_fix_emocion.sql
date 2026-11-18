-- Agregar estados emocionales a las señales (Bien, Neutral, Frustrado, Cansado, Motivado)
-- Pegá esto en Supabase > SQL Editor > New query > Run

-- 1. Actualizar CHECK de value en signals
alter table public.signals drop constraint if exists signals_value_check;
alter table public.signals add constraint signals_value_check
  check (value in ('seguro','parcial','perdido','lento','adecuado','rapido','bien','neutral','frustrado','cansado','motivado'));

-- 2. Actualizar CHECK de kind (agregar 'emocion')
alter table public.signals drop constraint if exists signals_kind_check;
alter table public.signals add constraint signals_kind_check
  check (kind in ('comprension','ritmo','emocion'));
