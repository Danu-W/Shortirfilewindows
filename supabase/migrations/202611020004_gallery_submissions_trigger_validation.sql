create or replace function public.validate_gallery_submission()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.galleries g where g.id = new.gallery_id) then
    raise exception 'Gallery does not exist';
  end if;
  return new;
end $$;

drop trigger if exists trg_validate_gallery_submission on public.gallery_submissions;
create trigger trg_validate_gallery_submission
  before insert on public.gallery_submissions
  for each row execute function public.validate_gallery_submission();

drop policy if exists "Anyone can submit photos to a gallery"
  on public.gallery_submissions;

create policy "Anyone can submit photos to a gallery"
  on public.gallery_submissions for insert to anon, authenticated
  with check (true);
