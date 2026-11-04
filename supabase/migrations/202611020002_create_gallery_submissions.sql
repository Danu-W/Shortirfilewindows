create table if not exists public.gallery_submissions (
  id uuid primary key default gen_random_uuid(),
  gallery_id uuid not null references public.galleries (id) on delete cascade,
  client_name text,
  files jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.gallery_submissions enable row level security;
grant select, insert on public.gallery_submissions to anon, authenticated;

create policy "Anyone can submit photos to a gallery"
  on public.gallery_submissions for insert to anon, authenticated
  with check (exists (
    select 1 from public.galleries g where g.id = gallery_id
  ));

create policy "Owner can read submissions of their galleries"
  on public.gallery_submissions for select to authenticated
  using (exists (
    select 1 from public.galleries g
    where g.id = gallery_id and g.user_id = auth.uid()
  ));
