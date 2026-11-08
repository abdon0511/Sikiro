-- Formulario de contacto guardado en Supabase (visible en Table Editor > contacts)
-- Pegá esto en Supabase > SQL Editor > New query > Run

create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 50),
  email text not null check (char_length(email) between 1 and 80),
  message text not null check (char_length(message) between 1 and 500),
  created_at timestamptz default now()
);

alter table public.contacts enable row level security;

drop policy if exists "contacts_insert_public" on public.contacts;
create policy "contacts_insert_public" on public.contacts
  for insert to anon, authenticated with check (true);

drop policy if exists "contacts_select_auth" on public.contacts;
create policy "contacts_select_auth" on public.contacts
  for select to authenticated using (true);

create or replace function public.send_contact_message(p_name text, p_email text, p_message text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_name text := trim(p_name);
  v_email text := trim(p_email);
  v_msg text := trim(p_message);
begin
  if char_length(v_name) < 1 or char_length(v_name) > 50 then
    raise exception 'El nombre debe tener entre 1 y 50 caracteres';
  end if;
  if char_length(v_email) < 1 or char_length(v_email) > 80 or v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then
    raise exception 'Correo no válido (máx. 80)';
  end if;
  if char_length(v_msg) < 1 or char_length(v_msg) > 500 then
    raise exception 'El mensaje debe tener entre 1 y 500 caracteres';
  end if;
  -- Anti-spam: 3 mensajes por minuto por correo
  if (select count(*) from public.contacts where lower(email) = lower(v_email) and created_at > now() - interval '1 minute') >= 3 then
    raise exception 'Espera un momento antes de enviar otro mensaje';
  end if;
  insert into public.contacts(name, email, message) values (v_name, v_email, v_msg);
end;
$$;

grant execute on function public.send_contact_message(text, text, text) to anon, authenticated;
grant insert on public.contacts to anon, authenticated;
