-- Fix 403 en profiles: dar permisos + asegurar policies
-- Pegá esto en Supabase > SQL Editor > New query > Run

grant usage on schema public to authenticated;
grant select, insert, update on public.profiles to authenticated;

-- Re-crear policies por si faltan
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select to authenticated using (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);
