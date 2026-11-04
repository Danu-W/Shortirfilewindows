alter table public.galleries
  add column if not exists session_time text;
