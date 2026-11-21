create table if not exists public.ammir_visitor_events (
  id uuid primary key default gen_random_uuid(),
  event_key uuid not null unique,
  visitor_id uuid not null,
  session_id uuid not null,
  user_id uuid references auth.users(id) on delete set null,
  site text not null check (site in ('app','website')),
  event_name text not null check (event_name in ('page_view','login_success','signup_success')),
  page_path text not null check (char_length(page_path) <= 512),
  page_title text check (page_title is null or char_length(page_title) <= 160),
  referrer_domain text check (referrer_domain is null or char_length(referrer_domain) <= 255),
  device_type text not null default 'unknown' check (device_type in ('mobile','tablet','desktop','unknown')),
  country_code text check (country_code is null or char_length(country_code) = 2),
  created_at timestamptz not null default now()
);

create index if not exists ammir_visitor_events_created_at_idx
  on public.ammir_visitor_events (created_at desc);
create index if not exists ammir_visitor_events_visitor_created_idx
  on public.ammir_visitor_events (visitor_id, created_at desc);
create index if not exists ammir_visitor_events_user_created_idx
  on public.ammir_visitor_events (user_id, created_at desc)
  where user_id is not null;
create index if not exists ammir_visitor_events_site_created_idx
  on public.ammir_visitor_events (site, created_at desc);

alter table public.ammir_visitor_events enable row level security;
revoke all on table public.ammir_visitor_events from public, anon, authenticated;
grant all on table public.ammir_visitor_events to service_role;

comment on table public.ammir_visitor_events is
  'AMMIR consent-based, privacy-minimised visitor analytics. No raw IP, full user-agent, query string, or precise location is stored. Read only through the admin-guarded analytics Edge Function.';
