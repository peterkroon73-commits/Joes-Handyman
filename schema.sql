-- =============================================================================
-- Joe's Handyman — Record-Keeping Database Schema
-- Target: Supabase (PostgreSQL)
--
-- How to use:
--   1. Open your Supabase project -> SQL Editor -> New query.
--   2. Paste this entire file and click "Run".
--   3. Copy your Project URL and anon/public API key (Project Settings ->
--      API) into the SUPABASE_URL / SUPABASE_ANON_KEY constants in index.html.
-- =============================================================================

-- Required for gen_random_uuid()
create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- invoices
-- Digitally generated invoices created via the Invoicing Generator tab.
-- line_items is stored as JSONB so an invoice can hold any number of rows,
-- e.g. [{"description":"Fix leaking tap","qty":1,"rate":120,"amount":120}]
-- -----------------------------------------------------------------------------
create table if not exists public.invoices (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  client_name  text not null,
  client_email text,
  line_items   jsonb not null default '[]'::jsonb,
  total_amount numeric(12, 2) not null default 0,
  status       text not null default 'Draft'
               check (status in ('Draft', 'Sent', 'Paid', 'Overdue'))
);

comment on table public.invoices is 'Digitally generated client invoices with line items and status.';

-- -----------------------------------------------------------------------------
-- manual_income
-- Quick log of cash-in-hand or external payments that did not go through the
-- Invoicing Generator (e.g. cash jobs, bank transfers logged after the fact).
-- -----------------------------------------------------------------------------
create table if not exists public.manual_income (
  id             uuid primary key default gen_random_uuid(),
  date           date not null default current_date,
  client_name    text not null,
  description    text,
  amount         numeric(12, 2) not null default 0,
  payment_method text not null default 'Cash'
                 check (payment_method in ('Cash', 'Bank Transfer', 'Card', 'PayPal', 'Other'))
);

comment on table public.manual_income is 'Manually logged income not raised as a formal invoice.';

-- -----------------------------------------------------------------------------
-- expenses
-- Day-to-day running costs and business expenses, with an optional link to a
-- photographed/scanned receipt (e.g. a Supabase Storage public URL).
-- -----------------------------------------------------------------------------
create table if not exists public.expenses (
  id          uuid primary key default gen_random_uuid(),
  date        date not null default current_date,
  category    text not null default 'General'
              check (category in ('Materials', 'Fuel', 'Tools', 'Insurance', 'Vehicle', 'Advertising', 'General', 'Other')),
  description text,
  amount      numeric(12, 2) not null default 0,
  receipt_url text
);

comment on table public.expenses is 'Business running costs and expenses, optionally linked to a receipt image/file.';

-- -----------------------------------------------------------------------------
-- Helpful indexes for the Financial Overview dashboard queries
-- -----------------------------------------------------------------------------
create index if not exists idx_invoices_status      on public.invoices (status);
create index if not exists idx_invoices_created_at   on public.invoices (created_at);
create index if not exists idx_manual_income_date    on public.manual_income (date);
create index if not exists idx_expenses_date         on public.expenses (date);

-- -----------------------------------------------------------------------------
-- Row Level Security
-- This app is designed as a single-owner tool using the public anon key, so
-- RLS is enabled with permissive policies allowing full read/write access.
-- If you add authentication later, tighten these policies to filter by
-- auth.uid() instead of allowing all access.
-- -----------------------------------------------------------------------------
alter table public.invoices      enable row level security;
alter table public.manual_income enable row level security;
alter table public.expenses      enable row level security;

drop policy if exists "Allow all access to invoices" on public.invoices;
create policy "Allow all access to invoices"
  on public.invoices for all
  using (true)
  with check (true);

drop policy if exists "Allow all access to manual_income" on public.manual_income;
create policy "Allow all access to manual_income"
  on public.manual_income for all
  using (true)
  with check (true);

drop policy if exists "Allow all access to expenses" on public.expenses;
create policy "Allow all access to expenses"
  on public.expenses for all
  using (true)
  with check (true);
