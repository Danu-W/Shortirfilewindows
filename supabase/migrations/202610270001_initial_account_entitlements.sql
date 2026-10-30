create table if not exists public.user_preferences (
  user_id uuid primary key references auth.users (id) on delete cascade,
  language text not null default 'id' check (language in ('id', 'en')),
  updated_at timestamptz not null default now()
);

alter table public.user_preferences enable row level security;
grant select, insert, update on public.user_preferences to authenticated;

create policy "Users can read their own preferences"
  on public.user_preferences for select to authenticated
  using (auth.uid() = user_id);

create policy "Users can create their own preferences"
  on public.user_preferences for insert to authenticated
  with check (auth.uid() = user_id);

create policy "Users can update their own preferences"
  on public.user_preferences for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.billing_entitlements (
  user_id uuid primary key references auth.users (id) on delete cascade,
  entitlement text not null default 'pro',
  status text not null check (status in ('active', 'grace_period', 'canceled', 'expired', 'past_due')),
  provider text not null check (provider in ('app_store', 'google_play', 'stripe')),
  product_id text not null,
  expires_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.billing_entitlements enable row level security;
grant select on public.billing_entitlements to authenticated;

create policy "Users can read their own subscription status"
  on public.billing_entitlements for select to authenticated
  using (auth.uid() = user_id);

-- Deliberately no client insert/update/delete policies. A trusted billing webhook
-- or server function must verify provider transactions before changing entitlements.
