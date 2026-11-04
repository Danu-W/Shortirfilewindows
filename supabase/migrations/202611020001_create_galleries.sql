create table if not exists public.galleries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  drive_folder_id text not null,
  pin text,
  max_selections integer,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.galleries enable row level security;
grant select, insert, update, delete on public.galleries to authenticated;

create policy "Users can read their own galleries"
  on public.galleries for select to authenticated
  using (auth.uid() = user_id);

create policy "Users can create their own galleries"
  on public.galleries for insert to authenticated
  with check (auth.uid() = user_id);

create policy "Users can update their own galleries"
  on public.galleries for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete their own galleries"
  on public.galleries for delete to authenticated
  using (auth.uid() = user_id);
