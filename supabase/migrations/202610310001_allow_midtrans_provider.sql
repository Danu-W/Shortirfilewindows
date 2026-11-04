alter table public.billing_entitlements
  drop constraint if exists billing_entitlements_provider_check;

alter table public.billing_entitlements
  add constraint billing_entitlements_provider_check
  check (provider in ('app_store', 'google_play', 'stripe', 'xendit', 'midtrans'));
