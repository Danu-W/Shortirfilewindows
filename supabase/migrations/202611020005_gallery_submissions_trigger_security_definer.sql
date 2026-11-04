create or replace function public.validate_gallery_submission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.galleries g where g.id = new.gallery_id) then
    raise exception 'Gallery does not exist';
  end if;
  return new;
end $$;
