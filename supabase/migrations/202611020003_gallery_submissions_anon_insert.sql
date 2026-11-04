create or replace function public.gallery_exists(gid uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (select 1 from public.galleries g where g.id = gid)
$$;

grant execute on function public.gallery_exists(uuid) to anon, authenticated;

drop policy if exists "Anyone can submit photos to a gallery"
  on public.gallery_submissions;

create policy "Anyone can submit photos to a gallery"
  on public.gallery_submissions for insert to anon, authenticated
  with check (public.gallery_exists(gallery_id));
