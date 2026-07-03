-- ============================================================
-- Reviews table for the portfolio site
-- Run this once in Supabase: SQL Editor -> New query -> paste -> Run
-- ============================================================

create table public.reviews (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  name        text not null check (char_length(name) between 2 and 80),
  role        text check (char_length(role) <= 120),
  rating      int  not null check (rating between 1 and 5),
  message     text not null check (char_length(message) between 10 and 1000),
  approved    boolean not null default false
);

-- Row Level Security: the anon key can only read approved reviews
-- and can only insert rows that start unapproved. Nobody can update
-- or delete through the public API.
alter table public.reviews enable row level security;

create policy "public reads approved reviews only"
  on public.reviews for select
  using (approved = true);

create policy "anyone can submit an unapproved review"
  on public.reviews for insert
  with check (approved = false);

-- ============================================================
-- Moderation: approve a review from the Supabase dashboard
-- (Table Editor -> reviews -> flip `approved` to true), or:
--
--   update public.reviews set approved = true where id = '<uuid>';
--
-- Seeding real testimonials you already have (e.g. from clients):
--
--   insert into public.reviews (name, role, rating, message, approved)
--   values ('Client Name', 'Founder, Company', 5, 'Real quote here.', true);
--
-- Never seed invented reviews — real ones only.
-- ============================================================
