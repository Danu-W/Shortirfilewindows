create extension if not exists pg_cron with schema cron;

select cron.schedule(
  'cleanup-expired-galleries',
  '0 */6 * * *',
  $$
  delete from public.galleries
  where expires_at is not null
    and (expires_at + interval '3 days') < now();
  $$
);
